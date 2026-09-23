#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

GAME_DIR="$GAMES_DIR/PartsNeeded-wasm.sdd"
LUA_GAME_DIR="$GAMES_DIR/PartsNeeded.sdd"
SOURCE_ROOT="$GAME_DIR/wasm-src"
MAP_DIR="$MAPS_DIR/LD35-map.sdd"
MAP_NAME='LD35 map 0.1'
GAME_NAME='Parts Needed WASM 0.1.0-wasm'
LUA_GAME_NAME='Parts Needed $VERSION'
TEST_MARKER='ALL PARTS NEEDED INTEGRATION TESTS PASSED'
ENDING_TEST_MARKER='PARTS NEEDED ENDING INTEGRATION TEST PASSED'

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

partsneeded_start() {
    local game=${1:?game name}
    vf_start_inline <<EOS
[GAME]
{
[team0] { startposx=2000; startposz=2000; allyteam=0; teamleader=0; }
[allyteam0] { numallies=0; }
[player0] { team=0; spectator=0; name=wasm-test; }
[modoptions] { gamemode=play; }
minspeed=100; maxspeed=100; ishost=1; hostip=127.0.0.1; gamemode=0; numteams=1; numusers=1; numplayers=1; myplayernum=0; myplayername=wasm-test; hostport=8452; startpostype=0; gamestartdelay=0;
gametype=$game; mapname=$MAP_NAME;
}
EOS
}

partsneeded_install() {
    (
        cd "$SOURCE_ROOT"
        cp target/wasm32-unknown-unknown/release/partsneeded_rules_wasm.wasm "$GAME_DIR/LuaRules/wasm/partsneeded-rules.wasm"
        cp target/wasm32-unknown-unknown/release/partsneeded_ui_wasm.wasm "$GAME_DIR/LuaUI/wasm/partsneeded-ui.wasm"
    )
}

partsneeded_headless() {
    local seconds=${1:-120}
    trap 'vf_restore_modules "$SOURCE_ROOT"; vf_keep_workspace_unless' EXIT INT TERM

    partsneeded_assets
    vf_build "$SOURCE_ROOT" headless-integration
    partsneeded_install

    vf_workspace partsneeded-headless
    vf_link_game "$GAME_DIR"
    vf_link_map "$MAP_DIR"
    partsneeded_start "$GAME_NAME"
    vf_config
    vf_run_headless "$seconds"
    vf_save_logs

    vf_require "$TEST_MARKER" 'the headless integration assertions did not pass'
    vf_require "$ENDING_TEST_MARKER" 'the type-1 ending integration assertions did not pass'
    vf_forbid 'ASSERTION FAILED' 'an integration assertion failed'
    vf_forbid 'Wasm.*(trap|error|Error)|CallIn.*(error|Error)|panic|LuaUnitScript.*error' \
        'the run contains a runtime failure'
    vf_forbid 'Unknown tag "(new|clone|append)"|really low power|table for CEG .* invalid|excess char' \
        'the game data still produces engine warnings'

    grep -- '\[PartsNeeded-Rust-Test\]' "$VF_OUT_DIR/last.combined.txt" || true
    echo '>>> Parts Needed headless verification passed <<<'
}

case "${1:-headless}" in
    headless) partsneeded_headless "${2:-}" ;;
    *) vf_die 'usage: partsneeded.sh [headless] [seconds]' ;;
esac
