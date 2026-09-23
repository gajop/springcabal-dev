#!/usr/bin/env bash
# Smoke-test an assembled Linux bundle: every menu entry must load into a
# game under spring-headless and still be running at the timeout (no crash),
# and the menu must boot under xvfb.  Frame counts are informational: several
# games start paused or log nothing once running.
#
# Usage: release/smoke-test.sh release/out/SpringCabal-<ver>-linux [seconds]
set -uo pipefail

bundle="$(cd "${1:?bundle directory}" && pwd)"
seconds="${2:-45}"
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
menu_src="$project_root/wasm-menu/wasm-src/menu/src/lib.rs"
work="$(mktemp -d "${TMPDIR:-/tmp}/springcabal-smoke.XXXXXX")"

[[ -x "$bundle/spring-headless" ]] || { echo "no spring-headless in $bundle" >&2; exit 1; }

# (game_type, map_name) pairs straight from the menu's tables, so the test
# launches exactly what the menu would.
mapfile -t entries < <(
    grep -E '^\s*(game_type|map_name): "' "$menu_src" \
        | sed -E 's/.*"(.*)".*/\1/' | paste - -
)

mod_options() {
    case "$1" in
        "Area 17"*) printf 'DisableMapDamage=0;' ;;
        "Parts Needed"*) printf 'gamemode=play;' ;;
        "Scenario Editor Gravitas"*)
            printf 'play_mode=1;deathmode=neverend;has_scenario_file=0;project_dir=projects/Gravity-Enterprise;' ;;
    esac
}

start_script() {
    # Mirrors format_start_script() in the menu.
    local game_type="$1" map="$2" player_team=0 ai_team=1
    [[ "$game_type" == Flove* ]] && { player_team=1; ai_team=0; }
    cat <<EOF
[GAME]
{
    MapName=$map;
    GameMode=0;
    GameType=$game_type;
    NumTeams=2;
    NumUsers=2;
    HostIP=127.0.0.1;
    HostPort=$(shuf -i 20000-60000 -n 1);
    IsHost=1;
    NumPlayers=1;
    GameStartDelay=0;
    StartposType=3;
    MyPlayerNum=1;
    MyPlayerName=0;
    NumRestrictions=0;
    MaxSpeed=20;
    MinSpeed=0.1;
    [TEAM0] { AllyTeam=0; Side=; TeamLeader=1; Handicap=0; StartPosX=0; StartPosZ=0; }
    [PLAYER1] { Name=0; Spectator=0; Team=$player_team; }
    [TEAM1] { AllyTeam=1; Side=; TeamLeader=1; Handicap=0; StartPosX=0; StartPosZ=0; }
    [AI1] { Name=1: NullAI; ShortName=NullAI; Team=$ai_team; IsFromDemo=0; Host=1; [Options] {} }
    [ALLYTEAM0] { NumAllies=0; }
    [ALLYTEAM1] { NumAllies=0; }
    [MODOPTIONS] { $(mod_options "$game_type") }
}
EOF
}

failures=0
printf '%-36s %-10s %-8s %s\n' GAME RESULT FRAMES ERRORS
for entry in "${entries[@]}"; do
    game_type="${entry%%$'\t'*}"
    map="${entry#*$'\t'}"
    slug="$(echo "$game_type" | tr -c 'A-Za-z0-9\n' '_')"
    run="$work/$slug"
    mkdir -p "$run"
    start_script "$game_type" "$map" > "$run/start.txt"
    printf 'snd_volmaster = 0\n' > "$run/spring.conf"

    timeout --signal=TERM "${seconds}s" "$bundle/spring-headless" \
        --isolation --isolation-dir "$bundle" --write-dir "$run" \
        --config "$run/spring.conf" "$run/start.txt" > "$run/stdout.txt" 2>&1
    status=$?

    # infolog.txt is only flushed on a clean exit; stdout has the same log.
    log="$run/stdout.txt"
    last_frame="$(grep -oE '\[f=[0-9]+\]' "$log" | tail -1 | tr -dc '0-9' | sed 's/^0*//')"
    errors="$(grep -cE '\bError:' "$log")"
    if grep -q "finished loading and is now ingame" "$log" && (( status == 124 )) \
        && ! grep -qE 'Segmentation fault|\[Fatal\]|wasm trap|panicked at' "$log"; then
        result=ok
    else
        result="FAIL($status)"
        failures=$((failures + 1))
    fi
    printf '%-36s %-10s %-8s %s\n' "$game_type" "$result" "${last_frame:-0}" "${errors:-0}"
done

# Menu boot under a virtual display (software GL).
if command -v xvfb-run >/dev/null; then
    run="$work/menu"
    mkdir -p "$run"
    printf 'snd_volmaster = 0\n' > "$run/spring.conf"
    LIBGL_ALWAYS_SOFTWARE=1 SDL_VIDEODRIVER=x11 WAYLAND_DISPLAY= \
        timeout --signal=TERM 90s xvfb-run -a -s '-screen 0 1280x900x24 +extension GLX' \
        "$bundle/spring" --window --isolation --isolation-dir "$bundle" --write-dir "$run" \
        --config "$run/spring.conf" -menu "WasmMenu 1.0" > "$run/stdout.txt" 2>&1
    errors="$(grep -cE '\bError:' "$run/stdout.txt")"
    if grep -q 'Wasm manifest loaded from WasmMenu/manifest.json' "$run/stdout.txt" \
        && ! grep -qE 'Segmentation fault|\[Fatal\]|wasm trap|panicked at' "$run/stdout.txt"; then
        printf '%-36s %-10s %-8s %s\n' "WasmMenu (xvfb)" ok - "${errors:-0}"
    else
        printf '%-36s %-10s %-8s %s\n' "WasmMenu (xvfb)" FAIL - "${errors:-0}"
        failures=$((failures + 1))
    fi
fi

echo ""
echo "Logs: $work"
exit $(( failures > 0 ))
