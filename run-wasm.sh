#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
engine_root="${SPRING_BAR_DIR:-/home/gajop/projects/spring-projects/spring-bar}"
engine_bin="$engine_root/build-amd64-linux/install/spring"
wasm_menu_dir="$project_root/wasm-menu"
write_dir="$project_root/wasm-test/write"
log_dir="$write_dir/logs"

usage() {
    echo "Usage: $0 [--game hunted|area17]"
    echo ""
    echo "  No arguments:       launch the WASM menu (pick a game interactively)"
    echo "  --game hunted       launch Hunted WASM directly"
    echo "  --game area17       launch Area 17 WASM directly"
    echo "  --game flove        launch Flove WASM directly (bypasses the menu)"
    echo "  --game ttld         launch To the Last Drop WASM directly"
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
    exit 1
fi

# The isolation view has to keep the same path between runs.  The engine's
# archive cache in the write dir records each archive's info-file path, and a
# fresh mktemp directory every launch meant every cached entry pointed at a
# deleted /tmp path, so startup logged one
# "[FSA::GetFileModificationTime] error 'No such file or directory'" per
# archive and then rescanned all of them.  One stable directory per launch
# mode, since the modes link different archives under different names.
isolation_dir="$project_root/wasm-test/isolation-${game:-menu}"
rm -rf -- "$isolation_dir/games" "$isolation_dir/maps"
mkdir -p "$isolation_dir" "$write_dir" "$log_dir"

session_log="$log_dir/wasm-$(date +%Y%m%d-%H%M%S)-$$.infolog.txt"
return_marker="AREA17_RETURN_TO_WASM_MENU"

cleanup() {
    if [[ -n "$start_file" ]]; then
        rm -f -- "$start_file"
    fi
    if [[ -f "$write_dir/infolog.txt" ]]; then
        cp -- "$write_dir/infolog.txt" "$session_log"
        echo "Saved session log: $session_log"
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
    fi
    echo "Kept isolated launch view: $isolation_dir"
}
trap cleanup EXIT INT TERM

launch_engine() {
    set +e
    "$@"
    local status=$?
    set -e
    if grep -q "$return_marker" "$write_dir/infolog.txt" 2>/dev/null; then
        echo "Area 17 requested a return to the WASM menu."
        exec "$project_root/run-wasm.sh"
    fi
    return "$status"
}

ln -sfn "$engine_root/build-amd64-linux/install/base" "$isolation_dir/base"
ln -sfn "$engine_root/build-amd64-linux/install/fonts" "$isolation_dir/fonts"
if [[ -d "$engine_root/build-amd64-linux/install/AI" ]]; then
    ln -sfn "$engine_root/build-amd64-linux/install/AI" "$isolation_dir/AI"
elif [[ -d "$project_root/spring-linux/AI" ]]; then
    ln -sfn "$project_root/spring-linux/AI" "$isolation_dir/AI"
fi
mkdir -p "$isolation_dir/games" "$isolation_dir/maps"

if [[ -z "$game" ]]; then
    # --- Menu mode ---
    for g in "$project_root/spring-linux/games/"*.sdd; do
        ln -sf "$g" "$isolation_dir/games/$(basename "$g")"
    done
    for m in "$project_root/spring-linux/maps/"*; do
        ln -sf "$m" "$isolation_dir/maps/$(basename "$m")"
    done
    if [[ -f "$project_root/area17-test/Area17-wasm.sd7" ]]; then
        ln -sf "$project_root/area17-test/Area17-wasm.sd7" "$isolation_dir/maps/Area 17 - v01.sd7"
    fi
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
            start_txt="$project_root/wasm-test/start.txt"
            config="$project_root/wasm-test/spring.conf"
            ln -sf "$map_dir" "$isolation_dir/maps/Hunted - v04.sdd"
            ;;
        area17)
            game_dir="$project_root/spring-linux/games/Area17-wasm.sdd"
            map_dir="$project_root/area17-test/Area17-wasm.sd7"
            start_txt="$project_root/area17-test/start.txt"
            config="$project_root/area17-test/spring.conf"
            ln -sf "$map_dir" "$isolation_dir/maps/Area 17 - v01.sd7"
            ;;
        flove)
            game_dir="$project_root/spring-linux/games/Flove-wasm.sdd"
            map_dir="$project_root/spring-linux/maps/LD34-map.sdd"
            start_txt="$project_root/wasm-test/flove-start.txt"
            config="$project_root/wasm-test/spring.conf"
            ln -sf "$map_dir" "$isolation_dir/maps/The Grove 0.3.sdd"
            ;;
        ttld)
            game_dir="$project_root/spring-linux/games/ToTheLastDrop-wasm.sdd"
            map_dir="$project_root/spring-linux/maps/LD43-map.sdd"
            start_txt="$project_root/wasm-test/ttld-start.txt"
            config="$project_root/wasm-test/spring.conf"
            ln -sf "$map_dir" "$isolation_dir/maps/LD43-map.sdd"
            ;;
        *)
            echo "Unknown game: $game" >&2
            echo "Supported: hunted, area17, flove, ttld" >&2
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
