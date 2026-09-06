# Verification

One place for every game's automated checks. Before this existed the same
eight-line preamble (find the engine, build an isolation view, symlink base and
fonts, randomise the host port, run under `timeout`, grep the log) was
copy-pasted into 18 scripts across `area17-test/`, `wasm-test/`,
`claude-work/gravitas-test/`, `gemini-work/flove-test/` and the repo root.

## Running

```bash
./verification/verify list
./verification/verify flove                 # default mode
./verification/verify flove visual
./verification/verify flove outline 60      # mode + seconds
./verification/verify ports headless partsneeded
./verification/verify all                   # every suite, default mode
```

| game | modes |
| --- | --- |
| `area17` | `static` \| `headless` \| `visual` \| `all` |
| `flove` | `headless` \| `visual` \| `outline` \| `wisps` \| `original` |
| `gravitas` | `e2e` \| `shots` \| `headless` |
| `hunted` | `headless` |
| `ports` | `headless` \| `visual` — plus `mycube` \| `partsneeded` \| `all` |
| `ttld` | `headless` \| `visual` |

`static` is build hygiene only (fmt, clippy, installed artifacts match source).
`headless` runs the in-game assertions under `spring-headless`. `visual` renders
under xvfb with software GL and checks screenshots. `outline` and `shots` are
image comparisons against a reference. `flove wisps [0|1|2|3|all]` pins every
tree's wisps to a stage and reports the stage histogram plus a screenshot, so the
effect can be inspected without waiting the 165 frames per stage the game needs.
`flove original` renders the pre-port `Flove.sdd` from a staged copy for A/B
against the port.

## Layout

```
verify              dispatcher
lib/common.sh       everything shared; suites only describe their game
games/<game>.sh     per-game config, install steps and assertions
fixtures/<game>/    start scripts, configs, goldens
cache/fontcache     shared font cache, built once (see below)
out/<suite>/        logs, screenshots and workspace for the last run
```

Suites read `wasm-test/spring.conf` and `area17-test/spring.conf` in place
rather than keeping a copy, because the launchers (`run-wasm.sh`,
`run-area17-wasm.sh`) own those files.

## The font cache

`lib/common.sh` symlinks every run's `write/fontcache` at `cache/fontcache`, so
the cache is built once and shared by every suite forever after. Do not point a
suite at a fresh per-run fontcache: building it from scratch takes over 25
seconds under an ASAN engine build, which silently ate the whole timeout budget
of the first migrated visual run.

The archive cache (`write/cache`) stays per-suite. It records each archive's
info-file path, so a workspace that moves between runs makes every entry stale;
visual suites therefore use a stable workspace under `out/<suite>/run`.

## Writing a suite

Source the library, describe the game, call the helpers:

```bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

GAME_DIR="$GAMES_DIR/Example-wasm.sdd"

example_headless() {
    vf_build "$GAME_DIR/wasm-src" headless-integration
    vf_workspace example-headless
    vf_link_game "$GAME_DIR"
    vf_link_map "$MAPS_DIR/Example-map.sdd" 'Display Name.sdd'
    vf_start_file "$FIXTURES_DIR/example/start.txt" 100.0 100.0
    vf_config
    vf_run_headless 45
    vf_save_logs
    vf_require 'ALL EXAMPLE TESTS PASSED' 'the suite did not complete'
    vf_forbid 'panic|Wasm.*trap' 'the run contains a runtime failure'
}
```

Useful helpers beyond those: `vf_stage_game` (copy instead of symlink, for
suites that must not touch the shipped archive), `vf_write_settings`,
`vf_run_visual`, `vf_require_screenshots`, `vf_collect_screenshots`, `vf_rmse`,
`vf_within`, `vf_percent`, `vf_count`, `vf_summary`, `vf_restore_modules`.

A map alias is often needed because a start script names the map by its display
name, which rarely matches the archive directory name.

## Gotchas found the hard way

- `test_scenario.lua` in Flove force-sets game speed to 1.0 and `quitforce`s at
  frame 250. A wisp needs 165 frames per stage, so nothing in a default run ever
  leaves wisp stage 1. Any test that depends on later game state has to move
  that frame or drive the state directly rather than waiting for it.
- Visual suites need `xvfb-run` and ImageMagick (`convert`, `compare`).
- **Renders are not deterministic between runs.** Two runs of the identical
  config differ by roughly 11000 pixels at 1280x720. Never build an assertion on
  a pixel diff between two separate runs; it will measure noise. Compare within a
  run, compare against a committed golden with a generous RMSE tolerance (as
  `gravitas shots` does), or assert on values the simulation reports rather than
  on pixels.
