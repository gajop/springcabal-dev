#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

# Golden RMSE limit.  Every step and capture runs paused on its frame, so the
# scene is the same each run; particles and time-driven shaders still drift
# 0.3-3.8% between runs (2026-09-25).
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
    # The Lua observer and the visual scenario's camera; test-only.
    cp "$FIXTURES_DIR/area17/scenario.lua" "$staged/LuaRules/Gadgets/test_area17_scenario.lua"
    vf_link_map "$("$PROJECT_ROOT/scripts/area17-map.sh" --dir)"
}

# Build hygiene: fmt, clippy, the installed modules match a fresh build of
# the source (vf_installed_matches_source), and no unsafe or ABI-packing code.
area17_static() {
    VF_OUT_DIR="$VERIFICATION_ROOT/out/area17-static"
    mkdir -p "$VF_OUT_DIR"
    vf_installed_matches_source "$GAME_DIR"

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
    vf_start_file "$START_FILE"
    vf_modoption test_mode 1
    vf_quit_when 'ALL AREA17 RUST INTEGRATION TESTS PASSED' 'ALL AREA17 LUA INTEGRATION TESTS PASSED'
    vf_config
    vf_run_headless "$seconds"
    vf_save_logs
    vf_require_clean_exit

    vf_note 'Area 17 headless run finished'
    printf 'Rust integration assertions passed: %s\n' "$(vf_count '\[Area17-Rust-Test\] ASSERTION PASSED')"
    printf 'Lua gameplay assertions passed:    %s\n' "$(vf_count '\[Area17-Lua-Test\] ASSERTION PASSED')"
    vf_summary

    vf_require 'ALL AREA17 RUST INTEGRATION TESTS PASSED' 'the Rust suite did not complete'
    vf_require 'ALL AREA17 LUA INTEGRATION TESTS PASSED' 'the Lua suite did not complete'
    vf_forbid 'ASSERTION FAILED' 'one or more in-game assertions failed'
    vf_forbid_runtime_failures
    echo '>>> Area 17 headless verification passed <<<'
}

area17_visual() {
    local seconds=${1:-60} shots before after changed

    vf_workspace area17-visual stable
    area17_stage e2e
    vf_start_file "$START_FILE"
    vf_modoption visual_test 1
    # Particle effects draw from the engine's unsynced RNG.
    vf_start_set FixedUnsyncedRNGSeed 1
    vf_config "$VISUAL_CONFIG"
    vf_graphics area17
    vf_run_visual "$seconds"
    vf_save_logs
    # The scenario gadget quits after its last capture.
    vf_require_clean_exit

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
    vf_require 'Area 17 test resources granted' \
        "the rules never received the e2e test's resources request"
    vf_require 'Area 17 RmlUi callback: technology toggle' \
        'clicking the technology button never reached its RmlUi callback'
    vf_require 'UI input reached the rules through the engine: four weapons fired, four abilities requested' \
        "the UI's weapon and ability input did not reach the rules"
    vf_forbid 'ASSERTION FAILED' 'an in-game assertion failed'
    vf_forbid_runtime_failures 'the visual run'
    vf_forbid 'missed the pause' 'a step or capture ran after its paused frame'

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
