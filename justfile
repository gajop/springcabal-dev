# SpringCabal Games Development Framework

set shell := ["bash", "-cu"]

# Default recipe: show available commands
default:
    @just --list

# Run verification suite (e.g. `just verify area17 all`, `just verify flove`)
verify GAME="list" MODE="":
    ./verification/verify {{GAME}} {{MODE}}

# Run all verification suites
verify-all:
    ./verification/verify all

# List all verification suites and modes
verify-list:
    ./verification/verify list

# Check compilation of all wasm game modules
check-all:
    @for g in Area17 Flove Gravitas Hunted MyCube PartsNeeded ToTheLastDrop; do \
        echo "=== Checking $g ==="; \
        (cd "spring-linux/games/${g}-wasm.sdd/wasm-src" && cargo check --workspace --target wasm32-unknown-unknown) || exit 1; \
    done; \
    echo "=== Checking wasm-menu ==="; \
    (cd "wasm-menu/wasm-src" && cargo check --workspace --target wasm32-unknown-unknown) || exit 1; \
    echo "=== All games check passed ==="

# Build all wasm game modules in release mode
build-all:
    @for g in Area17 Flove Gravitas Hunted MyCube PartsNeeded ToTheLastDrop; do \
        echo "=== Building $g ==="; \
        (cd "spring-linux/games/${g}-wasm.sdd/wasm-src" && cargo build --workspace --target wasm32-unknown-unknown --release) || exit 1; \
    done; \
    echo "=== Building wasm-menu ==="; \
    (cd "wasm-menu/wasm-src" && cargo build --workspace --target wasm32-unknown-unknown --release) || exit 1; \
    echo "=== All games built ==="

# Copy built wasm artifacts into game directories
copy-all:
    @for g in Area17 Flove Gravitas Hunted MyCube PartsNeeded ToTheLastDrop; do \
        echo "=== Copying $g wasm ==="; \
        (cd "spring-linux/games/${g}-wasm.sdd/wasm-src" && just copy) || exit 1; \
    done

# Run setup (downloads engine and clones game repos)
setup:
    ./setup.sh

# Run a game with the engine (e.g. `just run area17`)
run GAME:
    ./run-wasm.sh {{GAME}}
