#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

GAME_DIR="$GAMES_DIR/MyCube.sdd"
MAP_DIR="$MAPS_DIR/MyCube_v1.sd7"
GAME_NAME='Ludum Dare 42 Git'
MAP_NAME='MyCube'

mycube_assets() {
    local asset
    for asset in \
        "$GAME_DIR/ModInfo.lua" \
        "$GAME_DIR/LuaRules/Gadgets/api_custom_unit_shaders.lua" \
        "$GAME_DIR/LuaUI/Widgets/ui_endgame.lua" \
        "$MAP_DIR"; do
        [[ -e $asset ]] || vf_die "required asset is missing: $asset"
    done
    grep -qF 'name = "Ludum Dare 42"' "$GAME_DIR/ModInfo.lua" ||
        vf_die "unexpected My Cube Lua title base"
    grep -qF 'version = "Git"' "$GAME_DIR/ModInfo.lua" ||
        vf_die "unexpected My Cube Lua version"
}

mycube_start() {
    vf_start_inline <<EOS
[GAME]
{
[team0] { startposx=4096; startposz=4096; allyteam=0; teamleader=0; }
[allyteam0] { numallies=0; }
[player0] { team=0; spectator=0; name=lua-test; }
minspeed=100; maxspeed=100; ishost=1; hostip=127.0.0.1; gamemode=0; numteams=1; numusers=1; numplayers=1; myplayernum=0; myplayername=lua-test; hostport=8452; startpostype=0; gamestartdelay=0;
gametype=$GAME_NAME; mapname=$MAP_NAME;
}
EOS
}

mycube_headless() {
    local seconds=${1:-20}

    trap 'vf_keep_workspace_unless' EXIT INT TERM

    mycube_assets
    vf_workspace mycube-headless
    vf_link_game "$GAME_DIR"
    vf_link_map "$MAP_DIR"
    mycube_start
    vf_config
    vf_run_headless "$seconds"
    vf_save_logs
    vf_summary

    # The headless renderer has no usable GL texture limit, so the engine
    # reports the groundFX atlas allocation once during startup. Ignore only
    # that renderer limitation; every other engine error is a game failure.
    local unexpected_errors
    unexpected_errors=$(grep -E 'Error:' "$VF_OUT_DIR/last.combined.txt" |
        grep -vF 'Could not finalize groundFX texture atlas' || true)
    if [[ -n $unexpected_errors ]]; then
        printf '%s\n' "$unexpected_errors" >&2
        vf_die 'the My Cube Lua archive still has an unexpected engine error'
    fi

    vf_forbid 'Fatal:|Bad return table|Unknown tag "(new|clone|append)"|really low power|table for CEG .* invalid|Failed to load:|attempt to (call|compare|concatenate)|RunCallInTraceback|Removed widget' \
        'the My Cube Lua archive still has a startup or runtime failure'

    echo '>>> My Cube Lua headless verification passed <<<'
}

case "${1:-headless}" in
    headless) mycube_headless "${2:-}" ;;
    *) vf_die 'usage: mycube.sh [headless] [seconds]' ;;
esac
