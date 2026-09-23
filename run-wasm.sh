#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
engine_root="${SPRING_BAR_DIR:-$(dirname "$project_root")/spring-bar}"
# Engine install to run: SPRING_ENGINE_DIR, else a local spring-bar build,
# else the release fetched by `./setup.sh --engine-tag TAG` (engine/current).
engine_install="${SPRING_ENGINE_DIR:-}"
if [[ -z "$engine_install" ]]; then
    engine_install="$engine_root/build-amd64-linux/install"
    if [[ ! -x "$engine_install/spring" && -x "$project_root/engine/current/spring" ]]; then
        engine_install="$project_root/engine/current"
    fi
fi
engine_bin="$engine_install/spring"
wasm_menu_dir="$project_root/wasm-menu"
run_dir="${SPRING_RUN_DIR:-$project_root/wasm-test}"
write_dir="$run_dir/write"
log_dir="$write_dir/logs"

usage() {
    echo "Usage: $0 [--game hunted|area17|flove|ttld|gravitas]"
    echo ""
    echo "  No arguments:       launch the WASM menu (pick a game interactively)"
    echo "  --game hunted       launch Hunted WASM directly"
    echo "  --game area17       launch Area 17 WASM directly"
    echo "  --game flove        launch Flove WASM directly (bypasses the menu)"
    echo "  --game ttld         launch To the Last Drop WASM directly"
    echo "  --game gravitas     launch Gravitas WASM directly"
    exit 1
}

game=""
start_file=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --game) game="${2:-}"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1" >&2; usage ;;
    esac
done

if [[ ! -x "$engine_bin" ]]; then
    echo "Experimental engine not found: $engine_bin" >&2
    echo "Build it with: cd '$engine_root' && ./docker-build-v2/build.sh linux" >&2
    echo "or download a release with: ./setup.sh --engine-tag TAG" >&2
    exit 1
fi

# The isolation view has to keep the same path between runs.  The engine's
# archive cache in the write dir records each archive's info-file path, and a
# fresh mktemp directory every launch meant every cached entry pointed at a
# deleted /tmp path, so startup logged one
# "[FSA::GetFileModificationTime] error 'No such file or directory'" per
# archive and then rescanned all of them.  One stable directory per launch
# mode, since the modes link different archives under different names.
isolation_dir="$run_dir/isolation-${game:-menu}"
rm -rf -- "$isolation_dir/games" "$isolation_dir/maps"
mkdir -p "$isolation_dir" "$write_dir" "$log_dir"

session_log="$log_dir/wasm-$(date +%Y%m%d-%H%M%S)-$$.infolog.txt"
return_marker="(AREA17|HUNTED|FLOVE|GRAVITAS|MYCUBE|TTLD)_RETURN_TO_WASM_MENU|RETURN_TO_WASM_MENU"

cleanup() {
    if [[ -n "$start_file" ]]; then
        rm -f -- "$start_file"
    fi
    echo "Kept isolated launch view: $isolation_dir"
    if [[ -f "$write_dir/infolog.txt" ]]; then
        cp -- "$write_dir/infolog.txt" "$session_log"
        echo ""
        echo "=========================================="
        echo "===     INFOLOG DIAGNOSTIC SUMMARY     ==="
        echo "=========================================="
        local warnings_count errors_count
        warnings_count=$(grep -c -E "\bWarning:" "$write_dir/infolog.txt" || true)
        errors_count=$(grep -c -E "\bError:" "$write_dir/infolog.txt" || true)
        echo "Total Errors: $errors_count | Total Warnings: $warnings_count"
        if [[ $errors_count -gt 0 || $warnings_count -gt 0 ]]; then
            echo ""
            echo "--- Errors & Warnings List ---"
            grep -E "\b(Warning|Error):" "$write_dir/infolog.txt" || true
        else
            echo "ALL CLEAR: 0 Errors, 0 Warnings!"
        fi
        echo "=========================================="
        echo "Saved session log: $session_log"
    fi
}
trap cleanup EXIT INT TERM

launch_engine() {
    set +e
    "$@"
    local status=$?
    set -e
    # Games normally return to the menu in-process (reloadforce).  Only a game
    # that logs a return marker and then quits the process (MyCube's Ctrl+Q)
    # needs the menu relaunched, so require the marker to come after the last
    # time the menu was (re)loaded.
    if returned_by_quitting "$write_dir/infolog.txt"; then
        echo "Game requested a return to the WASM menu."
        exec "$project_root/run-wasm.sh"
    fi
    return "$status"
}

returned_by_quitting() {
    local log=$1 marker_line menu_line
    [[ -f $log ]] || return 1
    marker_line=$(grep -n -E "$return_marker" "$log" | tail -1 | cut -d: -f1)
    [[ -n $marker_line ]] || return 1
    menu_line=$(grep -n 'LuaMenuController::Reset' "$log" | tail -1 | cut -d: -f1)
    (( marker_line > ${menu_line:-0} ))
}

ln -sfn "$engine_install/base" "$isolation_dir/base"
ln -sfn "$engine_install/fonts" "$isolation_dir/fonts"
if [[ -d "$engine_install/AI" ]]; then
    ln -sfn "$engine_install/AI" "$isolation_dir/AI"
