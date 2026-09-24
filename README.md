# SpringCabal Games Development Framework

A unified development environment, test harness, and build framework for SpringCabal WebAssembly games on the Spring / Recoil engine.

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
├── setup.sh                 # Clones content.tsv into spring-linux/, optionally fetches an engine
├── run-wasm.sh              # Launches the WASM menu or a single game
├── wasm-menu/               # The game-selection menu (RmlUi + Rust/WASM)
├── release/                 # Release packaging and smoke test (see RELEASING.md)
├── verification/            # Automated test suite (headless, visual, static)
├── game-info/               # Archived jam entries (descriptions, credits, ratings)
├── launch/                  # The one source of launch settings (see "Launch settings")
├── patches/                 # Patches applied to third-party archives (Area 17 map)
├── scripts/                 # Helper scripts (patched map builder)
├── justfile                 # Root commands for building, checking, testing, releasing
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

This clones every repository listed in `content.tsv` into `spring-linux/`
(existing checkouts are left alone) and downloads that Linux engine release from
`gajop/spring-rust` into `engine/`. Entries marked `local` or `download`, and the
`*-wasm-port` branches until they are published, have to be copied in by hand;
setup lists whatever it could not fetch.

`run-wasm.sh` picks the engine in this order: `$SPRING_ENGINE_DIR`, a local
engine build at `../spring-bar/build-amd64-linux/install` (override the checkout
with `$SPRING_BAR_DIR`), then `engine/current` from setup.

### 2. Running

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
| `launch/games/<game>/wasm.txt`, `lua.txt` (`gravitas/editor.txt`) | the start script for each menu button |
| `launch/games/<game>/graphics.cfg` | per-game overrides applied on top when that game starts |
| `launch/local.cfg` (gitignored) | your window size/position, for `run-wasm.sh` only |

The menu compiles `launch/games/` in (`include_str!`). After editing it, rebuild
the menu with `just --justfile wasm-menu/wasm-src/justfile copy`.
`run-wasm.sh` warns about a stale menu build, and `release/package.sh` refuses
to ship one.

### 3. Building & Checking Games
Games depend on `spring` and `spring-addons` from the engine repository
(`https://github.com/gajop/spring-rust`, branch `rust-wip`), and on the shared
`springcabal` crates from the private repository
`ssh://git@github.com/gajop/springcabal-rs.git`.

```bash
just check-all     # cargo check every WASM game and the menu
just build-all     # fmt + clippy + release build, installed into each game
```

**The private crate.** Fetching `springcabal-rs` needs SSH access to
`github.com/gajop/springcabal-rs` (an SSH key GitHub accepts, loaded in your
agent or configured in `~/.ssh/config`). Cargo's built-in git client does not
use your SSH setup, so `.cargo/config.toml` sets
`[net] git-fetch-with-cli = true`, which makes Cargo fetch through the `git`
command. `./setup.sh` clones the crate into `springcabal-rs/` (its own
repository, gitignored here) and writes `.cargo/config.toml` if there is none.

### 4. Local Engine Co-Development (Overrides)
`.cargo/config.toml` (gitignored) is generated by `setup.sh`; regenerate it
rather than editing it. It holds:
- `[patch."https://github.com/gajop/spring-rust"]`: `spring` and
  `spring-addons` from a local engine checkout, when you develop the engine
  at the same time;
- `[patch."ssh://git@github.com/gajop/springcabal-rs.git"]`: every crate in
  the local `springcabal-rs/` checkout (`springcabal`, `springcabal-control`);
- `[net] git-fetch-with-cli = true`.

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
spring = { path = "../spring-bar/rust/crates/spring" }
spring-addons = { path = "../spring-bar/rust/crates/spring-addons" }

[patch."ssh://git@github.com/gajop/springcabal-rs.git"]
springcabal = { path = "springcabal-rs/crates/springcabal" }
springcabal-control = { path = "springcabal-rs/crates/springcabal-control" }

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

`wasm-menu/wasm-src/menu/src/ui.rs` handles RmlUi events and queues launches
until callbacks return; game metadata and launch settings (start scripts,
graphics overrides) live in `lib.rs`. Rebuild after Rust changes with
`just --justfile wasm-menu/wasm-src/justfile copy`, and restart the engine after
editing RML/RCSS (styles may be cached across reloads).

Games return to the menu in-process (`reloadforce`). `run-wasm.sh` relaunches
the menu only when a game logs a return marker and then quits the process.

To try the menu on a separate X display without touching your runtime files:
```bash
xvfb-run -a -s '-screen 0 1280x900x24' env SPRING_RUN_DIR=/tmp/springcabal-menu-check ./run-wasm.sh
```
`SPRING_RUN_DIR` (default `wasm-test/`, gitignored) holds the launcher's write
dir, logs and isolation views.

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
