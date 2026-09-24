# SpringCabal Games Development Framework

set shell := ["bash", "-cu"]

# Default recipe: show available commands
[private]
default:
    @just --list

# WASM game checkouts, from content.tsv (e.g. spring-linux/games/Flove-wasm.sdd)
wasm_games := `awk -F'\t' '$1 == "game" && $2 ~ /-wasm\.sdd$/ { printf "spring-linux/games/%s ", $2 }' content.tsv`

# Run one suite, default mode if MODE is empty (e.g. `just verify flove visual`)
[group('test')]
verify SUITE MODE="" *ARGS:
    ./verification/verify {{SUITE}} {{MODE}} {{ARGS}}

# Every in-game assertion suite and static check, no screenshots (unit-scripts needs xvfb)
[group('test')]
verify-all:
    ./verification/verify all

# Every screenshot suite, compared against the committed goldens
[group('test')]
verify-visual:
    ./verification/verify visual

# List suites, their modes, and the probes
[group('test')]
verify-list:
    ./verification/verify list

# Re-record goldens from fresh renders (all suites, or one: `just update-goldens flove`)
[group('test')]
update-goldens SUITE="":
    ./verification/verify update-goldens {{SUITE}}

# Run a debugging probe from verification/probes (e.g. `just probe gravitas-fire lua`)
[group('probe')]
probe NAME *ARGS:
    ./verification/verify probe {{NAME}} {{ARGS}}

# cargo check every WASM game and the menu
[group('build')]
check-all:
    @for g in {{wasm_games}} wasm-menu; do \
        echo "=== Checking $g ==="; \
        (cd "$g/wasm-src" && cargo check --workspace --target wasm32-unknown-unknown) || exit 1; \
    done

# Build (fmt, clippy, release) and install the modules of every WASM game and the menu
[group('build')]
build-all:
    @for g in {{wasm_games}} wasm-menu; do \
        echo "=== Building $g ==="; \
        (cd "$g/wasm-src" && just copy) || exit 1; \
    done

# Build the patched Area 17 map into build/maps/
[group('build')]
area17-map:
    ./scripts/area17-map.sh

# Clone game/map repos from content.tsv (optionally fetch an engine release: `just setup 2026.09.23`)
[group('run')]
setup ENGINE_TAG="":
    ./setup.sh {{ if ENGINE_TAG != "" { "--engine-tag " + ENGINE_TAG } else { "" } }}

# Launch the WASM menu, or one game directly (e.g. `just run area17`)
[group('run')]
run GAME="":
    ./run-wasm.sh {{ if GAME != "" { "--game " + GAME } else { "" } }}

# Build Linux + Windows release bundles (e.g. `just package 2026.09.23`)
[group('release')]
package ENGINE_TAG *ARGS:
    ./release/package.sh --engine-tag {{ENGINE_TAG}} {{ARGS}}

# Smoke-test an assembled Linux bundle (every menu entry + menu boot)
[group('release')]
smoke-test BUNDLE:
    ./release/smoke-test.sh {{BUNDLE}}

# Build games against a local engine checkout's crates (default ../spring-bar); writes .cargo/config.toml
[group('engine')]
setup-dev-engine ENGINE_PATH="":
    ./setup.sh --dev-engine {{ENGINE_PATH}}

# Build games against the engine crates from git again (keeps the springcabal-rs patch)
[group('engine')]
remove-dev-engine:
    ./setup.sh --no-dev-engine
