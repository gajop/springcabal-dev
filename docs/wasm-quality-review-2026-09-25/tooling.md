# Review 3: tooling (verification harness, justfile, scripts, release, launch, docs, hygiene)

Paths are relative to `springcabal-games/` (HEAD `ad94ced`).

## Grade: B− (harness C+ → B, repo hygiene C → C+)

Round 3 fixed nearly every harness finding from round 2:
- counting reads one log;
- `verify` takes its own lock;
- every suite checks the exit status;
- provenance and renderer records are real;
- the gallery shows UI effects;
- the `justfile` and `.gitignore` bugs are gone.

What's left is a set of checks that quietly do nothing:
- the speed overrides never apply;
- `vf_write_settings` is never read;
- a renderer mismatch skips every pixel check and still passes;
- several runtime-failure patterns can't match the engine's trap message.

The docs have also drifted again since rounds 5–6. Hygiene is unchanged in size:
`verification/out/` holds 15 GB in 609 directories.

## Round-2 findings, status now

| Round-2 finding | Status |
|---|---|
| `last.combined.txt` doubles every count | **Fixed** (`vf_count_log`, `lib/common.sh:483-489`). |
| Hunted `waves >= 2` passed with one wave | **Changed.** The check was removed in `72c786e` in favour of the new integration suite. `hunted.sh:57,61` now only prints the wave count. BASELINE.md still says "the suite requires at least 2" (see T7). |
| No lock inside `verify`; stale lock reason | **Fixed** (`verify:94-119`, BASELINE.md:107-111). |
| Only Hunted checks the exit status; visual suites accept a timeout | **Partly.** Every suite checks the status now. Visual scenarios still end by the timeout (`vf_require_exit_or_timeout`), although `vf_quit_when` works in visual runs too. That costs 60–75 s each and turns a hang into a pass as long as the markers and shots are there. |
| Area17 headless had no panic/trap forbid | **Fixed** (`area17.sh:343`). Other suites have gaps, see T4. |
| Traps misbehave on Ctrl+C | **Fixed** (`vf_cleanup_on_exit`). |
| `run-wasm.sh`'s `exec` skipped the EXIT trap; dead relaunch | **Fixed** (`689ab15`). |
| `area17 static` built inside the checkout | **Fixed** (`area17.sh:302-319`, equal-length cache path). |
| Flove visual skipped `vf_graphics` and all checks | **Fixed**, and it renders with soft particles again (`c95d3eb`). |
| Provenance wrong for untracked folders and the engine version | **Fixed** (`vf_source_line`, `vf_engine_version`, `vf_crates_line`). |
| Goldens don't check the renderer | **Fixed**, but a mismatch now skips silently: T3. |
| Gallery: UI stripped, camera from the def radius, MyCube CEG crash | **Fixed** (gallery mode, model-bounds framing, `SKIP … has no ceg items`). |
| `justfile:115` backtick deleted the config | **Fixed** (the recipes call `setup.sh`). |
| Unanchored `springsettings.cfg` ignore | **Fixed** (`.gitignore:7`). |
| ~21 GB clutter | **Open.** `verification/out` 15 G (609 dirs, ~560 of them ad-hoc: `area17-abduction-wasm-debug{,2..6}`, `compare-lua-*`…), `wasm-backups` 5.7 G, `verification/cache` 2.0 G, `wasm-test` 752 M, `wasm-test-screens` 544 M, `area17-test` 306 M, root `mycube-*.cwasm`/`partsneeded-*.cwasm`, `*-work/`. `just clean-verification-out` exists but has never been run, and it leaves `cache/` alone. |
| Stale docs | **Partly.** The ones named then are fixed; new drift is listed in T7. |

## New findings (most severe first)

