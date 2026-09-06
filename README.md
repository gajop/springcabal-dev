# SpringCabal Games Development Framework

A unified development environment, test harness, and build framework for SpringCabal WebAssembly games on the Spring / Recoil engine.

## Overview

This repository provides:
- **Common Dev Tools**: Launchers, headless simulation harnesses, and visual regression testing (`verification/`).
- **Unified Just Commands**: Standardized commands (`just check-all`, `just build-all`, `just verify ...`) for multi-game workflows.
- **Crate Overrides**: Seamless local engine co-development via Cargo configuration (`.cargo/config.toml`).

## Directory Layout

```text
├── .cargo/config.toml       # Local engine development crate overrides
├── verification/            # Automated test suite (headless, visual, static)
│   ├── verify               # Unified test dispatcher
│   ├── games/               # Per-game test drivers
│   ├── fixtures/            # Golden images, start scripts, configs
│   └── lib/                 # Shared verification bash library
├── justfile                 # Root commands for building, checking, and testing
├── setup.sh                 # Environment setup script (downloads engine & maps)
├── run-wasm.sh              # Game launcher script
└── spring-linux/            # (Gitignored) Engine runtime and game checkouts
```

## Getting Started

### 1. Initial Setup
Download the portable engine runtime and game repositories:
```bash
just setup
# or ./setup.sh
```

### 2. Building & Checking Games
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

### 3. Local Engine Co-Development (Overrides)
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
