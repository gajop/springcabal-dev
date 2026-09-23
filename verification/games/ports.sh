#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

port_config() {
    ENDING_TEST_MARKER=''
    case "${1:?port}" in
        mycube)
            GAME_DIR="$GAMES_DIR/MyCube-wasm.sdd"
            MAP_DIR="$MAPS_DIR/MyCube_v1-wasm.sdd"
            MAP_NAME='MyCube v1 WASM'
            GAME_NAME='MyCube WASM 0.1.0-wasm'
            RULES=mycube_rules_wasm
            UI=mycube_ui_wasm
            TEST_MARKER='ALL MYCUBE INTEGRATION TESTS PASSED'
            VISUAL_MARKER='MYCUBE VISUAL E2E PASSED'
            ;;
        partsneeded)
            GAME_DIR="$GAMES_DIR/PartsNeeded-wasm.sdd"
            MAP_DIR="$MAPS_DIR/LD35-map.sdd"
            MAP_NAME='LD35 map 0.1'
            GAME_NAME='Parts Needed WASM 0.1.0-wasm'
            RULES=partsneeded_rules_wasm
            UI=partsneeded_ui_wasm
            TEST_MARKER='ALL PARTS NEEDED INTEGRATION TESTS PASSED'
            ENDING_TEST_MARKER='PARTS NEEDED ENDING INTEGRATION TEST PASSED'
            ;;
        *) vf_die "unknown port: $1" ;;
    esac
    SOURCE_ROOT="$GAME_DIR/wasm-src"
    RULES_ARCHIVE=${RULES%_wasm}; RULES_ARCHIVE=${RULES_ARCHIVE//_/-}
    UI_ARCHIVE=${UI%_wasm}; UI_ARCHIVE=${UI_ARCHIVE//_/-}
}

port_start() {
    vf_start_inline <<EOS
[GAME]
{
[team0] { startposx=4096; startposz=4096; allyteam=0; teamleader=0; }
[allyteam0] { numallies=0; }
[player0] { team=0; spectator=0; name=wasm-test; }
minspeed=100; maxspeed=100; ishost=1; hostip=127.0.0.1; gamemode=0; numteams=1; numusers=1; numplayers=1; myplayernum=0; myplayername=wasm-test; hostport=8452; startpostype=0; gamestartdelay=0;
gametype=$GAME_NAME; mapname=$MAP_NAME;
}
EOS
}

port_install() {
    (
        cd "$SOURCE_ROOT"
        cp "target/wasm32-unknown-unknown/release/$RULES.wasm" "$GAME_DIR/LuaRules/wasm/$RULES_ARCHIVE.wasm"
        cp "target/wasm32-unknown-unknown/release/$UI.wasm" "$GAME_DIR/LuaUI/wasm/$UI_ARCHIVE.wasm"
    )
}

port_run() {
    local key=${1:?port} mode=${2:?mode} seconds=${3:-} shots expected_marker
    port_config "$key"
    trap 'vf_restore_modules "$SOURCE_ROOT"; vf_keep_workspace_unless' EXIT INT TERM

    if [[ $mode == visual && $key == mycube ]]; then
        # The integration feature deliberately fast-forwards the authored
        # story to exercise every branch. Keep it out of screenshots: its
        # synthetic victory is a test result, not a player-visible ending.
        vf_build "$SOURCE_ROOT" e2e
    elif [[ $mode == visual ]]; then
        vf_build "$SOURCE_ROOT" e2e,headless-integration
    else
        vf_build "$SOURCE_ROOT" headless-integration
    fi
    port_install

    vf_workspace "$key-$mode" "$([[ $mode == visual ]] && echo stable || echo temp)"
    vf_link_game "$GAME_DIR"
    vf_link_map "$MAP_DIR"
    port_start

    if [[ $mode == visual ]]; then
        vf_config "$VISUAL_CONFIG"
        vf_run_visual "${seconds:-75}"
        vf_save_logs
        [[ $VF_ENGINE_STATUS -eq 0 || $VF_ENGINE_STATUS -eq 124 ]] ||
            vf_die "$key visual E2E engine exited with $VF_ENGINE_STATUS"
        shots=$(vf_require_screenshots 3)
        expected_marker=${VISUAL_MARKER:-$TEST_MARKER}
        vf_require "$expected_marker" "$key did not reach its visual test marker"
        [[ -z $ENDING_TEST_MARKER ]] ||
            vf_require "$ENDING_TEST_MARKER" "$key did not reach its ending test marker"
        vf_forbid 'Wasm.*(trap|error|Error)|CallIn.*(error|Error)|panic|ASSERTION FAILED' \
            "$key visual E2E contains a runtime failure"
        printf '%s visual E2E passed: %s screenshot(s) in %s\n' \
            "$key" "$shots" "$(vf_collect_screenshots)"
    else
        vf_config
        vf_run_headless "${seconds:-30}"
        vf_save_logs
        vf_require "$TEST_MARKER" "$key did not reach its test marker"
        vf_forbid 'Wasm.*(trap|error|Error)|CallIn.*(error|Error)|panic' \
            "$key headless run contains a runtime failure"
        printf '%s headless integration passed\n' "$key"
    fi
}

mode=${1:-headless}
game=${2:-all}
[[ $mode == headless || $mode == visual ]] ||
    vf_die 'usage: ports.sh [headless|visual] [mycube|partsneeded|all] [seconds]'

if [[ $game == all ]]; then
    (port_run mycube "$mode" "${3:-}")
    (port_run partsneeded "$mode" "${3:-}")
else
    port_run "$game" "$mode" "${3:-}"
fi