### T1. Every speed override in the harness is a no-op (bug)
- **What's wrong.** `vf_start_file` (`lib/common.sh:197-198`) rewrites speeds with case-sensitive
  seds: `s/minspeed=[^;]+;/…/` and `s/maxspeed=…/`. Every `launch/games/*/*.txt` spells them
  `MinSpeed=0.1;` and `MaxSpeed=20;`, so nothing is replaced.
- **Evidence.** The latest Flove visual run was asked for `10.0 30.0` (`flove.sh:72`), but its
  staged start script (`verification/out/flove-visual/run/start.txt`) still says `MaxSpeed=20;`
  and `MinSpeed=0.1;`.
- **Callers affected:**
  - `area17.sh:327` (`100.0 100.0`);
  - `flove.sh:43` (headless 100), `:72` (visual 10–30), `:124,158,195` (outline, wisps and
    original at 1.0);
  - `probes/flove-ceg.sh:12`, `probes/flove-spire.sh:20` (1 1).
- **Consequence.** Headless suites are capped at 20× instead of 100×, so they are slower and closer
  to their timeouts. The real-time runs meant to be pinned at 1× (outline, wisps, original) are not
  pinned. The gallery works only because it uses `vf_start_set` (case-insensitive, `gallery.sh:134`).
- **Fix:** implement the speed arguments with `vf_start_set MinSpeed/MaxSpeed`, and drop the seds.

### T2. `vf_write_settings` writes a file the engine never reads (dead check)
- **What's wrong.** Every run passes `--config $VF_CONFIG_FILE`, and with a config source the
  engine uses only that file. `ConfigHandler::Instantiate`
  (`spring-bar/rts/System/Config/ConfigHandler.cpp:420-424`) skips `GetDefaultLocations`, so the
  write dir's `springsettings.cfg` is never read. The logs confirm it: the only line is
  "Using writeable configuration source: …/spring.conf".
- **Consequence.** These settings are silently ignored:
  - Gravitas e2e's `UseFontConfigLib = 0` (`gravitas.sh:53-55`);
  - Gravitas shots' window size, borderless, position, `GroundDetail`, `MaxMapDetail` and
    `LODScale` (`gravitas.sh:135-146`).

  Some of those happen to match `launch/springsettings.cfg`; the rest don't apply.
- **Fix:** delete `vf_write_settings` (`lib/common.sh:119-121`, and the helper list in
  `verification/README.md:377`). Use `vf_config_set` after `vf_config` for anything that must
  differ.

### T3. A renderer change turns every pixel check into a silent pass (test proves less than it claims)
- **What's wrong.**
  - `vf_golden` prints `SKIP … recorded on another renderer` and returns 0
    (`lib/common.sh:726-729`).
  - `gravitas_hud_and_fire` returns 0 on a mismatch (`gravitas.sh:173`).
  - The gallery likewise "skips pixel comparisons".
  - `vf_goldens_done` then passes.
- **Consequence.** A Mesa or LLVM update changes the renderer record. Even an Ubuntu package bump
  does, because the record includes the package revision: `hunted/goldens/renderer.txt` has
  `llvmpipe (LLVM 20.1.2, 256 bits)` and `Mesa 25.2.8-0ubuntu0.24.04.2`. After that, all seven scenario suites (and the GPU galleries after a driver
  update) compare nothing. `verify visual` still prints `all 9 runs passed`, and the only trace is a
  WARNING inside each suite's output.
- **Fix:**
  - Count the skips.
  - Fail unless `VF_ALLOW_RENDERER_MISMATCH=1`, or give a distinct exit status that `run_all`
    reports as "skipped".

### T4. The runtime-failure checks differ per suite, and some can't match (silent failures)
- **What the engine logs.** A Rust panic in a guest ends as a wasm trap, which the engine logs as
  `core Wasm export trapped: …` (`spring-bar/rts/WasmInterface/core/host/WasmCoreHost.cpp:1184`),
  plus `guest panic: …` from the SDK hook.
