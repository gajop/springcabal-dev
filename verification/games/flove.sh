#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

GAME_DIR="$GAMES_DIR/Flove-wasm.sdd"
SOURCE_ROOT="$GAME_DIR/wasm-src"
MAP_DIR="$MAPS_DIR/LD34-map.sdd"
MAP_ALIAS='The Grove 0.3.sdd'
FIXTURES="$FIXTURES_DIR/flove"

flove_link() {
    vf_link_game "$GAME_DIR"
    vf_link_map "$MAP_DIR" "$MAP_ALIAS"
}

flove_headless() {
    local seconds=${1:-45}
    trap 'vf_restore_modules "$SOURCE_ROOT"; vf_keep_workspace_unless' EXIT INT TERM

    vf_build "$SOURCE_ROOT" headless-integration
    (
        cd "$SOURCE_ROOT"
        cp target/wasm32-unknown-unknown/release/flove_rules_wasm.wasm "$GAME_DIR/LuaRules/wasm/flove-rules.wasm"
        cp target/wasm32-unknown-unknown/release/flove_ui_wasm.wasm "$GAME_DIR/LuaUI/wasm/flove-ui.wasm"
    )

    vf_workspace flove-headless
    flove_link
    vf_start_file "$FIXTURES/start.txt" 100.0 100.0
    vf_config
    vf_run_headless "$seconds"
    vf_save_logs

    vf_note 'Flove headless run finished'
    printf 'Rust rules assertions passed:  %s\n' "$(vf_count '\[Flove-Rust-Test\] ASSERTION PASSED')"
    printf 'Rust UI input assertions passed: %s\n' "$(vf_count '\[Flove-UI-Test\] ASSERTION PASSED')"
    printf 'Scenario assertions passed:    %s\n' "$(vf_count '\[Flove-Test\] ASSERTION PASSED')"
    vf_summary

    vf_forbid 'ASSERTION FAILED' 'one or more in-game assertions failed'
    vf_require 'ALL FLOVE RUST INTEGRATION TESTS PASSED' 'the Rust rules suite did not complete'
    vf_require 'ALL FLOVE EXTENDED TEST ASSERTIONS PASSED' 'the scenario suite did not complete'
    echo '>>> Flove headless verification passed <<<'
}

