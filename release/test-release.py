#!/usr/bin/env python3
"""Exercise release orchestration with tiny Git repos and a fake GitHub CLI."""

import json
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import time
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parent
VERSION = "1.2.3"

spec = importlib.util.spec_from_file_location("smoke_run", SCRIPTS / "smoke-run.py")
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


class SmokeRunTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="springcabal-smoke-test-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.guard = self.directory / "guard.json"
        self.lock_held = False
        test = self

        class Lease:
            def __enter__(self):
                test.lock_held = True
                return self

            def __exit__(self, *_):
                test.lock_held = False

        class Monitor:
            error = None

            def __init__(self, *_args, **_kwargs):
                self.samples = [{"foreign": [], "cpu_pressure": 0}]

            def stop(self):
                test.assertTrue(test.lock_held, "monitor stopped after releasing engine lease")

        self.monitor = Monitor
        for name, value in [("VerificationLease", Lease), ("GpuMonitor", Monitor),
                            ("wait_for_resources", lambda *_args: (None, None, ["preflight"]))]:
            replacement = patch.object(smoke.verification, name, value)
            replacement.start()
            self.addCleanup(replacement.stop)

    def execute(self, code, seconds=5):
        return smoke.execute([os.sys.executable, "-c", code], seconds, self.guard)

    def test_timeout_is_distinct_from_clean_nonzero_exit(self):
        self.assertEqual(self.execute("import time; time.sleep(30)", seconds=.1), 124)
        self.assertIsNone(json.loads(self.guard.read_text())["error"])
        self.assertEqual(self.execute("raise SystemExit(7)"), 7)
        self.assertEqual(json.loads(self.guard.read_text())["exit"], 7)

    def test_contention_stops_process_before_unlock(self):
        self.monitor.error = RuntimeError("guard unavailable")
        actual_stop = smoke.stop

        def stop(process):
            self.assertTrue(self.lock_held, "engine stopped after releasing lease")
            actual_stop(process)
            self.assertIsNotNone(process.poll())

        with patch.object(smoke, "stop", stop):
            self.assertEqual(self.execute("import time; time.sleep(30)"), 125)
        self.assertIn("contention", json.loads(self.guard.read_text())["error"])

    def test_exited_launcher_does_not_leave_child_running(self):
        child_pid = self.directory / "child.pid"
        code = ("import subprocess,time,pathlib; "
                "p=subprocess.Popen(['sleep','30']); "
                f"pathlib.Path({str(child_pid)!r}).write_text(str(p.pid))")
        self.assertEqual(self.execute(code), 0)
        pid = int(child_pid.read_text())
        # A killed orphan can briefly remain as a zombie until init reaps it.
        stat = Path(f"/proc/{pid}/stat")
        try:
            state = stat.read_text().rsplit(")", 1)[1].split()[0]
        except (FileNotFoundError, ProcessLookupError):
            return
        self.assertEqual(state, "Z")


class SmokeScriptTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="springcabal-smoke-script-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "workspace with spaces"
        release = self.root / "release"
        release.mkdir(parents=True)
        self.script = release / "smoke-test.sh"
        shutil.copy2(SCRIPTS / "smoke-test.sh", self.script)
        failures = self.root / "verification/lib/failures.sh"
        failures.parent.mkdir(parents=True)
        shutil.copy2(SCRIPTS.parent / "verification/lib/failures.sh", failures)
        game = self.root / "launch/games/one"
        game.mkdir(parents=True)
        for variant in ["lua", "wasm"]:
            (game / (variant + ".txt")).write_text("[GAME] { HostPort=8452; }\n")
        self.bundle = self.root / "bundle with spaces"
        (self.bundle / "fonts").mkdir(parents=True)
        (self.bundle / "SpringCabal").touch()
        (self.bundle / "springsettings.cfg").write_text("Shadows = 0\n")
        self.ready, self.resume, self.calls = [self.root / name for name in
                                             ["ready", "resume", "calls.jsonl"]]
        scratch = self.root / "scratch"
        scratch.mkdir()
        self.env = dict(os.environ, SMOKE_TEST_READY=str(self.ready),
                        SMOKE_TEST_RESUME=str(self.resume), SMOKE_TEST_CALLS=str(self.calls),
                        TMPDIR=str(scratch))
        # Model the worker contract; these are shell-control tests, never GPU
        # measurements. Real hardware smoke cases exercise the actual worker.
        (release / "smoke-run.py").write_text('''import json,os,sys,time
from pathlib import Path
import xml.etree.ElementTree as ET
cache=Path(ET.parse(os.environ['FONTCONFIG_FILE']).findtext('cachedir'))
assert cache.is_dir() and os.access(cache,os.W_OK), 'font cache must exist before first Wine startup'
calls=Path(os.environ['SMOKE_TEST_CALLS'])
first=not calls.exists()
with calls.open('a') as stream:stream.write(json.dumps(sys.argv[1:])+'\\n')
if first and os.environ.get('SMOKE_TEST_PAUSE'):
 Path(os.environ['SMOKE_TEST_READY']).touch()
 deadline=time.monotonic()+10
 while not Path(os.environ['SMOKE_TEST_RESUME']).exists():
  if time.monotonic()>deadline:raise RuntimeError('test did not resume worker')
  time.sleep(.01)
Path(sys.argv[sys.argv.index('--guard')+1]).write_text('{}')
print('GL renderer : NVIDIA mock for shell control test')
print('[GR::LogDisplayMode] display-mode set to 1280x720x24bpp.')
print('finished loading and is now ingame')
print('Wasm manifest loaded from WasmMenu/manifest.json')
raise SystemExit(124)
''')

    def command(self, *options):
        return ["bash", str(self.script), str(self.bundle), ".01", *options]

    def test_running_script_survives_source_edit_and_keeps_selected_menu(self):
        self.env["SMOKE_TEST_PAUSE"] = "1"
        with subprocess.Popen(self.command("--case", "one/lua", "--case", "menu"),
                              env=self.env, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, text=True) as process:
            try:
                deadline = time.monotonic() + 5
                while not self.ready.exists() and process.poll() is None and time.monotonic() < deadline:
                    time.sleep(.01)
                self.assertTrue(self.ready.exists(), "smoke job did not reach its first case")
                text = self.script.read_text()
                self.script.write_text(text.replace("#!/usr/bin/env bash\n",
                    "#!/usr/bin/env bash\n" + "# edited while the case was running\n" * 31, 1))
            finally:
                self.resume.touch()
            out, err = process.communicate(timeout=10)
        self.assertEqual(process.returncode, 0, out + err)
        self.assertIn("one/lua", out)
        self.assertIn("WasmMenu", out)
        self.assertNotIn("one/wasm", out)
        self.assertEqual(len(self.calls.read_text().splitlines()), 2)

    def test_default_runs_every_entry_and_menu(self):
        result = subprocess.run(self.command(), env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("All 2 game entries and the menu", result.stdout)
        self.assertEqual(len(self.calls.read_text().splitlines()), 3)

    def test_unknown_case_cannot_pass_without_running_checks(self):
        result = subprocess.run(self.command("--case", "missing/wasm"),
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("Unknown smoke case", result.stderr)
        self.assertFalse(self.calls.exists())

MOCK_GH = r'''#!/usr/bin/env python3
import hashlib, json, os, pathlib, sys
a = sys.argv[1:]
directory = pathlib.Path(os.environ['MOCK_STATE'])
statefile = directory / 'github.json'
s = json.loads(statefile.read_text()) if statefile.exists() else None
if a[:2] == ['repo', 'view']:
    print('gajop/springcabal-dev')
elif a[0] == 'api' and '/git/ref/' in a[1]:
    print('tag\t' + 'a' * 40)
elif a[0] == 'api' and '/git/tags/' in a[1]:
    print('commit\t' + 'b' * 40)
elif a[:2] == ['release', 'view'] and 'gajop/spring-rust' in a:
    print('recoil_2026.10.21_amd64-linux.7z\nrecoil_2026.10.21_amd64-windows.7z')
elif a[:2] == ['release', 'list']:
    if s: print(str(s['draft']).lower())
elif a[0] == 'api':
    print(json.dumps({'assets': s['assets']}))
elif a[:2] == ['release', 'view']:
    print('https://api.github.com/repos/gajop/springcabal-dev/releases/1')
else:
    with (directory / 'mutations').open('a') as log:
        log.write(json.dumps(a) + '\n')
    if a[:2] == ['release', 'create']:
        s = {'draft': True, 'prerelease': '--prerelease=true' in a, 'assets': []}
    elif a[:2] == ['release', 'upload']:
        s['assets'] = [{'name': pathlib.Path(p).name,
                        'digest': 'sha256:' + hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()}
                       for p in a[2:] if pathlib.Path(p).is_file()]
        if os.environ.get('MOCK_BAD_DIGEST'): s['assets'][0]['digest'] = 'sha256:bad'
    elif a[:2] == ['release', 'edit']:
        if '--draft=false' in a: s['draft'] = False
        if '--prerelease=true' in a: s['prerelease'] = True
        if '--prerelease=false' in a: s['prerelease'] = False
    else:
        sys.exit(f'Unexpected gh call: {a}')
    statefile.write_text(json.dumps(s))
'''

MOCK_PACKAGE = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
assert sys.argv[1:] == ['--engine-tag', '2026.10.21', '--version', '1.2.3', '--platform', 'all', '--build']
root = pathlib.Path(__file__).resolve().parent.parent
out = root / 'release/out'
(out / 'content-1.2.3').mkdir(parents=True, exist_ok=True)
(out / 'content-1.2.3/BUILDINFO.txt').write_text('fixture build\n')
for name in ['SpringCabal-1.2.3-linux.tar.gz', 'SpringCabal-1.2.3-windows.zip']:
    (out / name).write_bytes(b'fixture binary archive')
if os.environ.get('MOCK_CHANGE_SOURCE'):
    (root / 'tracked.txt').write_text('changed during build')
'''


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="springcabal-release-test-")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base / "workspace with spaces"
        self.root.mkdir()
        (self.root / "release").mkdir()
        for name in ("release.sh", "source-snapshot.py"):
            shutil.copy2(SCRIPTS / name, self.root / "release" / name)
        package = self.root / "release/package.sh"
        package.write_text(MOCK_PACKAGE)
        package.chmod(0o755)
        (self.root / ".gitignore").write_text("spring-linux/\nspringcabal-rs/\nrelease/out/\n__pycache__/\n")
        (self.root / "content.tsv").write_text(
            "game\tTest-wasm.sdd\tgit-source\tmain\tyes\n"
            "game\tTest.sdd\tgit-source\tmain\tyes\n"
            "map\tTest-map.sdd\tgit-source\tmain\tyes\n"
            "game\tSupport.sdd\tlocal\t-\tyes\n"
            "map\tDownload.sd7\tdownload\t-\tyes\n"
            "game\tUnshipped.sdd\tlocal\t-\tno\n")
        for name in ("springcabal-rs", "spring-linux/games/Test-wasm.sdd",
                     "spring-linux/games/Test.sdd", "spring-linux/maps/Test-map.sdd"):
            repo = self.root / name
            repo.mkdir(parents=True)
            (repo / "tracked.txt").write_text(name)
            self.init_repo(repo)
        support = self.root / "spring-linux/games/Support.sdd"
        support.mkdir()
        (support / "local.txt").write_text("local content")
        (support / "cache.cwasm").write_text("ignored cache")
        (self.root / "spring-linux/maps/Download.sd7").write_text("downloaded map")
        (self.root / "tracked.txt").write_text("framework")
        self.init_repo(self.root)
        self.remote = self.base / "remote.git"
        self.run_command("git", "init", "--bare", "-q", str(self.remote))
        self.run_command("git", "remote", "add", "origin", str(self.remote))
        self.state = self.base / "state"
        self.state.mkdir()
        binary = self.base / "bin"
        binary.mkdir()
        (binary / "gh").write_text(MOCK_GH)
        (binary / "gh").chmod(0o755)
        self.env = {**os.environ, "PATH": str(binary) + os.pathsep + os.environ["PATH"],
                    "MOCK_STATE": str(self.state)}
        self.notes = self.base / "notes.md"
        self.notes.write_text("Player-visible changes and launch instructions.\n")

    def run_command(self, *args, cwd=None, check=True):
        return subprocess.run(args, cwd=cwd or self.root, check=check,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    def init_repo(self, repo):
        for args in (("init", "-q", "-b", "main"), ("config", "user.name", "Release test"),
                     ("config", "user.email", "test@example.invalid"),
                     ("add", "."), ("commit", "-qm", "fixture")):
            self.run_command("git", *args, cwd=repo)

    def release(self, action, *args, success=True, **env):
        result = subprocess.run([str(self.root / "release/release.sh"), action, VERSION, *args],
                                cwd=self.root, env={**self.env, **env}, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def prepare(self, **kwargs):
        return self.release("prepare", "--engine-tag", "2026.10.21", **kwargs)

    def publish(self, *args, **kwargs):
        return self.release("publish", "--notes", str(self.notes), *args, **kwargs)

    def test_source_snapshot_and_checksums(self):
        self.prepare()
        out = self.root / "release/out"
        self.run_command("sha256sum", "-c", "SHA256SUMS-1.2.3.txt", cwd=out)
        with tarfile.open(out / "SpringCabal-1.2.3-source.tar.gz") as archive:
            names = archive.getnames()
            prefix = "SpringCabal-1.2.3-source/"
            for name in ("tracked.txt", "springcabal-rs/tracked.txt",
                         "spring-linux/games/Test-wasm.sdd/tracked.txt",
                         "spring-linux/games/Test.sdd/tracked.txt",
                         "spring-linux/maps/Test-map.sdd/tracked.txt",
                         "spring-linux/games/Support.sdd/local.txt", "spring-linux/maps/Download.sd7"):
                self.assertIn(prefix + name, names)
            self.assertFalse(any(".git/" in n or n.endswith(".cwasm") for n in names))
            instructions = archive.extractfile(prefix + "BUILDING-RELEASE.txt").read().decode()
            self.assertIn("just setup-dev-engine ../spring-bar", instructions)
        self.assertFalse((self.state / "mutations").exists())

    def test_dirty_game_refused(self):
        (self.root / "spring-linux/games/Test.sdd/untracked.txt").write_text("dirty")
        self.prepare(success=False)

    def test_sources_changing_during_build_refused(self):
        self.prepare(success=False, MOCK_CHANGE_SOURCE="1")
        self.assertFalse((self.root / "release/out/SOURCES-1.2.3.json").exists())

    def test_dry_run_does_not_tag_or_push(self):
        self.prepare()
        self.publish("--dry-run")
        self.assertEqual(self.run_command("git", "tag").stdout, "")
        self.assertEqual(self.run_command("git", "--git-dir", str(self.remote), "show-ref", check=False).stdout, "")
        self.assertFalse((self.state / "mutations").exists())

    def test_changed_local_content_refused(self):
        self.prepare()
        (self.root / "spring-linux/games/Support.sdd/local.txt").write_text("different")
        self.publish("--dry-run", success=False)

    def test_changed_archive_refused(self):
        self.prepare()
        (self.root / "release/out/SpringCabal-1.2.3-linux.tar.gz").write_text("corrupt")
        self.publish(success=False)
        self.assertFalse((self.state / "mutations").exists())

    def test_publish_draft_resume_and_public_refusal(self):
        self.prepare()
        self.publish("--draft")
        self.assertTrue(json.loads((self.state / "github.json").read_text())["draft"])
        refs = self.run_command("git", "--git-dir", str(self.remote), "show-ref").stdout
        self.assertIn("refs/heads/main", refs)
        self.assertIn("refs/tags/v1.2.3", refs)
        self.publish()
        self.assertFalse(json.loads((self.state / "github.json").read_text())["draft"])
        self.publish(success=False)

    def test_github_digest_failure_leaves_draft(self):
        self.prepare()
        self.publish(success=False, MOCK_BAD_DIGEST="1")
        self.assertTrue(json.loads((self.state / "github.json").read_text())["draft"])

    def test_prerelease_preserves_latest_stable(self):
        self.prepare()
        self.publish("--prerelease")
        state = json.loads((self.state / "github.json").read_text())
        self.assertFalse(state["draft"])
        self.assertTrue(state["prerelease"])
        mutations = [json.loads(line) for line in (self.state / "mutations").read_text().splitlines()]
        self.assertIn("--latest=false", mutations[-1])
        self.assertNotIn("--latest", mutations[-1])

    def test_prerelease_draft_resume(self):
        self.prepare()
        self.publish("--prerelease", "--draft")
        state = json.loads((self.state / "github.json").read_text())
        self.assertTrue(state["draft"])
        self.assertTrue(state["prerelease"])
        self.publish("--prerelease")
        state = json.loads((self.state / "github.json").read_text())
        self.assertFalse(state["draft"])
        self.assertTrue(state["prerelease"])

    def test_remote_tag_at_another_commit_refused(self):
        self.run_command("git", "tag", "v1.2.3")
        self.run_command("git", "push", "origin", "refs/tags/v1.2.3")
        self.run_command("git", "tag", "-d", "v1.2.3")
        self.run_command("git", "commit", "--allow-empty", "-qm", "later framework commit")
        self.prepare()
        self.publish("--dry-run", success=False)
        self.assertFalse((self.state / "mutations").exists())

    def test_relative_notes_from_another_directory(self):
        self.prepare()
        result = subprocess.run([str(self.root / "release/release.sh"), "publish", VERSION,
                                 "--notes", "notes.md", "--dry-run"], cwd=self.base,
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_submodule_sources_are_archived(self):
        library = self.base / "library"
        library.mkdir()
        (library / "library.txt").write_text("pinned library source")
        self.init_repo(library)
        game = self.root / "spring-linux/games/Test.sdd"
        self.run_command("git", "-c", "protocol.file.allow=always", "submodule", "add",
                         str(library), "libs/library", cwd=game)
        self.run_command("git", "commit", "-qam", "pin library", cwd=game)
        self.prepare()
        with tarfile.open(self.root / "release/out/SpringCabal-1.2.3-source.tar.gz") as archive:
            self.assertIn("SpringCabal-1.2.3-source/spring-linux/games/Test.sdd/libs/library/library.txt",
                          archive.getnames())
        record = json.loads((self.root / "release/out/SOURCES-1.2.3.json").read_text())
        self.assertTrue(any(item['path'].endswith('libs/library') for item in record['sources']))
        (game / "libs/library/library.txt").write_text("dirty library")
        self.prepare(success=False)


if __name__ == "__main__":
    unittest.main()
