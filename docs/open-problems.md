# Open problems in the WASM ports

What's still wrong in the seven ports, the shared crate and the harness. Nothing fixed is listed;
git history has the reviews and fixes. Delete an entry when it's fixed.

Paths are relative to `spring-linux/games/<Game>-wasm.sdd/wasm-src/` unless stated otherwise.

## 1. Games

- **Gravitas: the arena golden can't see robots in the wrong place.** Runs of the same build differ
  by 1.0–2.5%, which is about what a misplaced robot costs. Assert unit positions at the shot frame
  instead.
- **Gravitas: all e2e cases share one arena on a hard-coded frame schedule.** Some cases depend on
  earlier ones finishing first. Fixing this needs a runner rewrite.
- **TTLD: Adrenaline, Heartburn and Poultice are cast directly in the headless suite,** not through
  the input message. Migraine and Transfusion already go through it.
- **Parts Needed: no check covers a lever and the kill plate opening the same cage in one pass.**
  The port handles it; a check would need both scenarios reworked.
- **Hunted: the pellet count and spray are hard-coded,** because the SDK's `WeaponDefInfo` has no
  `projectiles` or `sprayAngle` (engine).
- **Flove: the poison mushroom's poses differ from the Lua original's by 3.2 elmos** (unchanged since
  before round 7).
- **Area17: a human re-lifted by the beam floats again;** Lua only floats on the first lift. This is
  deliberate and in the README.

## 2. Flaky or non-deterministic checks

- **Hunted's anim gallery isn't reproducible.** The same code passed in round 6 and fails now on the
  same engine: the lighthouse `LightPitch` pose and the rabbit images. Their start angles come from
  the synced RNG, which apparently isn't seeded the same way each run.
- **Area17's visual `frame_080` is flaky under load (8.3–12.7% against 8%).** The scenario runs in
  real time, so the shot catches the God Gun's first impact at a varying moment. Frame-lock it, as
  TTLD does with `pauseatframe`.
- **The anim galleries run the full rules module,** so a change to one unit's logic (Area17's
  civilians) shifts the RNG and moves unrelated units' poses.
- **Area17's anim gallery:** the drone flies out of frame in every drone shot.

## 3. Harness and tooling

- **Speed overrides are ignored.** `vf_start_file` looks for lowercase `maxspeed=`; `launch/` says
  `MaxSpeed=`. Headless suites run at 20× (Parts Needed's at 1×) instead of 100×, and the runs meant
  to be pinned at 1× aren't. Fixing it changes test timing, so goldens will need re-recording.
- **A renderer change skips every pixel check and still passes** (`lib/common.sh`, `vf_golden`).
  Even a Mesa package bump does it. Fail unless `VF_ALLOW_RENDERER_MISMATCH=1`.
- **Runtime-failure checks miss real failures.**
  - The smoke test greps for "wasm trap"; the engine logs "core Wasm export trapped".
  - `ttld visual` and `gravitas shots` forbid nothing.
  - TTLD's `world state re-entered` check can never fire.
  - Fix: one `vf_forbid_runtime_failures` helper for every suite.
- **`vf_write_settings` writes a file the engine never reads** (`--config` replaces it).
- **MyCube and Parts Needed use inline start scripts** instead of `launch/`, so the layout players
  get has no assertion suite.
- **Checks that exist but aren't run:**
  - host tests: the crate, and each game's `shared`/`ai` crate;
  - `ttld pose-parity`;
  - "installed module = source", which runs only for Area17;
  - Flove's `animation-trace` build;
  - hover arms and idle in the unit-script comparison.
- **TTLD's UI crate can't build for the host,** so its `minimap.rs` tests never run.
- **Visual runs end on their timeout** in Area17, Hunted, MyCube and Parts Needed, instead of a
  marker. That's slower, and a hang passes.
- **Release:**
  - `BUILDINFO.txt` doesn't record the crate or engine-crate revisions;
  - the test-build guard misses Flove's `test-commands`;
  - the smoke test never starts the shipped graphics profile;
  - the menu's staleness check ignores `game-info/*/README.md`.
- **Stray tracked files:** `port-reference/` in Area17 and MyCube, and Flove's
  `verification/animation_trace.sh`.

## 4. Shared crate (`springcabal-rs`)

- **Unpinned git dependency.** A fresh clone without the local `[patch]` builds whatever HEAD is at
  the time. Pin a rev or tag.
- **`Encoder`** doesn't escape `|` or `=`, and writes `NaN`, which the parser drops.
- **`flag("false")` reads as true.**
- **`check::Suite` passes with 0 checks** unless a minimum is set. Make the minimum a constructor
  argument.
- **Untested modules:** `check`, `menu`, `music` and `shots`. `Screenshots` checks the shot order only
  with `debug_assert`.
- **`MusicLoop` logs a failure once per call site,** so a second track's failure is never logged.
- **Camera:**
  - `CameraFollow` holds its borrow across `set_camera_state`;
  - `arm_tracker` never retries after a failure;
  - `goal::map_rect` hard-codes the square size.
- **Dead API:** `KeyMoveWidget`, `VelocityDrive`, `ground_under_mouse`.
- **Stale doc:** `message.rs:3` names `send_lua_ui_msg`.

## 5. Duplication and conventions across games

- **Copied between games; should move to the crate or the SDK:**
  - `send_to_rules` (6×);
  - `gallery::active()` (7×);
  - per-game warning/`warning_once` helpers (use `log_err`/`log_once!`);
  - `thread_local!` def caches (12×);
  - the unit-script attach gadget (5×), which belongs in `spring-addons`;
  - two ports each of map-edge and fire.
- **Conventions differ:**
  - addon names are snake_case in Area17 and PascalCase elsewhere;
  - file prefixes differ;
  - `e2e` means different things in different games;
  - `attach_existing()` is called in `init` by 5 games. No game has units at the rules' `init` on a
    normal start, except Parts Needed (278, including map gates).

## 6. Decisions for the user

- **Hunted doesn't wake its unit scripts on Lua's schedule** (`CusHost::game_frame`). The other six
  do. In Hunted it moved rabbit poses further from the Lua gallery (2 → 4 differing shots, the hop
  included), so its agent reverted it. Keep Hunted as the exception, or investigate why?
