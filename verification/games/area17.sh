#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

# Golden RMSE limit.  Run-to-run drift measured 0.4-5.5% (2026-09-23); the
# scenario runs in real time, not frame-locked like the galleries.
GOLDEN_TOLERANCE=${GOLDEN_TOLERANCE:-8}

GAME_DIR="$GAMES_DIR/Area17-wasm.sdd"
SOURCE_ROOT="$GAME_DIR/wasm-src"
START_FILE="$(vf_launch_script area17)"
MODULES=(
    area17_rules_wasm:LuaRules/wasm/area17-rules.wasm
    area17_ui_wasm:LuaUI/wasm/area17-ui.wasm
)

# Stages the game with modules built for FEATURES, plus the patched map.
area17_stage() {
    local features=$1 staged
    vf_build "$SOURCE_ROOT" "$features"
    staged=$(vf_stage_game "$GAME_DIR")
    vf_install_modules "$staged" "${MODULES[@]}"
    vf_link_map "$("$PROJECT_ROOT/scripts/area17-map.sh" --dir)"
}

area17_static() {
    local target_root="$SOURCE_ROOT/target/wasm32-unknown-unknown/release" artifact

    (
        cd "$SOURCE_ROOT"
        cargo fmt --all -- --check
        cargo clippy --workspace --target wasm32-unknown-unknown --release -- -D warnings
        cargo build --workspace --target wasm32-unknown-unknown --release
    )

    for artifact in area17_rules_wasm.wasm area17_ui_wasm.wasm; do
        [[ -s "$target_root/$artifact" ]] || vf_die "missing build artifact: $artifact"
    done

    cmp "$target_root/area17_rules_wasm.wasm" "$GAME_DIR/LuaRules/wasm/area17-rules.wasm"
    cmp "$target_root/area17_ui_wasm.wasm" "$GAME_DIR/LuaUI/wasm/area17-ui.wasm"

    if grep -rnE --include='*.rs' '\bunsafe\b|align4|to_le_bytes|from_le_bytes|#!\[allow\(clippy::all\)\]' \
        "$SOURCE_ROOT/rules-synced/src" "$SOURCE_ROOT/ui/src"; then
        vf_die 'Area 17 source contains unsafe/ABI-packing/lint-suppression code'
    fi

    local manifest
    for manifest in "$GAME_DIR/LuaRules/wasm/manifest.txt" "$GAME_DIR/LuaUI/wasm/manifest.txt"; do
        [[ $(grep -c '^module(' "$manifest") -eq 1 ]] || vf_die "expected exactly one module in $manifest"
    done

    echo '>>> Area 17 static verification passed <<<'
}

area17_headless() {
    local seconds=${1:-90}
    vf_cleanup_on_exit

    vf_workspace area17-headless
    area17_stage headless-integration
    vf_start_file "$START_FILE" 100.0 100.0
    vf_modoption test_mode 1
    vf_quit_when 'ALL AREA17 RUST INTEGRATION TESTS PASSED' 'ALL AREA17 LUA INTEGRATION TESTS PASSED'
    vf_config
    vf_run_headless "$seconds"
    vf_save_logs

    vf_note 'Area 17 headless run finished'
    printf 'Rust integration assertions passed: %s\n' "$(vf_count '\[Area17-Rust-Test\] ASSERTION PASSED')"
    printf 'Lua gameplay assertions passed:    %s\n' "$(vf_count '\[Area17-Lua-Test\] ASSERTION PASSED')"
    vf_summary

    vf_require 'ALL AREA17 RUST INTEGRATION TESTS PASSED' 'the Rust suite did not complete'
    vf_require 'ALL AREA17 LUA INTEGRATION TESTS PASSED' 'the Lua suite did not complete'
    echo '>>> Area 17 headless verification passed <<<'
}

area17_visual() {
    local seconds=${1:-60} shots before after changed

    vf_workspace area17-visual stable
    area17_stage e2e
    vf_start_file "$START_FILE"
    vf_modoption visual_test 1
    vf_config "$VISUAL_CONFIG"
    vf_graphics area17
    vf_run_visual "$seconds"
    vf_save_logs

    [[ $VF_ENGINE_STATUS -eq 0 || $VF_ENGINE_STATUS -eq 124 ]] ||
        vf_die "engine exited with status $VF_ENGINE_STATUS"

    shots=$(vf_require_screenshots 3)

    before="$VF_OUT_DIR/crater-before.png"
    after="$VF_OUT_DIR/crater-after.png"
    convert "$(vf_screenshots | head -n 1)" -crop 360x360+460+100 +repage "$before"
    convert "$(vf_screenshots | tail -n 1)" -crop 360x360+460+100 +repage "$after"
    changed=$(compare -metric AE -fuzz 8% "$before" "$after" null: 2>&1 || true)
    [[ $changed =~ ^[0-9]+$ ]] || vf_die "crater comparison produced no pixel count: $changed"
    (( changed >= 1500 )) || vf_die "rendered crater assertion failed (changed pixels: $changed)"

    vf_require '\[Area17-Visual-Test\] Captured visual smoke-test screenshots' \
        'the visual smoke-test scenario did not complete'
    vf_require 'Area 17 RmlUi HUD render pass reached' \
        'the RmlUi render pass was never reached'
    vf_require 'Area 17 RmlUi callback: cheat resources' \
        'the RmlUi Cheat Resources callback never dispatched'
    vf_require 'Area 17 RmlUi callback: technology toggle' \
        'the RmlUi Technology callback never dispatched'
    vf_require 'SDL/RmlUi input integration passed: four weapons fired and four abilities activated' \
        'SDL/RmlUi input was not verified through engine gameplay'
    vf_forbid 'Wasm.*(trap|error|Error)|CallIn.*(error|Error)|panic|ASSERTION FAILED' \
        'the visual run contains a runtime failure'

    vf_note 'Area 17 goldens'
    vf_goldens_by_index area17 frame_020 frame_080 frame_450
    vf_goldens_done

    printf 'crater changed pixels: %s\n' "$changed"
    printf 'captured %s screenshot(s) in %s\n' "$shots" "$(vf_collect_screenshots)"
    echo '>>> Area 17 visual verification passed <<<'
}

case "${1:-}" in
    static) area17_static ;;
    headless) area17_headless "${2:-}" ;;
    visual) area17_visual "${2:-}" ;;
    all) area17_static; area17_headless; area17_visual ;;
    *) vf_die 'usage: area17.sh [static|headless|visual|all] [seconds]' ;;
esac
