# SpringCabal Games Development Framework

A unified development environment, test harness, and build framework for SpringCabal WebAssembly games on the Spring / Recoil engine.

## Play the games

Download the Linux or Windows bundle from [Releases](https://github.com/gajop/springcabal-dev/releases).
Each includes all seven games in both WASM and Lua, the menu, engine and maps.
Extract it and run `SpringCabal` on Linux or `SpringCabal.exe` on Windows.

## Overview

This repository provides:
- **Common Dev Tools**: Launchers, headless simulation harnesses, and visual regression testing (`verification/`).
- **Unified Just Commands**: Standardized commands (`just check-all`, `just build-all`, `just verify ...`) for multi-game workflows.
- **Crate Overrides**: Seamless local engine co-development via Cargo configuration (`.cargo/config.toml`).
- **Release Packaging**: Linux and Windows bundles of the engine, menu, games and maps (`release/`, see [RELEASING.md](RELEASING.md)).

## Directory Layout

Original jam descriptions, ratings, credits, links, and unique website screenshots
are archived in [game-info/](game-info/README.md).

```text
├── content.tsv              # Every game/map/project: source repo, branch, shipped or not
├── setup.sh                 # Clones content.tsv and springcabal-rs, writes .cargo/config.toml,
│                            #   optionally fetches an engine
├── run-wasm.sh              # Launches the WASM menu or a single game
├── wasm-menu/               # The game-selection menu (RmlUi + Rust/WASM)
├── release/                 # Release packaging and smoke test
├── RELEASING.md             # How releases are built and published
├── verification/            # Automated test suite (headless, visual, static)
├── BASELINE.md              # The last verified state: suite results and counts
├── TODO.md                  # Current rating of every WASM and Lua version
├── docs/                    # Code reviews of the WASM ports
├── game-info/               # Archived jam entries (descriptions, credits, ratings)
├── launch/                  # The one source of launch settings (see "Launch settings")
├── patches/                 # Patches applied to third-party archives (Area 17 map)
├── scripts/                 # Helper scripts (patched map builder)
├── justfile                 # Root commands for building, checking, testing, releasing
├── springcabal-rs/          # (Gitignored, separate public repo) the shared springcabal crates
└── spring-linux/            # (Gitignored) game and map checkouts
```

Game and map sources stay in their own repositories (mostly under
github.com/SpringCabal); this repository only holds the tooling around them.

## Getting Started

### Prerequisites

Linux with `git`, `just`, `7z`, `rsync`, `zip`, the GitHub CLI (`gh`, logged in),
and a Rust toolchain with the `wasm32-unknown-unknown` target:
```bash
rustup target add wasm32-unknown-unknown
```

### 1. Content and engine

```bash
./setup.sh --engine-tag 2026.09.23   # or: just setup 2026.09.23
```

This clones every repository listed in `content.tsv` into `spring-linux/` (existing checkouts are left alone) and downloads that Linux engine release from `gajop/spring-rust` into `engine/`. Entries marked `local` or `download`, and any game branches that have not been published, have to be copied in by hand; setup lists whatever it could not fetch. Release source snapshots include the local game and shared-crate revisions, which may not yet be available on their individual repositories' branches.

`run-wasm.sh` picks the engine in this order: `$SPRING_ENGINE_DIR`, a local
engine build at `../spring-bar/build-amd64-linux/install` (override the checkout
with `$SPRING_BAR_DIR`), then `engine/current` from setup.

### 2. Running

Every Lua and WASM game reserves Pause for pausing, F12 for screenshots and Ctrl+Q for returning to the menu. Default RTS keyboard orders are disabled. The shared controls live in the engine’s `LuaHandler/Utilities/game_controls.lua` for Lua and `springcabal::controls::GameControls` for WASM. These local review branches require the current development engine, including its rebuilt `springcontent.sdz`.

```bash
./run-wasm.sh                        # the WASM menu; every game has WASM and Lua buttons
./run-wasm.sh --game flove           # one game directly (every game in launch/games/)
./run-wasm.sh --game flove --lua     # the original Lua version
./run-wasm.sh --game gravitas --editor
```

### Launch settings

`launch/` is the only place launch settings live. The menu, `run-wasm.sh`,
verification, the smoke test and the release all read from it:

| file | what |
| --- | --- |
| `launch/springsettings.cfg` | graphics/UI profile; shipped as the release's `springsettings.cfg` |
| `launch/menu.cfg` | default menu for direct executable startup in portable bundles |
| `launch/games/<game>/wasm.txt`, `lua.txt` (`gravitas/editor.txt`) | the start script for each menu button |
| `launch/games/<game>/graphics.cfg` | per-game overrides applied on top when that game starts |
| `launch/local.cfg` (gitignored) | your window size/position, for `run-wasm.sh` only |

The menu compiles `launch/games/` in (`include_str!`). After editing it, rebuild
the menu with `just --justfile wasm-menu/wasm-src/justfile copy`.
`run-wasm.sh` warns about a stale menu build, and `release/package.sh` refuses
to ship one.

### 3. Building & Checking Games
Games depend on `spring-sdk` (imported as `spring`) and `spring-addons` from
the engine repository (`https://github.com/gajop/spring-rust`, branch
`rust-wip`), and on the shared `springcabal` crates through local path
dependencies in `springcabal-rs/`.

```bash
just check-all     # cargo check every WASM game and the menu
just build-all     # fmt + clippy + release build, installed into each game
```

`./setup.sh` clones the public `springcabal-rs` repository into
`springcabal-rs/` (a separate repository, gitignored here) and generates
`.cargo/config.toml` for local development.

### 4. Local Engine Co-Development (Overrides)
`.cargo/config.toml` (gitignored) is generated by `setup.sh`; regenerate it
rather than editing it. It holds:
- `[patch."https://github.com/gajop/spring-rust"]`: `spring-sdk` and
  `spring-addons` from a local engine checkout, when you develop the engine
  at the same time;
- `[net] git-fetch-with-cli = true`.

The shared crates already use local paths, so they need no Git patches.
Avoid obsolete or unused overrides: they can reorder Cargo's unused-patch
lockfile entries and make `--locked` checks fail.

```bash
just setup-dev-engine                   # engine crates from ../spring-bar
just setup-dev-engine /path/to/engine   # or another checkout
just remove-dev-engine                  # engine crates from git again
```

Both recipes run `./setup.sh --dev-engine [PATH]` / `--no-dev-engine`. When
the file changes, they print a diff and keep the old one as
`.cargo/config.toml.bak`. Paths are relative to this directory:
```toml
[patch."https://github.com/gajop/spring-rust"]
spring-addons = { path = "../spring-bar/rust/crates/spring-addons" }
spring-sdk = { path = "../spring-bar/rust/crates/spring-sdk" }

[net]
git-fetch-with-cli = true
```


## The WASM menu

`wasm-menu/WasmMenu/menu.rml`, `menu.rcss` and `gallery.rcss` define layout,
gallery styling and hover. Each game has one row with WASM and Lua buttons; the
spotlight shows artwork, the original jam date and full credits. Mouse
hover/scroll previews games independently of keyboard selection: Up/Down selects
a game, Left/Right its version, Enter launches, Tab/Shift+Tab walks the buttons.
Logo sources and attribution are in `wasm-menu/WasmMenu/images/LOGOS.md`.

`wasm-menu/wasm-src/menu/src/catalog.rs` contains each game's metadata, articles and launch scripts. `navigation.rs` handles arrow navigation; RmlUi handles Tab order, focus and button events. `model.rs` supplies data to the external RML templates, and `ui.rs` queues launches until callbacks return. Rebuild the menu after changing Rust or an embedded template with `just --justfile wasm-menu/wasm-src/justfile copy`; restart the engine after editing styles, which may be cached across reloads.

Games return to the menu in-process (`reloadforce`, e.g. Ctrl+Q). A game
launched directly (`./run-wasm.sh --game ...`) is started with the WASM menu
named as the engine's menu, so quitting it lands in the WASM menu as well.

To try the menu with invisible GPU rendering and separate runtime files:
```bash
SDL_VIDEODRIVER=offscreen SPRING_RUN_DIR=/tmp/springcabal-menu-check ./run-wasm.sh
```
`SPRING_RUN_DIR` (default `wasm-test/`, gitignored) contains stable isolation views and separate `<game-or-menu>/write` directories for configuration, logs and caches. Different launch modes can run together; a lock prevents two sessions from sharing the same mode's files. Use another `SPRING_RUN_DIR` for a second copy of the same game.

## Verification

```bash
just verify-list             # suites, modes, probes
just verify flove            # one suite, default mode
just verify-all              # every assertion suite and static check
just verify-visual           # screenshot suites against committed goldens
just update-goldens flove    # re-record goldens after an intended change
```

Suites build test modules into `verification/cache/` and stage copies of the
games, so they never modify `spring-linux/`. See
[verification/README.md](verification/README.md).