elif [[ -d "$project_root/spring-linux/AI" ]]; then
    ln -sfn "$project_root/spring-linux/AI" "$isolation_dir/AI"
fi
if [[ -d "$project_root/spring-linux/projects" ]]; then
    ln -sfn "$project_root/spring-linux/projects" "$isolation_dir/projects"
fi
mkdir -p "$isolation_dir/games" "$isolation_dir/maps"

if [[ -z "$game" ]]; then
    # --- Menu mode ---
    for g in "$project_root/spring-linux/games/"*.sdd; do
        ln -sf "$g" "$isolation_dir/games/$(basename "$g")"
    done
    for m in "$project_root/spring-linux/maps/"*; do
        # Area 17 always runs on the patched copy of its map.
        [[ $(basename "$m") == Area17.sd7 ]] && continue
        ln -sf "$m" "$isolation_dir/maps/$(basename "$m")"
    done
    ln -sf "$("$project_root/scripts/area17-map.sh")" "$isolation_dir/maps/Area17.sd7"
    if [[ ! -f "$wasm_menu_dir/WasmMenu/wasm-menu.wasm" ]]; then
        echo "Wasm menu module not found. Build it first:" >&2
        echo "  cd '$wasm_menu_dir/wasm-src' && just copy" >&2
        exit 1
    fi
    ln -s "$wasm_menu_dir" "$isolation_dir/games/WasmMenu.sdd"

    echo "Launching WASM Menu with experimental engine: $engine_bin"
    echo "Live log: $write_dir/infolog.txt"
    launch_engine "$engine_bin" \
        --window \
        --write-dir "$write_dir" \
        --isolation \
        --isolation-dir "$isolation_dir" \
        -menu "WasmMenu 1.0"
else
    # --- Direct game launch ---
    case "$game" in
        hunted)
            game_dir="$project_root/spring-linux/games/Hunted-wasm.sdd"
            map_dir="$project_root/spring-linux/maps/HuntedMap.sdd"
            start_txt="$project_root/launch/hunted.txt"
            config="$isolation_dir/spring.conf"
            cp "$project_root/launch/spring.conf" "$config"
            echo "Shadows = 0" >> "$config"
            ln -sf "$map_dir" "$isolation_dir/maps/Hunted - v04.sdd"
            ;;
        area17)
            game_dir="$project_root/spring-linux/games/Area17-wasm.sdd"
            map_dir="$("$project_root/scripts/area17-map.sh")"
            start_txt="$project_root/launch/area17.txt"
            config="$project_root/launch/area17.conf"
            ln -sf "$map_dir" "$isolation_dir/maps/Area17.sd7"
            ;;
        flove)
            game_dir="$project_root/spring-linux/games/Flove-wasm.sdd"
            map_dir="$project_root/spring-linux/maps/LD34-map.sdd"
            start_txt="$project_root/launch/flove.txt"
            config="$project_root/launch/spring.conf"
            ln -sf "$map_dir" "$isolation_dir/maps/The Grove 0.3.sdd"
            ;;
        ttld)
            game_dir="$project_root/spring-linux/games/ToTheLastDrop-wasm.sdd"
            map_dir="$project_root/spring-linux/maps/LD43-map.sdd"
            start_txt="$project_root/launch/ttld.txt"
            config="$project_root/launch/spring.conf"
            ln -sf "$map_dir" "$isolation_dir/maps/LD43-map.sdd"
            ;;
        gravitas)
            game_dir="$project_root/spring-linux/games/Gravitas-wasm.sdd"
            map_dir="$project_root/spring-linux/maps/Gravitas-map.sdd"
            start_txt="$project_root/launch/gravitas.txt"
            config="$project_root/launch/spring.conf"
            ln -sf "$map_dir" "$isolation_dir/maps/Gravitas-map.sdd"
            ;;
        *)
            echo "Unknown game: $game" >&2
            echo "Supported: hunted, area17, flove, ttld, gravitas" >&2
            exit 1
            ;;
    esac

    if [[ ! -d "$game_dir" || ! -e "$map_dir" ]]; then
        echo "Game or map not found: $game_dir / $map_dir" >&2
        exit 1
    fi

    ln -sf "$game_dir" "$isolation_dir/games/$(basename "$game_dir")"

    # Each direct game session gets its own loopback port.  This lets a menu
    # session or another local Spring instance remain running concurrently.
    host_port="$(shuf -i 20000-60000 -n 1)"
    start_file="$(mktemp "${TMPDIR:-/tmp}/spring-wasm-start.XXXXXX")"
    cp "$start_txt" "$start_file"
    sed -E -i "s/hostport=[0-9]+;/hostport=${host_port};/" "$start_file"

    echo "Launching $game WASM with experimental engine: $engine_bin (port $host_port)"
    echo "Live log: $write_dir/infolog.txt"
    launch_engine "$engine_bin" \
        --window \
        --write-dir "$write_dir" \
        --isolation \
        --isolation-dir "$isolation_dir" \
        --config "$config" \
        "$start_file"
fi