flove_visual() {
    local seconds=${1:-45} shots
    trap 'vf_restore_modules "$SOURCE_ROOT"' EXIT INT TERM

    vf_build "$SOURCE_ROOT" headless-integration
    (
        cd "$SOURCE_ROOT"
        cp target/wasm32-unknown-unknown/release/flove_rules_wasm.wasm "$GAME_DIR/LuaRules/wasm/flove-rules.wasm"
        cp target/wasm32-unknown-unknown/release/flove_rules_unsynced_wasm.wasm "$GAME_DIR/LuaRules/wasm/flove-rules-unsynced.wasm"
        cp target/wasm32-unknown-unknown/release/flove_ui_wasm.wasm "$GAME_DIR/LuaUI/wasm/flove-ui.wasm"
    )

    vf_workspace flove-visual stable
    flove_link
    vf_start_file "$FIXTURES/start.txt" 10.0 30.0
    vf_config "$FIXTURES/spring.conf"
    vf_run_visual "$seconds"
    vf_save_logs

    shots=$(vf_require_screenshots 3)
    vf_note 'Flove visual golden moments'
    local index=0 golden
    for golden in "$FIXTURES"/goldens/*.png; do
        index=$((index + 1))
        printf 'shot %d -> %s\n' "$index" "$(basename "$golden")"
    done
    printf 'captured %s screenshot(s) in %s\n' "$shots" "$(vf_collect_screenshots)"
    echo '>>> Flove visual verification passed <<<'
}

flove_outline() {
    local seconds=${1:-60}
    trap 'flove_outline_restore' EXIT INT TERM

    vf_build "$SOURCE_ROOT" headless-integration
    (
        cd "$SOURCE_ROOT"
        cp target/wasm32-unknown-unknown/release/flove_rules_wasm.wasm "$GAME_DIR/LuaRules/wasm/flove-rules.wasm"
        cp target/wasm32-unknown-unknown/release/flove_rules_unsynced_wasm.wasm "$GAME_DIR/LuaRules/wasm/flove-rules-unsynced.wasm"
        cp target/wasm32-unknown-unknown/release/flove_ui_wasm.wasm "$GAME_DIR/LuaUI/wasm/flove-ui.wasm"
    )

    vf_note 'Rendering the Lua gadget baseline'
    cp "$FIXTURES/gadget_gfx_outline.lua" "$GAME_DIR/LuaRules/Gadgets/gfx_outline.lua"
    cat >"$GAME_DIR/LuaRules/wasm/manifest.txt" <<'MANIFEST'
module(flove-rules, LuaRules/wasm/flove-rules.wasm, rules-synced, 0, 1.0.0)
MANIFEST
    flove_outline_shot lua_baseline "$seconds"

    vf_note 'Rendering the Rust WASM port'
    rm -f "$GAME_DIR/LuaRules/Gadgets/gfx_outline.lua"
    cat >"$GAME_DIR/LuaRules/wasm/manifest.txt" <<'MANIFEST'
module(flove-rules, LuaRules/wasm/flove-rules.wasm, rules-synced, 0, 1.0.0)
module(flove-rules-unsynced, LuaRules/wasm/flove-rules-unsynced.wasm, rules-unsynced, 1, 1.0.0)
MANIFEST
    flove_outline_shot rust_wasm "$seconds"

    vf_note 'Comparing'
    local out="$VERIFICATION_ROOT/out/flove-outline"
    compare -metric AE "$out/lua_baseline.png" "$out/rust_wasm.png" "$out/diff.png" 2>&1 || true
    printf '\n%s\n' "baseline: $out/lua_baseline.png"
    printf '%s\n' "port:     $out/rust_wasm.png"
    printf '%s\n' "diff:     $out/diff.png"
}

flove_outline_shot() {
    local tag=${1:?tag} seconds=${2:?seconds} shot
    vf_workspace flove-outline stable
    flove_link
    vf_start_file "$FIXTURES/start.txt" 1.0 1.0
    vf_config "$FIXTURES/spring.conf"
    vf_run_visual "$seconds"

    shot=$(vf_screenshots | head -n 1)
    [[ -n $shot ]] || { vf_save_logs; vf_die "failed to capture $tag.png"; }
    cp "$shot" "$VF_OUT_DIR/$tag.png"
    printf 'captured %s\n' "$VF_OUT_DIR/$tag.png"
}

flove_outline_restore() {
    rm -f "$GAME_DIR/LuaRules/Gadgets/gfx_outline.lua"
    cat >"$GAME_DIR/LuaRules/wasm/manifest.txt" <<'MANIFEST'
module(flove-rules, LuaRules/wasm/flove-rules.wasm, rules-synced, 0, 1.0.0)
module(flove-rules-unsynced, LuaRules/wasm/flove-rules-unsynced.wasm, rules-unsynced, 1, 1.0.0)
MANIFEST
    vf_restore_modules "$SOURCE_ROOT"
}

flove_wisps() {
    local stage=${1:-all} seconds=${2:-90}

    if [[ $stage == all ]]; then
        local st
        for st in 0 1 2 3; do
            flove_wisps_render "$st" "$seconds"
        done
        printf '\nScreenshots are in %s. Pixel diffs between separate runs are not a\n' \
            "$VERIFICATION_ROOT/out/flove-wisps"
        printf 'reliable signal: two runs of the identical config differ by ~11000 pixels.\n'
        return 0
    fi

    flove_wisps_render "$stage" "$seconds"
}

flove_wisps_render() {
    local stage=${1:?stage} seconds=${2:-90} shot
    trap 'flove_wisps_restore' EXIT INT TERM

    flove_helper 0 "$stage" 9999 15 200 >"$GAME_DIR/LuaRules/Gadgets/force_wisps.lua"

    vf_build "$SOURCE_ROOT" headless-integration
    (
        cd "$SOURCE_ROOT"
        cp target/wasm32-unknown-unknown/release/flove_rules_wasm.wasm "$GAME_DIR/LuaRules/wasm/flove-rules.wasm"
        cp target/wasm32-unknown-unknown/release/flove_rules_unsynced_wasm.wasm "$GAME_DIR/LuaRules/wasm/flove-rules-unsynced.wasm"
        cp target/wasm32-unknown-unknown/release/flove_ui_wasm.wasm "$GAME_DIR/LuaUI/wasm/flove-ui.wasm"
    )

    vf_workspace flove-wisps stable
    flove_link
    vf_start_file "$FIXTURES/start.txt" 1.0 1.0
    vf_config "$FIXTURES/spring.conf"
    vf_run_visual "$seconds"
    vf_save_logs

    vf_require '\[Flove-Wisp-Test\]' 'the wisp helper never ran'
    grep -o '\[Flove-Wisp-Test\][^"]*' "$VF_OUT_DIR/last.combined.txt" | tail -1

    shot=$(vf_screenshots | tail -n 1)
    [[ -n $shot ]] || vf_die 'no screenshot captured'
    cp "$shot" "$VF_OUT_DIR/stage$stage.png"
    printf 'stage %s -> %s\n' "$stage" "$VF_OUT_DIR/stage$stage.png"

    local wisps
    wisps=$(grep -o '\[Flove-Wisp-Test\][^"]*' "$VF_OUT_DIR/last.combined.txt" |
        tail -1 | grep -oE 'wisps=[0-9]+' | cut -d= -f2)
    if [[ $stage == -1 || $stage == 0 ]]; then
        return 0
    fi
    [[ ${wisps:-0} -gt 0 ]] || vf_die 'the trees carry no wisps at all'
}

flove_wisps_restore() {
    rm -f "$GAME_DIR/LuaRules/Gadgets/force_wisps.lua"
    vf_restore_modules "$SOURCE_ROOT"
}

flove_helper() {
    sed -e "s/__FORCE_START__/${1:?}/" -e "s/__STAGE__/${2:?}/" -e "s/__COUNT__/${WISP_COUNT:-6}/" \
        -e "s/__SHOT_NATURAL__/${3:?}/" -e "s/__PIN_FROM__/${4:?}/" -e "s/__SHOT_PINNED__/${5:?}/" \
        "$FIXTURES/gadget_force_wisps.lua"
}

flove_original() {
    local seconds=${1:-200} staged shot
    ORIGINAL_DIR="$GAMES_DIR/Flove.sdd"
    [[ -d $ORIGINAL_DIR ]] || vf_die "the pre-port game is not present: $ORIGINAL_DIR"

    vf_workspace flove-original stable
    staged=$(vf_stage_game "$ORIGINAL_DIR")
    sed 's/__SHOT_FRAME__/600/' "$FIXTURES/gadget_original_boot.lua" \
        >"$staged/LuaRules/Gadgets/original_boot.lua"
    flove_helper 1 -1 9999 9999 9999 >"$staged/LuaRules/Gadgets/force_wisps.lua"
    vf_link_map "$MAP_DIR" "$MAP_ALIAS"

    sed 's/gametype=[^;]*;/gametype=Flove $VERSION;/' "$FIXTURES/start.txt" \
        >"$VF_OUT_DIR/original-start.txt"
    vf_start_file "$VF_OUT_DIR/original-start.txt" 1.0 1.0
    vf_config "$FIXTURES/spring.conf"
    vf_run_visual "$seconds"
    vf_save_logs

    vf_require '\[Flove-Wisp-Test\] original' 'the original game never reached the sample frame'
    grep -o '\[Flove-Wisp-Test\][^"]*' "$VF_OUT_DIR/last.combined.txt" | tail -1

    shot=$(vf_screenshots | tail -n 1)
    [[ -n $shot ]] || vf_die 'no screenshot captured'
    cp "$shot" "$VF_OUT_DIR/original.png"
    printf 'original -> %s\n' "$VF_OUT_DIR/original.png"
}

case "${1:-headless}" in
    headless) flove_headless "${2:-}" ;;
    visual) flove_visual "${2:-}" ;;
    outline) flove_outline "${2:-}" ;;
    wisps) flove_wisps "${2:-}" "${3:-}" ;;
    original) flove_original "${2:-}" ;;
    *) vf_die 'usage: flove.sh [headless|visual|outline] [seconds] | wisps [stage] [seconds]' ;;
esac
