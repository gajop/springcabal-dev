#!/usr/bin/env bash
# Launch the WASM menu, or one game directly, with exactly what the menu and
# the release use: launch/springsettings.cfg, launch/games/<game>/graphics.cfg
# and launch/games/<game>/<variant>.txt.
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
launch_dir="$project_root/launch"
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
games="$(ls "$launch_dir/games" | tr '\n' ' ')"

usage() {
    echo "Usage: $0 [--game GAME [--lua | --editor]]"
    echo ""
    echo "  No arguments:   the WASM menu"
    echo "  --game GAME     one game directly: $games"
    echo "  --lua           the original Lua version instead of the WASM port"
    echo "  --editor        the Gravitas scenario editor (with --game gravitas)"
    exit 1
}

game=""
variant="wasm"
start_file=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --game) game="${2:-}"; shift 2 ;;
        --lua) variant="lua"; shift ;;
        --editor) variant="editor"; shift ;;
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
if [[ -n "$game" && ! -f "$launch_dir/games/$game/$variant.txt" ]]; then
    echo "No launch/games/$game/$variant.txt (games: $games)" >&2
    exit 1
fi

# The menu compiles launch/games/ in; warn when it predates an edit there.
menu_wasm="$wasm_menu_dir/WasmMenu/wasm-menu.wasm"
if [[ -f "$menu_wasm" ]] && [[ -n "$(find "$launch_dir/games" -newer "$menu_wasm" -print -quit)" ]]; then
    echo "warning: launch/games/ changed after the menu was built; rebuild it with" >&2
    echo "  just --justfile wasm-menu/wasm-src/justfile copy" >&2
fi

# The isolation view has to keep the same path between runs.  The engine's
# archive cache in the write dir records each archive's info-file path, and a
# fresh mktemp directory every launch meant every cached entry pointed at a
# deleted /tmp path, so startup logged one
# "[FSA::GetFileModificationTime] error 'No such file or directory'" per
# archive and then rescanned all of them.  One stable directory per launch
# mode.
isolation_dir="$run_dir/isolation-${game:-menu}"
rm -rf -- "$isolation_dir/games" "$isolation_dir/maps"
mkdir -p "$isolation_dir/games" "$isolation_dir/maps" "$write_dir" "$log_dir"

session_log="$log_dir/wasm-$(date +%Y%m%d-%H%M%S)-$$.infolog.txt"

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
# The summary runs once, on exit.  INT/TERM only exit, which runs it; a
# handler on INT itself would run it twice.
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Engine data and every archive, as in the release bundle.
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
for g in "$project_root/spring-linux/games/"*.sdd; do
    ln -sf "$g" "$isolation_dir/games/$(basename "$g")"
done
for m in "$project_root/spring-linux/maps/"*; do
    # Area 17 always runs on the patched copy of its map.
    [[ $(basename "$m") == Area17.sd7 ]] && continue
    ln -sf "$m" "$isolation_dir/maps/$(basename "$m")"
done
ln -sfn "$("$project_root/scripts/area17-map.sh" --dir)" "$isolation_dir/maps/Area17.sdd"
if [[ ! -f "$menu_wasm" ]]; then
    echo "Wasm menu module not found. Build it first:" >&2
    echo "  cd '$wasm_menu_dir/wasm-src' && just copy" >&2
    exit 1
fi
ln -sfn "$wasm_menu_dir" "$isolation_dir/games/WasmMenu.sdd"

# Settings: the release profile, then personal window settings (launch/local.cfg),
# then, for a direct launch, the game's overrides (the menu applies those itself).
config="$run_dir/springsettings.cfg"
{
    cat "$launch_dir/springsettings.cfg"
    [[ -f "$launch_dir/local.cfg" ]] && printf '\n' && cat "$launch_dir/local.cfg"
    if [[ -n "$game" && -f "$launch_dir/games/$game/graphics.cfg" ]]; then
        printf '\n'
        cat "$launch_dir/games/$game/graphics.cfg"
    fi
} >"$config"

if [[ -z "$game" ]]; then
    echo "Launching WASM Menu with experimental engine: $engine_bin"
    echo "Live log: $write_dir/infolog.txt"
    "$engine_bin" --window --write-dir "$write_dir" \
        --isolation --isolation-dir "$isolation_dir" --config "$config" \
        -menu "WasmMenu 1.0"
else
    # Each direct session gets its own loopback port, so a menu session or
    # another local Spring instance can keep running.
    host_port="$(shuf -i 20000-60000 -n 1)"
    start_file="$(mktemp "${TMPDIR:-/tmp}/spring-wasm-start.XXXXXX")"
    sed -E "s/([Hh]ost[Pp]ort)=[0-9]+;/\1=${host_port};/" "$launch_dir/games/$game/$variant.txt" >"$start_file"

    echo "Launching $game ($variant) with experimental engine: $engine_bin (port $host_port)"
    echo "Live log: $write_dir/infolog.txt"
    # Games leave with `reloadforce` (Ctrl+Q, quit buttons), which goes to the
    # engine's menu.  Naming the WASM menu here makes that the menu, as it is
    # when the game was started from it, so quitting a directly launched game
    # also lands in the WASM menu, in the same process.
    "$engine_bin" --window --write-dir "$write_dir" \
        --isolation --isolation-dir "$isolation_dir" --config "$config" \
        -menu "WasmMenu 1.0" "$start_file"
fi
