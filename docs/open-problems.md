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
  the synced RNG, which apparently isn't seeded the same way each run. On 2026-09-25 three runs
  (two after phase B1, one at the HEADs before it) failed with identical numbers: today the runs
  agree with each other and the goldens are the odd ones out.
- **Area17's visual `frame_080` is flaky (8.3–12.7% against 8%; three runs on an idle machine on
  2026-09-25 all failed, 9.8–11.2%).** The scenario runs in
  real time, so the shot catches the God Gun's first impact at a varying moment. Frame-lock it, as
  TTLD does with `pauseatframe`.
- **The anim galleries run the full rules module,** so a change to one unit's logic (Area17's
  civilians) shifts the RNG and moves unrelated units' poses.
- **Area17's anim gallery:** the drone flies out of frame in every drone shot.
- **`unit-scripts partsneeded` can time out:** its Lua run hit the timeout (status 124) once in
  a `verify all` on 2026-09-25 and passed on the rerun.

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
  - the test-build guard misses Flove's `e2e` build (its test commands);
  - the smoke test never starts the shipped graphics profile;
  - the menu's staleness check ignores `game-info/*/README.md`.
- **Stray tracked files:** `port-reference/` in Area17 and MyCube, and Flove's
  `verification/animation_trace.sh`.

## 4. Duplication and conventions across games

- **Copied between games:**
  - the unit-script attach gadget (5×): it belongs in `spring-addons`, filed as
    §5 of `spring-bar/WASM_GAME_API_TODO_2026-09-25.md`;
  - two ports each of map-edge and fire.
- **File prefixes differ** between games (left alone on purpose).
- **`attach_existing()` is called in `init` by 5 games.** No game has units at the
  rules' `init` on a normal start, except Parts Needed (278, including map gates).

## 5. Decisions for the user

- **Hunted doesn't wake its unit scripts on Lua's schedule** (`CusHost::game_frame`). The other six
  do. In Hunted it moved rabbit poses further from the Lua gallery (2 → 4 differing shots, the hop
  included), so its agent reverted it. Keep Hunted as the exception, or investigate why?
