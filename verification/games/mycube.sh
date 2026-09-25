#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

# Golden RMSE limit, about twice the run-to-run noise measured on 2026-09-23 (4.2%).
GOLDEN_TOLERANCE=${GOLDEN_TOLERANCE:-9}

GAME_DIR="$GAMES_DIR/MyCube-wasm.sdd"
SOURCE_ROOT="$GAME_DIR/wasm-src"
MAP_DIR="$MAPS_DIR/MyCube_v1-wasm.sdd"
LUA_GAME_DIR="$GAMES_DIR/MyCube.sdd"
LUA_MAP_DIR="$MAPS_DIR/MyCube_v1.sd7"
MODULES=(
    mycube_rules_wasm:LuaRules/wasm/mycube-rules.wasm
    mycube_ui_wasm:LuaUI/wasm/mycube-ui.wasm
)

# mycube_start wasm|lua: the start script the menu uses for that version.
mycube_start() {
    vf_start_file "$(vf_launch_script mycube "${1:?wasm or lua}")"
    # The rules draw from the engine's synced RNG; pin it so runs repeat.
    vf_start_set FixedRNGSeed 1
}

mycube_stage() {
    local features=$1 staged
    vf_build "$SOURCE_ROOT" "$features"
    staged=$(vf_stage_game "$GAME_DIR")
    vf_install_modules "$staged" "${MODULES[@]}"
    vf_link_map "$MAP_DIR"
    mycube_start wasm
}

mycube_headless() {
    # The integration suite finishes around frame 1100, a few seconds in at
    # 100x. Its checks wait for the UI's messages, whose round trip takes more
    # frames the faster the game runs.
    local seconds=${1:-60}
    vf_cleanup_on_exit

    vf_workspace mycube-headless
    mycube_stage headless-integration
    vf_quit_when 'ALL MYCUBE INTEGRATION TESTS PASSED'
    vf_config
    vf_run_headless "$seconds"
    vf_save_logs
    vf_require_clean_exit
    vf_require 'ALL MYCUBE INTEGRATION TESTS PASSED' 'MyCube did not reach its test marker'
    vf_forbid_runtime_failures 'the MyCube headless run'
    echo '>>> MyCube headless verification passed <<<'
}

# The village in a 1280x720 screenshot from the engine's start camera, which
# looks at the middle of the map from far away, through the fog (as the Lua
# game does). The crop's contrast is stretched before the comparison: in the
# raw crop the whole village is only 2% away from flat fog. Stretched, flat
# fog is 15% off, and runs differ by up to 1.8% (drill ships, craters).
VILLAGE_CROP=400x200+440+300
VILLAGE_TOLERANCE=${VILLAGE_TOLERANCE:-4}

mycube_visual() {
    # The last screenshot comes at frame 2000, about 70 s in.
    local seconds=${1:-100} shots index village

    # The integration feature fast-forwards the story to exercise every branch;
    # keep its synthetic victory out of the screenshots.
    vf_workspace mycube-visual stable
    mycube_stage e2e
    vf_quit_when 'MYCUBE VISUAL E2E PASSED'
    vf_config "$VISUAL_CONFIG"
    vf_run_visual "$seconds"
    vf_save_logs
    vf_require_clean_exit
    shots=$(vf_require_screenshots 5)
    vf_require 'MYCUBE VISUAL E2E PASSED' 'MyCube did not reach its visual test marker'
    vf_forbid 'ASSERTION FAILED' 'an in-game assertion failed'
    vf_forbid_runtime_failures 'the MyCube visual run'

    vf_note 'MyCube goldens'
    local -a images
    mapfile -t images < <(vf_screenshots)
    # The whole screen once, for the HUD; then the village at each shot.
    vf_golden mycube hud "${images[0]}"
    mkdir -p "$VF_OUT_DIR/village"
    for index in 0 1 2 3 4; do
        village="$VF_OUT_DIR/village/village_$((index + 1)).png"
        convert "${images[$index]}" -crop "$VILLAGE_CROP" +repage -normalize "$village"
        vf_golden mycube "village_$((index + 1))" "$village" "$VILLAGE_TOLERANCE"
    done
    vf_goldens_done
    printf 'MyCube visual E2E passed: %s screenshot(s) in %s\n' "$shots" "$(vf_collect_screenshots)"
}

# The original Lua game must boot on this engine without any Lua errors.
mycube_lua_headless() {
    # Frame 450 comes about 18 s in, and the exit takes another second or two.
    local seconds=${1:-45} asset unexpected_errors
    vf_cleanup_on_exit

    for asset in \
        "$LUA_GAME_DIR/ModInfo.lua" \
        "$LUA_GAME_DIR/LuaRules/Gadgets/api_custom_unit_shaders.lua" \
        "$LUA_GAME_DIR/LuaUI/Widgets/ui_endgame.lua" \
        "$LUA_MAP_DIR"; do
        [[ -e $asset ]] || vf_die "required asset is missing: $asset"
    done
    grep -qF 'name = "Ludum Dare 42"' "$LUA_GAME_DIR/ModInfo.lua" ||
        vf_die "unexpected My Cube Lua title base"
    grep -qF 'version = "Git"' "$LUA_GAME_DIR/ModInfo.lua" ||
        vf_die "unexpected My Cube Lua version"

    vf_workspace mycube-lua-headless
    vf_link_game "$LUA_GAME_DIR"
    vf_link_map "$LUA_MAP_DIR"
    mycube_start lua
    vf_quit_when --frame 450
    vf_config
    vf_run_headless "$seconds"
    vf_save_logs
    vf_require_clean_exit
    vf_summary

    # The headless renderer has no usable GL texture limit, so the engine
    # reports the groundFX atlas allocation once during startup. Ignore only
    # that renderer limitation; every other engine error is a game failure.
    unexpected_errors=$(grep -E 'Error:' "$(vf_count_log)" |
        grep -vF 'Could not finalize groundFX texture atlas' || true)
    if [[ -n $unexpected_errors ]]; then
        printf '%s\n' "$unexpected_errors" >&2
        vf_die 'the My Cube Lua archive still has an unexpected engine error'
    fi
    vf_forbid 'Fatal:|Bad return table|Unknown tag "(new|clone|append)"|really low power|table for CEG .* invalid|Failed to load:|attempt to (call|compare|concatenate)|RunCallInTraceback|Removed widget' \
        'the My Cube Lua archive still has a startup or runtime failure'
    echo '>>> My Cube Lua headless verification passed <<<'
}

case "${1:-}" in
    headless) mycube_headless "${2:-}" ;;
    visual) mycube_visual "${2:-}" ;;
    lua-headless) mycube_lua_headless "${2:-}" ;;
    *) vf_die 'usage: mycube.sh [headless|visual|lua-headless] [seconds]' ;;
esac
