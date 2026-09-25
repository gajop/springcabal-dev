# Verification

Automated checks for every game, driven from the repository root with `just`:

```bash
just verify-list                 # suites, modes, probes
just verify flove                # one suite, default mode
just verify flove visual         # one suite, one mode
just verify-all                  # every assertion suite and static check
just verify-visual               # every screenshot suite against its goldens
just update-goldens [suite]      # re-record goldens after an intended change
just probe gravitas-fire lua     # a debugging probe
```

(`./verification/verify …` takes the same arguments.)

| suite | modes (first = default) |
| --- | --- |
| `area17` | `headless` \| `visual` \| `static` \| `all` |
| `flove` | `headless` \| `visual` \| `animation-trace` \| `outline` \| `wisps [stage]` \| `original` |
| `gravitas` | `e2e` \| `shots` \| `headless` |
| `hunted` | `headless` \| `visual` |
| `mycube` | `headless` \| `visual` \| `lua-headless` |
| `partsneeded` | `headless` \| `visual` |
| `ttld` | `headless` \| `visual` \| `lua-visual` \| `pose-parity` |
| `unit-scripts` | `partsneeded` \| `source` |
| `gallery` | `ceg [game]` \| `anim [game]` \| `parity [game]` (game defaults to `all`) |
| `host` | `tests` |
| `installed` | `all` \| `<game>` |

- `headless` runs the in-game assertions (modules built with the
  `headless-integration` feature) under `spring-headless`.
- `visual` renders under xvfb with software GL, runs the `e2e` feature's
  scripted scenario and compares its screenshots with goldens.
- `static` is build hygiene only (fmt, clippy, installed artifacts match source).
- `lua-*` modes check the original Lua game on this engine.
- `pose-parity`, `animation-trace` and `unit-scripts` compare Lua and Rust
  unit-script animation traces numerically.
