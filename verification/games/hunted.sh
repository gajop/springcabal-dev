#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

# Golden RMSE limit, about twice the run-to-run noise measured on 2026-09-23 (5.2%).
GOLDEN_TOLERANCE=${GOLDEN_TOLERANCE:-10}
# The HUD crops' limit: run-to-run noise was 0.1-0.5% on 2026-09-25, and one
# changed digit in the score corner is 3.6%.
HUD_TOLERANCE=${HUD_TOLERANCE:-2}

GAME_DIR="$GAMES_DIR/Hunted-wasm.sdd"
SOURCE_ROOT="$GAME_DIR/wasm-src"
MAP_DIR="$MAPS_DIR/HuntedMap.sdd"
START_FILE="$(vf_launch_script hunted)"
TEST_MARKER='ALL HUNTED INTEGRATION TESTS PASSED'
MODULES=(
    hunted_rules_wasm:LuaRules/wasm/hunted-rules.wasm
    hunted_ui_wasm:LuaUI/wasm/hunted-ui.wasm
)

hunted_headless() {
    local seconds=${1:-60} asset staged checks
    vf_cleanup_on_exit

    for asset in \
        "$GAME_DIR/LuaUI/sounds/Zeus_vs_Bunnies.ogg" \
        "$GAME_DIR/sounds/killstreak.ogg" \
        "$GAME_DIR/sounds/ultrakill.ogg" \
        "$GAME_DIR/sounds/monsterkill.ogg" \
        "$GAME_DIR/sounds/godlike.ogg"; do
        [[ -f $asset ]] || vf_die "required sound asset is missing: $asset"
    done

    # The rules' integration gadget asserts everything; the UI's test feature
    # confirms the rules' status to it.
    vf_build "$SOURCE_ROOT" hunted-rules-wasm/headless-integration,hunted-ui-wasm/headless-integration
    vf_workspace hunted-headless
    staged=$(vf_stage_game "$GAME_DIR")
    vf_install_modules "$staged" "${MODULES[@]}"
    vf_link_map "$MAP_DIR" 'Hunted - v04.sdd'
    vf_start_file "$START_FILE"
    vf_quit_when "$TEST_MARKER"
    vf_config
    vf_run_headless "$seconds"
    vf_save_logs

    vf_require_clean_exit
    [[ -s "$VF_OUT_DIR/last.infolog.txt" ]] || vf_die 'the headless run produced no infolog'

    vf_forbid 'ASSERTION FAILED' 'one or more in-game assertions failed'
    vf_require "$TEST_MARKER" 'the integration assertions did not pass'
    vf_forbid 'fatal error|Lua.*error' 'the run logged a Lua or fatal error'
    vf_forbid_runtime_failures

    checks=$(vf_count '\[Hunted-Rust-Test\] ASSERTION PASSED')

    vf_summary
    printf 'Rust rules assertions passed: %s\n' "$checks"
    echo '>>> Hunted headless verification passed <<<'
}

hunted_visual() {
    local seconds=${1:-75} shots staged

    vf_build "$SOURCE_ROOT" e2e
    vf_workspace hunted-visual stable
    staged=$(vf_stage_game "$GAME_DIR")
    vf_install_modules "$staged" "${MODULES[@]}"
    vf_link_map "$MAP_DIR" 'Hunted - v04.sdd'
    vf_start_file "$START_FILE"
    vf_quit_when 'HUNTED VISUAL SHOTS TAKEN'
    vf_config "$VISUAL_CONFIG"
    vf_graphics hunted
    vf_run_visual "$seconds"
    vf_save_logs

    vf_require_clean_exit
    shots=$(vf_require_screenshots 5)

    # The HUD, the flashlight volume and the rabbit-visibility pass only draw
    # under a real renderer.
    vf_require 'HUNTED VISUAL SHOTS TAKEN' 'the visual run did not take its screenshots'
    vf_forbid_runtime_failures 'the Hunted visual run'
    vf_require 'HUNTED HUD BINDINGS PASSED' 'the bound event rows and restart button were not verified'

    vf_note 'Hunted goldens'
    vf_goldens_by_index hunted shot_1 shot_2 shot_3 shot_4 shot_5
    # The whole-frame limit can't see the HUD's text, so its corners and the
    # end screen are compared on their own, more tightly.
    local -a images
    mapfile -t images < <(vf_screenshots)
    vf_golden hunted hud_top "${images[3]}" "$HUD_TOLERANCE" 1280x70+0+0
    vf_golden hunted hud_score "${images[3]}" "$HUD_TOLERANCE" 160x90+1120+630
    vf_golden hunted end_screen "${images[4]}" "$HUD_TOLERANCE" 680x340+300+215
    vf_goldens_done

    vf_summary
    printf 'Hunted visual E2E passed: %s screenshot(s) in %s\n' \
        "$shots" "$(vf_collect_screenshots)"
    echo '>>> Hunted visual verification passed <<<'
}

case "${1:-}" in
    headless) hunted_headless "${2:-}" ;;
    visual) hunted_visual "${2:-}" ;;
    *) vf_die 'usage: hunted.sh [headless|visual] [seconds]' ;;
esac
