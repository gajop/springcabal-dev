#!/usr/bin/env python3
"""Archive committed release sources, including the unpublished game repositories."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def git(directory, *args):
    return subprocess.check_output(["git", "-C", str(directory), *args], text=True).strip()


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def ignored(name):
    return name in {".git", "target", "__pycache__"} or name.endswith((".cwasm", ".log", ".pyc"))


def inventory(args):
    repos = [ROOT, ROOT / "springcabal-rs"]
    local = []
    for line in (ROOT / "content.tsv").read_text().splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        kind, name, source, _branch, ship = line.split("\t")
        if ship != "yes":
            continue
        relative = Path("spring-linux") / (kind + "s") / name
        if kind not in {"game", "map", "project"} or relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"invalid content path: {relative}")
        path = ROOT / relative
        if not path.exists():
            raise ValueError(f"missing content: {relative}")
        if (path / ".git").exists():
            repos.append(path)
        elif source in {"local", "download"}:
            local.append(path)
        else:
            raise ValueError(f"missing Git checkout: {relative}")

    sources = []
    for repo in repos:
        if Path(git(repo, "rev-parse", "--show-toplevel")).resolve() != repo.resolve():
            raise ValueError(f"not a separate Git checkout: {repo}")
        if git(repo, "status", "--porcelain", "--ignore-submodules=none"):
            raise ValueError(f"commit all changes before preparing a release: {repo}")
        sources.append({"path": str(repo.relative_to(ROOT)), "commit": git(repo, "rev-parse", "HEAD"),
                        "branch": git(repo, "branch", "--show-current")})
        # git archive leaves submodule directories empty. Include each pinned
        # checkout separately, including any nested submodules.
        for entry in git(repo, "ls-files", "--stage", "-z").split("\0"):
            if not entry.startswith("160000 "):
                continue
            header, name = entry.split("\t", 1)
            child = repo / name
            expected = header.split()[1]
            if not (child / ".git").exists() or git(child, "rev-parse", "HEAD") != expected:
                raise ValueError(f"initialize the pinned submodule before packaging: {child}")
            repos.append(child)

    # Local/download entries have no commit: record every copied file's hash.
    files = {}
    for path in local:
        for file in sorted(path.rglob("*") if path.is_dir() else [path]):
            if file.is_file() and not any(ignored(part) for part in file.relative_to(path.parent).parts):
                files[str(file.relative_to(ROOT))] = sha256(file)
    return {"version": args.version, "engine_tag": args.engine_tag,
            "engine_repository": "https://github.com/gajop/spring-rust",
            "engine_commit": args.engine_commit, "sources": sources, "local_content": files}, local


def snapshot(args, metadata, local):
    output = ROOT / "release/out" / f"SpringCabal-{args.version}-source.tar.gz"
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".source-", dir=output.parent) as temporary:
        stage = Path(temporary) / f"SpringCabal-{args.version}-source"
        stage.mkdir()
        for item in metadata["sources"]:
            destination = stage / item["path"]
            destination.mkdir(parents=True, exist_ok=True)
            archive = subprocess.Popen(["git", "-C", str(ROOT / item["path"]), "archive",
                                        "--format=tar", item["commit"]], stdout=subprocess.PIPE)
            try:
                subprocess.run(["tar", "-xf", "-", "-C", str(destination)], stdin=archive.stdout, check=True)
            finally:
                archive.stdout.close()
                result = archive.wait()
            if result:
                raise ValueError(f"git archive failed: {item['path']}")
            print(f"Archived {item['path']} at {item['commit'][:12]}", file=sys.stderr)
        for path in local:
            destination = stage / path.relative_to(ROOT)
            destination.parent.mkdir(parents=True, exist_ok=True)
            if path.is_dir():
                shutil.copytree(path, destination, ignore=lambda _dir, names: [n for n in names if ignored(n)])
            else:
                shutil.copy2(path, destination)
        (stage / "SOURCEINFO.json").write_text(json.dumps(metadata, indent=2) + "\n")
        (stage / "BUILDING-RELEASE.txt").write_text(f"""SpringCabal {args.version} source snapshot

SOURCEINFO.json records the committed framework/menu, shared crate, game and
map revisions, plus hashes of local support content. Git history and ignored
build outputs are excluded. The matching engine and SDK sources are public at:
{metadata['engine_repository']}/tree/{args.engine_tag}
Engine commit: {args.engine_commit}

Install the Linux prerequisites listed in README.md, then from this directory:

git clone --recurse-submodules --branch {args.engine_tag} {metadata['engine_repository']}.git ../spring-bar
rustup target add wasm32-unknown-unknown
just setup-dev-engine ../spring-bar
just build-all
./release/package.sh --engine-tag {args.engine_tag} --version {args.version}

Use the low-level package.sh here: release.sh prepare requires Git checkouts.
Keep SOURCEINFO.json and the release's BUILDINFO.txt as the historical record.
Engine build instructions are in the engine repository.
""")
        # Refuse to publish a snapshot if a checkout changed while it was copied.
        if inventory(args)[0] != metadata:
            raise ValueError("release sources changed while creating the snapshot; prepare again")
        archive_path = Path(temporary) / output.name
        with tarfile.open(archive_path, "w:gz") as archive:
            archive.add(stage, arcname=stage.name)
        archive_path.replace(output)
    print(f"Created {output}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--engine-tag", required=True)
    parser.add_argument("--engine-commit", required=True)
    parser.add_argument("--check", action="store_true", help="check clean sources and print their JSON inventory only")
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9][A-Za-z0-9._-]*", args.version):
        parser.error("version must start with a digit and contain only letters, digits, dots, underscores or hyphens")
    if not re.fullmatch(r"[0-9a-f]{40}", args.engine_commit):
        parser.error("engine commit must be a full Git SHA")
    metadata, local = inventory(args)
    if not args.check:
        snapshot(args, metadata, local)
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f"Source snapshot failed: {error}")
