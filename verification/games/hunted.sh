#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

# Golden RMSE limit, about twice the run-to-run noise measured on 2026-09-23 (5.2%).
GOLDEN_TOLERANCE=${GOLDEN_TOLERANCE:-10}

GAME_DIR="$GAMES_DIR/Hunted-wasm.sdd"
SOURCE_ROOT="$GAME_DIR/wasm-src"
MAP_DIR="$MAPS_DIR/HuntedMap.sdd"
START_FILE="$(vf_launch_script hunted)"
MODULES=(
    hunted_rules_wasm:LuaRules/wasm/hunted-rules.wasm
    hunted_ui_wasm:LuaUI/wasm/hunted-ui.wasm
)

hunted_headless() {
    local seconds=${1:-50} asset waves
    vf_cleanup_on_exit

    for asset in \
        "$GAME_DIR/LuaUI/sounds/Zeus_vs_Bunnies.ogg" \
        "$GAME_DIR/sounds/killstreak.ogg" \
        "$GAME_DIR/sounds/ultrakill.ogg" \
        "$GAME_DIR/sounds/monsterkill.ogg" \
        "$GAME_DIR/sounds/godlike.ogg"; do
        [[ -f $asset ]] || vf_die "required sound asset is missing: $asset"
    done

    vf_workspace hunted-headless
    vf_link_game "$GAME_DIR"
    vf_link_map "$MAP_DIR" 'Hunted - v04.sdd'
    vf_start_file "$START_FILE"
    vf_quit_when 'static carrots, burrows, and lighthouses spawned' \
        'rabbit wave started:' 'rabbit wave started:' \
        'rabbit finished eating and is carrying a carrot' 'status sent frame='
    vf_config
    vf_run_headless "$seconds"
    vf_save_logs

    [[ -s "$VF_OUT_DIR/last.infolog.txt" ]] || vf_die 'the headless run produced no infolog'
    [[ $VF_ENGINE_STATUS -eq 0 || $VF_ENGINE_STATUS -eq 124 ]] ||
        vf_die "engine exited unexpectedly with status $VF_ENGINE_STATUS"

    vf_require 'static carrots, burrows, and lighthouses spawned' 'static content never spawned'
    vf_require 'rabbit wave started:' 'no rabbit wave started'
    vf_require 'rabbit motion frame=.*moving=[1-9]' 'rabbits never moved'
    vf_require 'rabbit finished eating and is carrying a carrot' 'rabbits never ate a carrot'
    vf_require 'status sent frame=' 'synced status never reached the UI boundary'
    vf_forbid 'AddressSanitizer|Segmentation fault|Wasm trap|fatal error|Lua.*error' \
        'the run contains a runtime failure'

    waves=$(vf_count 'rabbit wave started:')
    [[ ${waves:-0} -ge 2 ]] || vf_die "expected at least two rabbit waves, observed ${waves:-0}"

    vf_summary
    printf 'rabbit waves: %s\n' "$waves"
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
    vf_config "$VISUAL_CONFIG"
    vf_graphics hunted
    vf_run_visual "$seconds"
    vf_save_logs

    [[ $VF_ENGINE_STATUS -eq 0 || $VF_ENGINE_STATUS -eq 124 ]] ||
        vf_die "Hunted visual E2E engine exited with $VF_ENGINE_STATUS"
    shots=$(vf_require_screenshots 3)

    # The UI world is skipped in headless, so these are the only checks that
    # exercise the Rust widgets at all: the HUD, the flashlight volume and the
    # rabbit-visibility pass all run only under a real renderer.
    vf_require 'rabbit wave started:' 'no rabbit wave started in the visual run'
    vf_forbid 'Wasm.*(trap|error|Error)|CallIn.*(error|Error)|panic' \
        'the Hunted visual run contains a runtime failure'

    vf_note 'Hunted goldens'
    vf_goldens_by_index hunted shot_1 shot_2 shot_3
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
