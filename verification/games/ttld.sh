#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

GAME_DIR="$GAMES_DIR/ToTheLastDrop-wasm.sdd"
SOURCE_ROOT="$GAME_DIR/wasm-src"
MAP_DIR="$MAPS_DIR/LD43-map.sdd"
MAP_NAME='Eyam'
GAME_NAME='To the Last Drop WASM 0.1.0-wasm'
TEST_MARKER='ALL TO THE LAST DROP INTEGRATION TESTS PASSED'

ttld_assets() {
    local asset
    for asset in \
        "$GAME_DIR/LuaUI/wasm/ttld.rml" \
        "$GAME_DIR/LuaUI/wasm/ttld.rcss" \
        "$GAME_DIR/GameData/weapondefs_post.lua" \
        "$GAME_DIR/effects/nothing.lua" \
        "$GAME_DIR/Bitmaps/GPL/flame.png" \
        "$GAME_DIR/LuaRules/Gadgets/api_unit_script_support.lua" \
        "$MAP_DIR/mapinfo.lua"; do
        [[ -f $asset ]] || vf_die "required asset is missing: $asset"
    done
    [[ ! -e "$MAP_DIR/shaders" ]] ||
        vf_die "map still overrides the engine SMF shaders: $MAP_DIR/shaders"
}

ttld_start() {
    vf_start_inline <<EOS
[GAME]
{
[team0] { startposx=5580; startposz=7100; allyteam=0; teamleader=0; }
[team1] { startposx=5650; startposz=2700; allyteam=1; teamleader=0; }
[team2] { startposx=5650; startposz=2700; allyteam=2; teamleader=0; }
[allyteam0] { numallies=0; }
[allyteam1] { numallies=0; }
[allyteam2] { numallies=0; }
[player0] { team=0; spectator=0; name=wasm-test; }
minspeed=100; maxspeed=100; ishost=1; hostip=127.0.0.1; gamemode=0; numteams=3; numusers=1; numplayers=1; myplayernum=0; myplayername=wasm-test; hostport=8452; startpostype=0; gamestartdelay=0;
gametype=$GAME_NAME; mapname=$MAP_NAME;
}
EOS
}

ttld_install() {
    (
        cd "$SOURCE_ROOT"
        cp target/wasm32-unknown-unknown/release/ttld_rules_wasm.wasm "$GAME_DIR/LuaRules/wasm/ttld-rules.wasm"
        cp target/wasm32-unknown-unknown/release/ttld_ui_wasm.wasm "$GAME_DIR/LuaUI/wasm/ttld-ui.wasm"
    )
}

ttld_headless() {
    local seconds=${1:-45}
    trap 'vf_restore_modules "$SOURCE_ROOT"; vf_keep_workspace_unless' EXIT INT TERM

    ttld_assets
    vf_build "$SOURCE_ROOT" headless-integration
    ttld_install

    vf_workspace ttld-headless
    vf_link_game "$GAME_DIR"
    vf_link_map "$MAP_DIR"
    ttld_start
    vf_config
    vf_run_headless "$seconds"
    vf_save_logs

    vf_require "$TEST_MARKER" 'the headless integration assertions did not pass'
    vf_forbid 'world state re-entered' 'the synced module re-entered its world state'
    vf_forbid 'Wasm.*(trap|error|Error)|CallIn.*(error|Error)|panic|LuaUnitScript.*error' \
        'the run contains a runtime failure'
    vf_forbid 'Unknown tag "(new|clone|append)"|really low power|table for CEG .* invalid|Failed to load icon|excess char' \
        'the game data still produces engine warnings'

    grep -- '\[TTLD-Rust-Test\]' "$VF_OUT_DIR/last.combined.txt" || true
    echo '>>> To the Last Drop headless verification passed <<<'
}

ttld_visual() {
    local seconds=${1:-60} shots
    trap 'vf_restore_modules "$SOURCE_ROOT"' EXIT INT TERM

    ttld_assets
    vf_build "$SOURCE_ROOT" e2e
    ttld_install

    vf_workspace ttld-visual stable
    vf_link_game "$GAME_DIR"
    vf_link_map "$MAP_DIR"
    ttld_start
    vf_config "$VISUAL_CONFIG"
    vf_run_visual "$seconds"
    vf_save_logs

    shots=$(vf_require_screenshots 3)
    vf_forbid 'GLSL-PO::Validate\] program-object name: SMFShader' \
        'the map SMF shader still fails to validate; terrain will not render'
    printf 'captured %s screenshot(s) in %s\n' "$shots" "$(vf_collect_screenshots)"
    echo '>>> To the Last Drop visual verification passed <<<'
}

case "${1:-headless}" in
    headless) ttld_headless "${2:-}" ;;
    visual) ttld_visual "${2:-}" ;;
    *) vf_die 'usage: ttld.sh [headless|visual] [seconds]' ;;
esac
