#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

# Golden RMSE limit.  Run-to-run drift has not been measured for this suite;
# 8% matches the other scenario suites (see verification/README.md).
GOLDEN_TOLERANCE=${GOLDEN_TOLERANCE:-8}

GAME_DIR="$GAMES_DIR/PartsNeeded-wasm.sdd"
LUA_GAME_DIR="$GAMES_DIR/PartsNeeded.sdd"
SOURCE_ROOT="$GAME_DIR/wasm-src"
MAP_DIR="$MAPS_DIR/LD35-map.sdd"
MAP_NAME='LD35 map 0.1'
GAME_NAME='Parts Needed WASM 0.1.0-wasm'
TEST_MARKER='ALL PARTS NEEDED INTEGRATION TESTS PASSED'
ENDING_TEST_MARKER='PARTS NEEDED ENDING INTEGRATION TEST PASSED'
MODULES=(
    partsneeded_rules_wasm:LuaRules/wasm/partsneeded-rules.wasm
    partsneeded_ui_wasm:LuaUI/wasm/partsneeded-ui.wasm
)

partsneeded_assets() {
    local asset
    for asset in \
        "$GAME_DIR/LuaRules/Gadgets/unit_script.lua" \
        "$GAME_DIR/LuaRules/draw.lua" \
        "$GAME_DIR/LuaUI/images/ground/s_ok.png" \
        "$GAME_DIR/LuaUI/images/ground/b_ok.png" \
        "$LUA_GAME_DIR/Scripts/wisp.lua" \
        "$MAP_DIR/mapinfo.lua"; do
        [[ -f $asset ]] || vf_die "required asset is missing: $asset"
    done
}

partsneeded_stage() {
    local features=$1 staged
    partsneeded_assets
    vf_build "$SOURCE_ROOT" "$features"
    staged=$(vf_stage_game "$GAME_DIR")
    vf_install_modules "$staged" "${MODULES[@]}"
    vf_link_map "$MAP_DIR"
    vf_start_inline <<EOS
[GAME]
{
[team0] { startposx=2000; startposz=2000; allyteam=0; teamleader=0; }
[allyteam0] { numallies=0; }
[player0] { team=0; spectator=0; name=wasm-test; }
[modoptions] { gamemode=play; }
minspeed=100; maxspeed=100; ishost=1; hostip=127.0.0.1; gamemode=0; numteams=1; numusers=1; numplayers=1; myplayernum=0; myplayername=wasm-test; hostport=8452; startpostype=0; gamestartdelay=0;
gametype=$GAME_NAME; mapname=$MAP_NAME;
}
EOS
}

partsneeded_headless() {
    local seconds=${1:-120}
    vf_cleanup_on_exit

    vf_workspace partsneeded-headless
    partsneeded_stage headless-integration
    vf_quit_when "$TEST_MARKER" "$ENDING_TEST_MARKER"
    vf_config
    vf_run_headless "$seconds"
    vf_save_logs
    vf_require_clean_exit

    vf_require "$TEST_MARKER" 'the headless integration assertions did not pass'
    vf_require "$ENDING_TEST_MARKER" 'the type-1 ending integration assertions did not pass'
    vf_forbid 'ASSERTION FAILED' 'an integration assertion failed'
    vf_forbid 'Wasm.*(trap|error|Error)|CallIn.*(error|Error)|panic|LuaUnitScript.*error' \
        'the run contains a runtime failure'
    vf_forbid 'Unknown tag "(new|clone|append)"|really low power|table for CEG .* invalid|excess char' \
        'the game data still produces engine warnings'

    grep -- '\[PartsNeeded-Rust-Test\]' "$(vf_count_log)" || true
    echo '>>> Parts Needed headless verification passed <<<'
}

partsneeded_visual() {
    local seconds=${1:-75} shots

    vf_workspace partsneeded-visual stable
    partsneeded_stage e2e,headless-integration
    vf_config "$VISUAL_CONFIG"
    vf_run_visual "$seconds"
    vf_save_logs
    vf_require_exit_or_timeout
    shots=$(vf_require_screenshots 3)
    vf_require "$TEST_MARKER" 'Parts Needed did not reach its test marker'
    vf_require "$ENDING_TEST_MARKER" 'Parts Needed did not reach its ending test marker'
    vf_forbid 'Wasm.*(trap|error|Error)|CallIn.*(error|Error)|panic|ASSERTION FAILED' \
        'the Parts Needed visual run contains a runtime failure'

    vf_note 'Parts Needed goldens'
    vf_goldens_by_index partsneeded shot_1 shot_2 shot_3
    vf_goldens_done
    printf 'Parts Needed visual E2E passed: %s screenshot(s) in %s\n' "$shots" "$(vf_collect_screenshots)"
}

case "${1:-}" in
    headless) partsneeded_headless "${2:-}" ;;
    visual) partsneeded_visual "${2:-}" ;;
    *) vf_die 'usage: partsneeded.sh [headless|visual] [seconds]' ;;
esac
