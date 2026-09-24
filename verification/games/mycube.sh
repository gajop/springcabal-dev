#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

# Golden RMSE limit, about twice the run-to-run noise measured on 2026-09-23 (4.2%).
GOLDEN_TOLERANCE=${GOLDEN_TOLERANCE:-9}

GAME_DIR="$GAMES_DIR/MyCube-wasm.sdd"
SOURCE_ROOT="$GAME_DIR/wasm-src"
MAP_DIR="$MAPS_DIR/MyCube_v1-wasm.sdd"
MAP_NAME='MyCube v1 WASM'
GAME_NAME='MyCube WASM 0.1.0-wasm'
LUA_GAME_DIR="$GAMES_DIR/MyCube.sdd"
LUA_MAP_DIR="$MAPS_DIR/MyCube_v1.sd7"
LUA_GAME_NAME='Ludum Dare 42 Git'
LUA_MAP_NAME='MyCube'
MODULES=(
    mycube_rules_wasm:LuaRules/wasm/mycube-rules.wasm
    mycube_ui_wasm:LuaUI/wasm/mycube-ui.wasm
)

mycube_start() {
    local game=${1:?game} map=${2:?map}
    vf_start_inline <<EOS
[GAME]
{
[team0] { startposx=4096; startposz=4096; allyteam=0; teamleader=0; }
[allyteam0] { numallies=0; }
[player0] { team=0; spectator=0; name=test; }
minspeed=100; maxspeed=100; ishost=1; hostip=127.0.0.1; gamemode=0; numteams=1; numusers=1; numplayers=1; myplayernum=0; myplayername=test; hostport=8452; startpostype=0; gamestartdelay=0;
gametype=$game; mapname=$map;
}
EOS
    # The rules draw from the engine's synced RNG; pin it so runs repeat.
    vf_start_set FixedRNGSeed 1
}

mycube_stage() {
    local features=$1 staged
    vf_build "$SOURCE_ROOT" "$features"
    staged=$(vf_stage_game "$GAME_DIR")
    vf_install_modules "$staged" "${MODULES[@]}"
    vf_link_map "$MAP_DIR"
    mycube_start "$GAME_NAME" "$MAP_NAME"
}

mycube_headless() {
    # The integration suite finishes at frame 1036 (~37s headless).
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
    vf_forbid 'Wasm.*(trap|error|Error)|CallIn.*(error|Error)|panic' \
        'the MyCube headless run contains a runtime failure'
    echo '>>> MyCube headless verification passed <<<'
}

mycube_visual() {
    local seconds=${1:-75} shots

    # The integration feature fast-forwards the story to exercise every branch;
    # keep its synthetic victory out of the screenshots.
    vf_workspace mycube-visual stable
    mycube_stage e2e
    vf_config "$VISUAL_CONFIG"
    vf_run_visual "$seconds"
    vf_save_logs
    vf_require_exit_or_timeout
    shots=$(vf_require_screenshots 5)
    vf_require 'MYCUBE VISUAL E2E PASSED' 'MyCube did not reach its visual test marker'
    vf_forbid 'Wasm.*(trap|error|Error)|CallIn.*(error|Error)|panic|ASSERTION FAILED' \
        'the MyCube visual run contains a runtime failure'

    vf_note 'MyCube goldens'
    vf_goldens_by_index mycube shot_1 shot_2 shot_3 shot_4 shot_5
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
    mycube_start "$LUA_GAME_NAME" "$LUA_MAP_NAME"
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
