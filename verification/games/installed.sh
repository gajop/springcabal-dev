#!/usr/bin/env bash
# The modules installed in each game folder (what the menu starts and the
# release ships) match a fresh build of the game's wasm-src/.
#
#   installed.sh [game|all]
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

installed_check() {
    local target=${1:-all} dir failed=()
    local -a dirs
    # A game is named by the start of its folder (area17, ttld is ToTheLastDrop).
    [[ $target == ttld ]] && target=ToTheLastDrop
    mapfile -t dirs < <(printf '%s\n' "$GAMES_DIR"/*-wasm.sdd |
        { [[ $target == all ]] && cat || grep -i "/$target[^/]*$"; })
    [[ ${#dirs[@]} -gt 0 ]] || vf_die "no game matches: $target"
    for dir in "${dirs[@]}"; do
        vf_note "$(basename "$dir")"
        VF_OUT_DIR="$VERIFICATION_ROOT/out/installed-$(basename "$dir" -wasm.sdd)"
        mkdir -p "$VF_OUT_DIR"
        ( vf_installed_matches_source "$dir" ) || failed+=("$(basename "$dir")")
    done
    [[ ${#failed[@]} -eq 0 ]] || vf_die "installed modules differ from the source: ${failed[*]}"
    echo '>>> Installed modules match their source <<<'
}

installed_check "${1:-all}"