- **The gaps:**
  - `hunted.sh:54`: `'…|Wasm trap|…'` is a literal that never matches `Wasm export trapped`, and
    there is no `panic`. A UI-module trap in the Hunted headless run goes unnoticed. (The rules
    trapping would also stop the marker.)
  - `ttld.sh:466-499` (`ttld visual`) forbids nothing but a GLSL validate line: no trap, panic or
    `ASSERTION FAILED` check.
  - `gravitas.sh:128-168` (`gravitas shots`) forbids nothing.
  - `release/smoke-test.sh:40,60` forbids `wasm trap`, which is lowercase and literal, so it never
    matches either. A bundle whose modules trap on load passes the smoke test.
  - `ttld.sh:406` `vf_forbid 'world state re-entered'` can't fire: nothing emits that string any
    more. It is the same dead check round 2 found in Gravitas.
- **Fix:**
  - Add one `vf_forbid_runtime_failures` helper in `lib/common.sh`, with
    `Wasm.*trap|guest panic|panicked at|CallIn.*(error|Error)|already borrowed|ASSERTION FAILED`.
  - Call it from every suite, and reuse the pattern in `smoke-test.sh`.
  - Delete the TTLD `world state` line.

### T5. MyCube and Parts Needed never test the shipped start script (launch/ rule broken)
- **What's wrong.** `mycube.sh:233-247` and `partsneeded.sh:138-156` write inline start scripts:
  one team, no NullAI team, `startpostype=0`, custom start positions. `launch/games/{mycube,
  partsneeded}/wasm.txt` have two teams, an AI team and `StartposType=3`.
- **Why that breaks a rule.** CLAUDE.md and README.md ("verification … read from it") say suites
  read `launch/`. `verification/README.md:334` allows inline scripts only where "the scenario needs
  a special team layout". TTLD's three-team inline script (`ttld.sh:244-262`) is such a case. These
  two aren't.
- **Consequence.** The layout players get (team 1 as a NullAI enemy, engine start positions) is
  exercised only by the gallery and the smoke test. So game-end or team logic that depends on it has
  no assertion suite.
- **Fix:** `vf_start_file "$(vf_launch_script mycube)"` plus `vf_start_set`/`vf_modoption` for
  what the scenario really needs.

### T6. Checks exist but aren't run (gaps)
- **Host unit tests.** No recipe or suite runs them:
  - `springcabal-rs` (~23 tests);
  - Flove `rules-synced/src/command_policy.rs`;
  - Parts Needed `shared/src/lib.rs` and `ui/.../trail.rs`;
  - TTLD `ui/src/minimap.rs`.

  Only Hunted has a `test` recipe (`Hunted-wasm.sdd/wasm-src/justfile:17`), and that isn't in
  `verify all` either.
- **Installed module = source.** Only Area 17 checks this (`area17_static`). For the other six,
  `release/package.sh:107-112` only warns when a `.rs` mtime is newer than a module. It ignores
  `Cargo.lock`, `springcabal-rs` and the `spring` crates, so a module built against an older crate
  ships without a word. Generalise `area17_static` to every game, and run it in `verify all` and in
  `package.sh`.
- **Lua/Rust pose parity.** `ttld pose-parity` is a pass/fail comparison (`compare.py --tolerance
  1e-4`), but it is in neither `ALL_RUNS` nor `VISUAL_RUNS` (`verify:22-32`), so it never runs.
- **Unbuilt feature.** Flove's `animation-trace` feature (15 `cfg` sites) is built only by
  `Flove-wasm.sdd/verification/animation_trace.sh`. That script lives inside the game repo, sources
  this repo's `lib/common.sh`, and isn't listed by `verify list`. The feature can rot unseen.
- **Source comparison.** `unit-scripts/compare_source.py:162-187` reads `float_arms.rs` but compares
  only walk legs and walk arms. Hover arms and idle are never compared.

### T7. Docs out of date after rounds 5–6
- **verification/README.md.**
  - `:59-62` still says Flove's visual suite "turns soft particles off". That was removed in
    `c95d3eb`.
  - `:377` lists the dead `vf_write_settings`.
