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
├── wasm-test/, area17-test/ # Launch configs and start scripts used by run-wasm.sh
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
./run-wasm.sh                 # the WASM menu; every game has WASM and Lua buttons
./run-wasm.sh --game flove    # one game directly: hunted, area17, flove, ttld, gravitas
```

### 3. Building & Checking Games
Games depend on `spring` and `spring-addons` via the remote git repository (`https://github.com/gajop/spring-rust`, branch `rust-wip`).

Check compilation across all games:
```bash
just check-all
```

Build release WASM binaries across all games:
```bash
just build-all
just copy-all
```

### 4. Local Engine Co-Development (Overrides)
By default, all games build from the remote git repository (`https://github.com/gajop/spring-rust`, branch `rust-wip`), requiring no engine checkout.

If you are developing on the engine at the same time, you can configure a local override:
```bash
just setup-dev-engine
# Prompts for path (defaults to ../spring-bar), or pass it directly:
# just setup-dev-engine /path/to/spring-engine
```

This creates `.cargo/config.toml` (which is gitignored) with Cargo `[patch]` entries pointing to your local engine's crates:
```toml
[patch."https://github.com/gajop/spring-rust"]
spring = { path = "../spring-bar/rust/crates/spring" }
spring-addons = { path = "../spring-bar/rust/crates/spring-addons" }
```

To revert back to using the remote repository:
```bash
just remove-dev-engine
```


## Verification Suite

The WASM menu uses `wasm-menu/WasmMenu/menu.rml`, `menu.rcss`, and `gallery.rcss`
for layout, gallery styling, and hover. Each game has one row with separate
one-click WASM and Lua buttons. The spotlight shows artwork, original jam date,
and full credits. Mouse hover/scroll previews games independently of keyboard
selection: Up/Down selects a game, Left/Right selects its version, and Enter
launches that keyboard selection. Tab/Shift+Tab traverses the launch buttons.
Official logo sources and attribution are in `wasm-menu/WasmMenu/images/LOGOS.md`.
Rust in `wasm-menu/wasm-src/menu/src/ui.rs` handles RmlUi
events and queues launches until callbacks return; game metadata and launch
settings remain in `lib.rs`. This requires the experimental engine's RmlUi
menu integration. Rebuild Rust changes with:

```bash
just --justfile wasm-menu/wasm-src/justfile copy
```

Restart the engine after editing RML/RCSS (styles may be cached across reloads).
The Hunted Core-WASM launch/return path and repeated Hunted Lua launch/return
cycles have been checked in the same process. Use an engine build containing
the Lua-plugin teardown fix documented in the engine repository's `review.md`.

To test the menu on a separate X display without using your desktop or its
runtime files:
```bash
xvfb-run -a -s '-screen 0 1280x900x24' env SPRING_RUN_DIR=/tmp/springcabal-menu-check ./run-wasm.sh
```

`SPRING_RUN_DIR` defaults to `wasm-test` in this repository. It contains the
launcher's writable data and isolation views.

Run automated headless assertions and visual tests:

```bash
# List available test suites
just verify-list

# Run tests for a specific game
just verify area17 all
just verify flove
just verify gravitas

# Run all verification suites
just verify-all
```
