#!/usr/bin/env bash

set -euo pipefail

VERIFICATION_ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=failures.sh
source "$VERIFICATION_ROOT/lib/failures.sh"
PROJECT_ROOT=$(CDPATH= cd -- "$VERIFICATION_ROOT/.." && pwd)
ENGINE_ROOT=${SPRING_BAR_DIR:-$(dirname "$PROJECT_ROOT")/spring-bar}
# Same lookup order as run-wasm.sh: SPRING_ENGINE_DIR, the spring-bar build,
# then the release fetched by setup.sh.
ENGINE_INSTALL=${SPRING_ENGINE_DIR:-$ENGINE_ROOT/build-amd64-linux/install}
if [[ -z ${SPRING_ENGINE_DIR:-} && ! -x $ENGINE_INSTALL/spring && -x $PROJECT_ROOT/engine/current/spring ]]; then
    ENGINE_INSTALL="$PROJECT_ROOT/engine/current"
fi

# VF_GAMES_DIR points suites at other game checkouts (worktrees on a branch).
GAMES_DIR=${VF_GAMES_DIR:-$PROJECT_ROOT/spring-linux/games}
MAPS_DIR="$PROJECT_ROOT/spring-linux/maps"
FIXTURES_DIR="$VERIFICATION_ROOT/fixtures"
SHARED_FONTCACHE="$VERIFICATION_ROOT/cache/fontcache"

LAUNCH_DIR="$PROJECT_ROOT/launch"
# Every run uses the settings players get: the release profile that
# release/package.sh ships, plus the menu's per-game overrides (vf_graphics).
DEFAULT_CONFIG="$LAUNCH_DIR/springsettings.cfg"
VISUAL_CONFIG="$DEFAULT_CONFIG"
BUILD_CACHE="$VERIFICATION_ROOT/cache/target"
GOLDEN_FAILURES=0

VF_TEST_ROOT=""
VF_ISOLATION=""
VF_WRITE_DIR=""
VF_START_FILE=""
VF_CONFIG_FILE=""
VF_OUT_DIR=""
VF_ENGINE_STATUS=0
VF_BUILD_OUT=""

vf_die() {
    printf '%s\n' "$*" >&2
    exit 1
}

vf_note() {
    printf '\n=== %s ===\n' "$*"
}

# shellcheck source=build.sh
source "$VERIFICATION_ROOT/lib/build.sh"
# shellcheck source=run.sh
source "$VERIFICATION_ROOT/lib/run.sh"
# shellcheck source=results.sh
source "$VERIFICATION_ROOT/lib/results.sh"