- `host tests` runs the host unit tests: `springcabal-rs` and every game's
  `shared` (and Hunted's `ai`) crate.
- `installed` checks that the modules installed in each game folder match a
  fresh build of its `wasm-src/`.
- `flove outline`, `wisps` and `original` render images for manual A/B
  inspection and do not fail on pixels.

`verify all` runs every in-game assertion suite, the Lua/Rust pose
comparisons, the host tests and the static checks (installed modules, Area
17's source checks).  They run headless, at 100x (MyCube's and Gravitas'
e2e at 1x, see their scripts), except the unit-script comparison, which renders the Lua and
WASM games under xvfb.  `verify visual` runs every golden comparison.
Both take their run lists from the tables in `verify`, and that table's first
mode per suite is the only place a default mode is defined.

Only one `verify` runs at a time: it takes a `flock` on
`/tmp/springcabal-verify.lock` (`VF_LOCK_FILE`) and waits for any other run.
Runs share the `out/<suite>/` workspaces, the font and build caches and the
CPU, and the real-time visual scenarios drift under load.  Wrapping `verify`
in `flock` yourself is no longer needed, but still works.

## Renderer and graphics settings

Visual runs render with the graphics settings players get: the release profile
(`launch/springsettings.cfg`, which turns on deferred map and model rendering),
plus the per-game overrides the menu applies (`vf_graphics` reads
`launch/games/<game>/graphics.cfg`: Area 17 gets 200,000 particles, shadows
and water level 4; Hunted gets shadows off).  The
only test-only changes are the window size, a muted mixer, a hidden console and
hidden FPS/speed counters.  The gallery logs the effective settings and GPU at
the start of every run (`[Gallery] graphics ...`).

`VF_RENDERER` picks the backend:

| renderer | what | visible | limits |
| --- | --- | --- | --- |
| `gpu` | the real GPU and driver via SDL's `offscreen` video driver (EGL, no window) | no | window at most 1024x736: SDL's offscreen display is 1024x768 and the engine clamps to it |
| `software` | Xvfb + Mesa llvmpipe | no | not the driver players use |
| `screen` | a normal window on `$DISPLAY` | **yes**, takes over the screen | none |

Galleries default to `gpu` (720x720).  The scenario suites capture at
1280x720, which doesn't fit the offscreen display, so they default to
`software`; run them with `VF_RENDERER=screen` when fidelity matters.  Goldens
store the renderer they were recorded with: the backend, the GL renderer
string (the GPU, or llvmpipe with its LLVM version) and the GL version string
(the driver), in `renderer.txt` next to them (older scenario goldens: the
`renderer`/`gpu`/`gl` lines of their `PROVENANCE.txt`).  A run on a different
renderer still checks poses, markers and presence, but fails: it can't compare
pixels, and a driver or Mesa update would otherwise switch every pixel check
off unnoticed.  `VF_ALLOW_RENDERER_MISMATCH=1` skips the pixel comparisons
instead, with a message.  `lib/common.sh` has the shared helpers: `vf_renderer_info`
writes the record, `vf_renderer_matches DIR` compares a run with it.

## Suites never touch the game checkouts

Everything under `spring-linux/` is what `release/package.sh` ships, so suites
treat it as read-only:

- `vf_build` compiles into `verification/cache/target/<game>/`, never the
  checkout's own `target/` (whose output `just copy` installs).
- `vf_stage_game` copies the game into the run's isolation view, and
  `vf_install_modules` puts the test-feature modules into that copy. Probe
  gadgets, edited manifests and similar changes also go into the copy.

`release/package.sh` rejects any module that contains test markers, in case a
test build ends up in a checkout anyway.

## Goldens

`fixtures/<game>/goldens/<name>.png` holds the reference screenshots.
`vf_golden` compares a capture with its golden by RMSE and writes the capture
and a diff image to `out/<suite>/goldens/`.

Renders are **not** bit-identical between runs, and how much they drift
depends on the game. Each suite sets `GOLDEN_TOLERANCE` to about twice the
run-to-run RMSE measured on 2026-09-23:

| suite | run-to-run drift | limit |
| --- | --- | --- |
| ttld | 0.1% | 1% |
| area17 | up to 5.5% | 8% |
| flove | 2.6% | 5% |
| mycube | 4.2% | 9% |
| hunted | 5.2% | 10% |
| gravitas | 7.9% | 10% (`SHOT_TOLERANCE`) |
| partsneeded | not recorded yet | 8% |

For MyCube and Hunted the drift is as large as the difference between two of
their own shots, because units move differently each run. Their goldens catch
gross breakage (missing terrain, a black screen, a missing HUD) but not subtle
changes. For those, compare within one run (the `area17` crater, the `ttld`
leader render), assert on values the simulation reports, or use a tight
tolerance on a masked crop (the `gravitas` HUD check).

Golden names:

- **flove** names them after its scenario's announcements
  ("Taking screenshot 2 (spire zap in flight)" → `02_spire_zap_in_flight`).
- **area17** names them after the capture frame (`frame_080`).
- **The other suites** use `shot_N`, in capture order.

After an intended visual change, run `just update-goldens <suite>`, look at the
new images, and commit them.

## Galleries: every CEG and every unit animation

The scenario screenshots above depend on the whole game (AI, timing, camera,
UI), so they are noisy.  `gallery` isolates the two things most worth pinning
down.  For each game it runs **one engine process** that works through every
item in turn:

```bash
just verify gallery ceg flove        # every CEG of one game (or `all`)
just verify gallery anim ttld        # every unit type's animations
just verify gallery parity ttld      # WASM vs Lua unit poses (report only)
just verify gallery ceg hunted --only flashnuke,smoke_puff
just update-goldens gallery          # re-record both for every game
```

Timings for a check (GTX 1660 Ti, 2026-09-23):
- Area 17: 11.9 s (CEGs) + 12.9 s (animations)
- Flove: 9.7 + 6.8 s
- every other game: 4–6 s each
- all galleries of all games: 79 s

Recording goldens takes four CEG runs and two animation runs.

What makes it fast:
- **Raw captures.** PNG encoding cost 60–80 ms per capture on the render
  thread.  The gallery now box-filters each capture on the GPU (mipmaps) and
  writes 64x64 and 128x128 raw RGB via `gl.SaveImage(..., "x.raw")` (DevIL's
  raw format).  Hunted's 336 captures went from 29.9 s of engine time to 1.3 s.
  The Python comparison reads those bytes directly.
- **Goldens in one atlas per game.** One PNG holds all tiles, so a check reads
  a single file.  Contact sheets are made only when recording, or for failing
  captures.
- **An extracted copy of the Area 17 map** (`scripts/area17-map.sh --dir`).
  Decompressing the 103 MB solid 7z took about 4 s on every start.

`GALLERY_FULL=1` also keeps a full-size JPEG of every capture for inspection.

`fixtures/gallery/gallery.lua` does the work in-engine.
`Spring.SetVideoCapturingMode(true)` advances exactly one simulation frame per
drawn frame and pins interpolation at 0, so a capture taken at game frame N
shows frame N exactly.  Captures happen in `DrawScreenPost`, after every
client's screen effects (the UI module's bloom, lights and sprites run after
the gallery's own `DrawScreenEffects`), with the interface hidden, no HUD
widgets loaded, the mouse cursor parked in a corner outside the crop, and
global LOS granted (particles outside line of sight are not drawn).
`lib/gallery.py` compares the results.

**One unit at a time (animations).**  The game's rules run as they ship, so
they would spawn their level, waves and respawns, and every one of those
units' logic draws from the synced RNG the unit scripts share: a change to
one unit's logic would move every later unit's random start angles and idles.
So the anim gallery removes every unit but its own each frame, and reseeds the
synced RNG each frame from the unit's name and the frame within its job.  A
unit's captures depend on its own script, the rules' logic for it, and the
rules' global logic (spawn timers) only.  Aircraft are framed on the view ray
through the unit (the spring camera always focuses on the ground).

**UI effects: gallery mode.**  A capture should show what a player sees of a
unit or effect, minus the HUD, and much of that is drawn by the game's WASM UI
module, not the engine.  So the UI module stays loaded, and the `gallery`
modoption (which the gallery always sets) puts it in gallery mode:
`ui/src/widgets/gallery.rs` in each game registers only the widgets that draw
into the world, plus the state they need, and logs `gallery mode: <widgets>`.
No HUD, RmlUi document, input, camera or sound widget runs.  A run whose UI
module loads without logging `gallery mode:` fails, so a new game can't leak its
HUD or camera into the captures; its `setup` needs the same
`if gallery::active() { gallery::setup(handler); return; }` switch.
`GALLERY_UI=0` strips the UI module instead, for A/B comparisons.

| game | kept in gallery mode | shows | left out, and why |
| --- | --- | --- | --- |
| Area 17 | ApiSync, GfxVolumes | the UFO's abduction cone | full view (the gallery grants LOS itself) |
| Flove | GfxGrass, GfxHideTriggers | full grass detail, hidden trigger markers | (the outlines are the rules-unsynced module, kept in both kinds) |
| Gravitas | GameClock, GfxRulesEffects, GfxFire, GfxMapEdge | fire, sparks, arcs and smoke the rules report, heat distortion, map edge | health bars (HUD) |
| Hunted | none | | the flashlight follows the cursor, and rabbit visibility hides every rabbit outside it |
| MyCube | none | | the game draws no world effects; health bars and texts are HUD |
| Parts Needed | ApiSync, GfxBlood, GfxEyesEffect | wisp glow sprites, the player wisp's trail, floor decals, the spirit-form screen pass | the lever highlight follows the cursor |
| TTLD | ApiSync, GfxLighting, GfxFire, GfxMapEdge, GfxHighlight, GalleryPointer | the dark sun, house, staff, projectile and cursor lights, bloom, burning houses, the hover highlight | |

TTLD's cursor light and hover highlight follow the player's pointer, so gallery
mode's `GalleryPointer` stands in for the input widget: a cursor resting on the
middle of the view, where the subject is.  Effects that need the rules module
(Gravitas' fire, TTLD's staff light and house fires, Area 17's cone, Parts
Needed's form) appear only in animation runs, since CEG runs have no rules.

**Framing.**  The camera stands six def radii from a unit, at least 170 elmos
away.  Some defs declare a radius far below their model (MyCube's iglu: radius
20, about 430 elmos across), which put the camera inside the model.  When the
model's half-extent (from the `UnitDefs[id].model` bounds) reaches past half
that distance, the camera stands six half-extents away instead.  Every unit
whose model is bigger than its radius is logged (`note model-bounds`).  Mere
excess is not reframed, because scaled units (TTLD) and far-off helper pieces
would then be framed too small.

**Renderer.**  Every capture directory and golden has a `renderer.txt`
(backend, GL renderer, GL version, as `vf_renderer_info` writes it).  When any
of them differs from the golden's, the gallery still checks poses and whether
effects appear, and fails, saying which differ (`VF_ALLOW_RENDERER_MISMATCH=1`
skips the pixel comparisons instead).

**Nothing to capture.**  A game without CEGs (MyCube, Parts Needed), or an
`--only` that matches nothing, is skipped with `SKIP ... has no ceg items`.

**CEGs.**  Only game data and drawing are loaded: Lua widgets, rules gadgets
and the synced rules module are stripped from the staged copy; the UI module
(in gallery mode) and any draw-only rules-unsynced module stay.  Each CEG is spawned at fixed land spots, near
(camera distance 180) and far (520), four times each.  Every spawn gets a
background frame and captures 2 and 12 frames after it.  CEG particles use the
engine's unsynced RNG, which nothing can seed, so no two spawns look the same.
Instead, the four spawns' (capture − background) images are averaged at 64x64,
and also compared pooled to 16x16.  Recording runs the gallery four times and
measures how far each run's average strays from the golden built from the
other three.  A capture fails when it strays more than twice that, with a
floor, or when an effect that was visible stops appearing.  The golden is
`fixtures/<game>/goldens/ceg/` (`metrics.json`, the `diffs.png` atlas, and
contact sheets `sheet-*.jpg` to look at).

Deliberately broken CEGs were used to check what this catches (Hunted,
2026-09-23):

| change | result |
| --- | --- |
| recolour flashnuke's smoke | caught, 3–6x limit |
| flashnuke smoke particles 30 → 12 | caught, 1.3–2.1x limit |
| delete a CEG | caught |
| swap one flare texture inside a bunny explosion | **missed** (0.6x) |
| (animations) give a unit another unit's model | caught |

Effects whose randomness is large-scale, like the bunny explosions, get wide
limits.  The report lists every capture's distance and limit, so weakly
guarded effects are visible.

**Animations.**  The game runs as shipped (rules, WASM modules, unit scripts),
with its UI module in gallery mode and `FixedRNGSeed=1`.  Every unit type is spawned at its own
spot and put through idle, a move order and an attack-ground order.  At each
capture the gallery logs every piece's matrix and takes a zoomed image.

Both halves of the gadget compute the same schedule, and the synced half
spawns, orders and removes on fixed absolute frames.  An earlier version
spawned on a Lua message, and the frame it landed on varied.  Game logic that
acts on the gallery's units (Flove's mushroom AI, Area 17's UFO targeting) then
caught them at different moments, and poses differed by up to 17 elmos between
runs.  With the fixed schedule, poses repeat exactly and are compared at 0.01
elmos.  Recording takes two runs.  A shot whose poses still drift is reported,
and held to that drift.

Images still vary where unsynced effects are in view: particles, weather, other
units wandering past.  Each image's limit is 2.5x the difference between the
two recordings, never below 1.5% RMSE.  The Flove poison mushroom, for example,
sits in its own random gas cloud and gets a wide limit, while most shots stay
near 1.5%.  The golden is `fixtures/<game>/goldens/anim/` (`poses.txt`, the
`images.png` atlas, `noise.json`, and `sheet.jpg` to look at).

**Parity** runs the animation gallery on both the WASM port and the original
Lua game, and lists per unit how far their poses differ.  It is a report, not
a pass/fail check: some differences are expected (a Lua unit attacking ground
where the port does not, script timing).

## Screenshots and provenance

The comparison images are tiny (64x64 / 128x128) on purpose.  For people,
recording also keeps full-size captures from the first run and writes one
mosaic per CEG (near/far, early/late) or per unit (every phase) to
`fixtures/<game>/screenshots/{ceg,anim}/<name>.jpg`, using 256 px tiles.
Open these to see what a golden actually looked like.

Every recording writes a `PROVENANCE.txt` next to its goldens
(`fixtures/<game>/goldens/{ceg,anim}/PROVENANCE.txt`, plus
`fixtures/<game>/goldens/PROVENANCE.txt` for scenario screenshots).  It
records:
- this repo's commit;
- the game archive's and map's branch and commit, flagging uncommitted files
  (a folder that isn't the top of its own git checkout, like the extracted
  Area 17 map, is "not version-controlled");
- the engine install with its binary's version string, and the spring-bar
  checkout (`engine src`), whose working tree provides the `spring` crates;
- the springcabal crates: the `springcabal-rs` checkout's commit when
  `.cargo/config.toml` patches it in, else the game's `Cargo.lock` revision;
- the renderer, GPU and GL driver, and a hash of `launch/springsettings.cfg`.

Game repos are never written to; everything lives here.

## Probes

`probes/` holds debugging tools that aren't regression tests. They need
environment variables, a real GPU, or manual steps; each script's header says
which. `verify list` shows them, and `verify all` never runs them.

## Layout

```
verify              dispatcher (suite/mode table, all, visual, goldens, probes)
lib/common.sh       everything shared; suites only describe their game
games/<suite>.sh    per-game build features, staging and assertions
probes/             debugging probes (not part of all/visual)
fixtures/<game>/    probe gadgets, configs, goldens
unit-scripts/       Lua/Rust animation trace comparators
cache/              font cache and build targets, shared across runs
out/<suite>/        logs, screenshots and workspace of the last run
```

`out/` only grows: every suite and probe keeps its last workspace in
`out/<name>/run/`, and ad-hoc runs add directories of their own.
`just clean-verification-out [DAYS] [--dry-run]` deletes every `run/`
workspace, and every directory untouched for DAYS days (default 14).  The
`last.*` logs, screenshots and golden diffs of recent runs stay.  It waits
for a running `verify` first.

Start scripts come from `launch/games/` (`vf_launch_script GAME [wasm|lua]`),
the same files the menu compiles in and `run-wasm.sh` plays.  Suites add what
they need with `vf_modoption test_mode 1` and `vf_start_set ...`. Suites whose scenario needs a special team layout
write theirs inline.

## Writing a suite

```bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

GAME_DIR="$GAMES_DIR/Example-wasm.sdd"

example_headless() {
    local staged
    vf_cleanup_on_exit          # remove the temp workspace, also on Ctrl+C
    vf_build "$GAME_DIR/wasm-src" headless-integration
    vf_workspace example-headless
    staged=$(vf_stage_game "$GAME_DIR")
    vf_install_modules "$staged" example_rules_wasm:LuaRules/wasm/example-rules.wasm
    vf_link_map "$MAPS_DIR/Example-map.sdd" 'Display Name.sdd'
    vf_start_file "$(vf_launch_script example)"
    vf_modoption test_mode 1
    vf_quit_when 'ALL EXAMPLE TESTS PASSED'
    vf_config
    vf_run_headless 45
    vf_save_logs
    vf_require_clean_exit       # quitforce, not the timeout or a crash
    vf_require 'ALL EXAMPLE TESTS PASSED' 'the suite did not complete'
    vf_forbid_runtime_failures
    printf 'assertions passed: %s\n' "$(vf_count 'ASSERTION PASSED')"
}
```

The engine writes every log line to stdout and to the infolog, and
`last.combined.txt` holds both.  `vf_require` and `vf_forbid` search it,
but anything that counts or lists lines reads one log, `vf_count_log` (the
infolog after a clean exit, else stdout): `vf_count` and `vf_summary` do.
Visual runs check `vf_require_exit_or_timeout` instead of
`vf_require_clean_exit`: scenarios that don't quit themselves end by the
timeout (status 124), and their markers and screenshots prove they finished.

Then add the suite and its modes to the tables in `verify`. For a screenshot
mode, end with `vf_goldens_by_index example shot_1 shot_2` (or `vf_golden`
per image) and `vf_goldens_done`.

Every suite calls `vf_forbid_runtime_failures`: no Wasm trap or fault, skipped
callin, panic, borrow conflict, Lua error or crash in the log.  The pattern is
`lib/failures.sh`, which the release smoke test uses too.

Speeds: the engine takes `MinSpeed`/`MaxSpeed` only from `[modoptions]`
(defaults 0.1 and 20; `launch/` sets neither), and starts at 1x clamped into
that range.  `vf_run_headless` runs at 100x and `vf_run_visual` at 1x unless the
suite called `vf_speed MIN [MAX]`.

Other helpers: `vf_config_set`, `vf_run_visual`, `vf_require_screenshots`,
`vf_collect_screenshots`, `vf_rmse`, `vf_within`, `vf_percent`, `vf_count`,
`vf_count_log`, `vf_summary`, `vf_renderer_info`, `vf_renderer_matches`.

A map alias is often needed, because a start script names the map by its
display name, which rarely matches the archive name.

`vf_quit_when MARKER...` (or `vf_quit_when --frame N` for a suite with no
completion marker) ends the run with `quitforce` once every marker has been
logged, instead of letting the timeout kill it. It stages
`fixtures/quit.lua` into the game. Every headless run uses it. Only a clean
exit makes `spring-headless` flush its infolog and lets an ASAN engine check
for leaks; the timeout stays as the backstop.

## ASAN engines and leaks

Point `SPRING_HEADLESS_BIN` / `SPRING_ENGINE_BIN` at an ASAN build (the
engine's `docker-build-v2/build-variants.sh asan` writes
`build-amd64-linux-asan/install`) and run any suite:

```bash
A=../spring-bar/build-amd64-linux-asan/install
SPRING_HEADLESS_BIN=$A/spring-headless SPRING_ENGINE_BIN=$A/spring just verify-all
```

Leak checking is on. `lsan.supp` suppresses only third-party
process-lifetime allocations (the NVIDIA driver); a run whose output contains
a LeakSanitizer report fails. Add an entry only for a stack that never reaches
engine or game code. Leaks are only reported by runs that exit cleanly, which
is why the suites quit themselves.

## The font cache

Every run's `write/fontcache` is a symlink to `cache/fontcache`, so the cache
is built once. Building it from scratch takes over 25 seconds under an ASAN
engine build, which silently ate the whole timeout of the first migrated
visual run.

The archive cache (`write/cache`) stays per suite. It records each archive's
path, so visual suites use a stable workspace under `out/<suite>/run`.

## Gotchas found the hard way

- `test_scenario.lua` in Flove force-sets game speed to 1.0 and `quitforce`s at
  frame 250. A wisp needs 165 frames per stage, so nothing in a default run ever
  leaves wisp stage 1. Any test that depends on later game state has to move
  that frame or drive the state directly.
- Visual suites need `xvfb-run` and ImageMagick (`convert`, `compare`).
- The Lua Gravitas archive can wait at the pre-game boundary under the
  headless engine, and several games start paused or stop logging once
  running. Don't infer progress from the last logged frame number.