- **BASELINE.md.**
  - `:173` and `:257` repeat the SoftParticles deviation.
  - `:241` says Hunted "requires at least 2" waves.
  - The "Current state" table (`:113-147`) predates round 6: every game HEAD differs, and the
    engine version is `…279-g765edd6`.
- **CLAUDE.md.** It says "each game keeps a small deferred list for that case only". Since round 5
  every game uses the SDK's `with_cus_module_or_defer` (`spring/src/cus/core_module.rs:231`) and
  keeps no list.
- **RELEASING.md.** Its smoke-test section says each entry "must load and simulate at least 150
  frames". `smoke-test.sh:4-5,39` treats frames as informational and requires only loading plus
  still running at the timeout. It also says the test "starts every menu entry", but
  `smoke-test.sh:18` globs `{wasm,lua}.txt` and skips `gravitas/editor.txt`, which the menu has
  (`wasm-menu/wasm-src/menu/src/lib.rs:28`).
- **`Area17-wasm.sdd/wasm-src/justfile:16-20`** still wraps `verify` in `flock`. It is harmless, but
  it is the pattern the docs call obsolete.

### T8. Release provenance and the test-build guard are incomplete
- **Provenance.** `BUILDINFO.txt` (`package.sh:163-184`) records every content checkout, but not the
  `springcabal-rs` commit or the `spring`/`spring-addons` revision the modules were built with.
  Together with the unpinned deps (crate.md), a bundle's modules can't be traced to their crate
  sources. Reuse `vf_crates_line`.
- **Test-build guard.** `test_markers` (`package.sh:94`) doesn't catch Flove's `test-commands` build
  (the one the Flove visual suite uses) or its `animation-trace` build. Add a marker string that each
  of those features compiles in.
- **The shipped profile is never started.** The smoke test passes `--config $run/spring.conf`
  (`smoke-test.sh:28-32,53-57`), which replaces the bundle's `springsettings.cfg`. The menu-boot
  check therefore never starts the profile players get (deferred rendering and the rest).
- **Menu staleness check.** Both `run-wasm.sh:62` and `package.sh:224` compare the menu module
  against `launch/games/` only. The menu also `include_str!`s `game-info/*/README.md`
  (`menu/src/entry.rs:6-12`), so edited descriptions can ship stale.

### T9. Smaller harness issues
- **Visual runs end by the timeout.** Area17, Hunted, MyCube, Parts Needed and TTLD visual runs
  always end by the timeout. Screenshots already log a done marker, so `vf_quit_when <marker>` would
  cut about 5 minutes from `verify visual` and make a hang fail rather than pass.
- **`gravitas headless` asserts nothing.** It checks only a clean exit (`gravitas.sh:31-45`). It
  sits in the mode table as if it were a suite; drop it or give it checks.
- **`vf_config_set` builds a sed regex from an unescaped key** (`lib/common.sh:379`). That is fine
  for today's keys, and fragile.

## Strengths

- `lib/common.sh` is a real library now:
  - suites describe only their game;
  - isolation is enforced (`vf_install_modules` refuses paths outside the isolation view);
  - one log is used for counting, with the reason documented.
- The lock handles nesting correctly: it inherits an ancestor's descriptor, and `/proc/locks` is
  checked so an ancestor's lock doesn't deadlock the run.
- `area17_static` compares code sections byte for byte, from a target directory of equal path length.
  That is clever and well explained, and should be the model for the other games (T6).
- Provenance and renderer records are thorough. The gallery (fixed-schedule poses at 0.01 elmo, CEG
  noise measured per capture) is the strongest check in the repo.
- `launch/` really is compiled into the menu. `run-wasm.sh` and `package.sh` guard against a stale
  menu, and `run-wasm.sh` regenerates its config each launch, so games can't persist settings.
