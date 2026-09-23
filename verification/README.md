# Verification

Automated checks for every game, driven from the repository root with `just`:

```bash
just verify-list                 # suites, modes, probes
just verify flove                # one suite, default mode
just verify flove visual         # one suite, one mode
just verify-all                  # every headless/static suite
just verify-visual               # every screenshot suite against its goldens
just update-goldens [suite]      # re-record goldens after an intended change
just probe gravitas-fire lua     # a debugging probe
```

(`./verification/verify …` takes the same arguments.)

| suite | modes (first = default) |
| --- | --- |
| `area17` | `headless` \| `visual` \| `static` \| `all` |
| `flove` | `headless` \| `visual` \| `outline` \| `wisps [stage]` \| `original` |
| `gravitas` | `e2e` \| `shots` \| `headless` |
| `hunted` | `headless` \| `visual` |
| `mycube` | `headless` \| `visual` \| `lua-headless` |
| `partsneeded` | `headless` \| `visual` |
| `ttld` | `headless` \| `visual` \| `lua-visual` \| `pose-parity` |
| `unit-scripts` | `partsneeded` \| `source` |

- `headless` runs the in-game assertions (modules built with the
  `headless-integration` feature) under `spring-headless`.
- `visual` renders under xvfb with software GL, runs the `e2e` feature's
  scripted scenario and compares its screenshots with goldens.
- `static` is build hygiene only (fmt, clippy, installed artifacts match source).
- `lua-*` modes check the original Lua game on this engine.
- `pose-parity` and `unit-scripts` compare Lua and Rust unit-script animation
  traces numerically.
- `flove outline`, `wisps` and `original` render images for manual A/B
  inspection and do not fail on pixels.

`verify all` runs every in-game assertion suite. `verify visual` runs every
golden comparison. Both run their mode list from the table in `verify`.

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
| area17 | 2.8% | 5% |
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
fixtures/visual.conf  engine config for every visual suite
fixtures/<game>/    probe gadgets, configs, goldens
unit-scripts/       Lua/Rust animation trace comparators
cache/              font cache and build targets, shared across runs
out/<suite>/        logs, screenshots and workspace of the last run
```

Start scripts come from `launch/` (the same files `run-wasm.sh` plays), and
suites add what they need with `vf_modoption test_mode 1` and
`vf_start_set gametype ...`. Suites whose scenario needs a special team layout
write theirs inline.

## Writing a suite

```bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

GAME_DIR="$GAMES_DIR/Example-wasm.sdd"

example_headless() {
    local staged
    vf_build "$GAME_DIR/wasm-src" headless-integration
    vf_workspace example-headless
    staged=$(vf_stage_game "$GAME_DIR")
    vf_install_modules "$staged" example_rules_wasm:LuaRules/wasm/example-rules.wasm
    vf_link_map "$MAPS_DIR/Example-map.sdd" 'Display Name.sdd'
    vf_start_file "$LAUNCH_DIR/example.txt" 100.0 100.0
    vf_modoption test_mode 1
    vf_config
    vf_run_headless 45
    vf_save_logs
    vf_require 'ALL EXAMPLE TESTS PASSED' 'the suite did not complete'
    vf_forbid 'panic|Wasm.*trap' 'the run contains a runtime failure'
}
```

Then add the suite and its modes to the tables in `verify`. For a screenshot
mode, end with `vf_goldens_by_index example shot_1 shot_2` (or `vf_golden`
per image) and `vf_goldens_done`.

Other helpers: `vf_write_settings`, `vf_run_visual`, `vf_require_screenshots`,
`vf_collect_screenshots`, `vf_rmse`, `vf_within`, `vf_percent`, `vf_count`,
`vf_summary`.

A map alias is often needed, because a start script names the map by its
display name, which rarely matches the archive name.

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
