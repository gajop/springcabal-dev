#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
engine_root="${SPRING_BAR_DIR:-/home/gajop/projects/spring-projects/spring-bar}"
engine_bin="$engine_root/build-amd64-linux/install/spring"
game_dir="$project_root/spring-linux/games/Area17-wasm.sdd"
map_file="$project_root/area17-test/Area17-wasm.sd7"
write_dir="${AREA17_WRITE_DIR:-$project_root/area17-test/write}"
log_dir="$write_dir/logs"

if [[ ! -x "$engine_bin" ]]; then
    echo "Experimental engine not found: $engine_bin" >&2
    echo "Build it with: cd '$engine_root' && ./docker-build-v2/build.sh linux -DUSE_ASAN=ON" >&2
    exit 1
fi

if [[ ! -d "$game_dir" || ! -f "$map_file" ]]; then
    echo "Area 17 WASM game or map is missing." >&2
    exit 1
fi

isolation_dir="$(mktemp -d "${TMPDIR:-/tmp}/area17-wasm-isolation.XXXXXX")"
mkdir -p "$write_dir" "$log_dir"

session_log="$log_dir/area17-$(date +%Y%m%d-%H%M%S)-$$.infolog.txt"
return_marker="AREA17_RETURN_TO_WASM_MENU"

cleanup() {
    if [[ -f "$write_dir/infolog.txt" ]]; then
        cp -- "$write_dir/infolog.txt" "$session_log"
        echo "Saved session log: $session_log"
    fi
    echo "Kept isolated launch view: $isolation_dir"
}
trap cleanup EXIT INT TERM

ln -s "$engine_root/build-amd64-linux/install/base" "$isolation_dir/base"
ln -s "$engine_root/build-amd64-linux/install/fonts" "$isolation_dir/fonts"
mkdir "$isolation_dir/games" "$isolation_dir/maps"
ln -s "$game_dir" "$isolation_dir/games/Area17-wasm.sdd"
ln -s "$map_file" "$isolation_dir/maps/Area 17 - v01.sd7"

echo "Launching Area 17 WASM with experimental engine: $engine_bin"
echo "Persistent write/cache directory: $write_dir"
echo "Live log: $write_dir/infolog.txt"
echo "The isolated symlink view will be kept: $isolation_dir"

set +e
"$engine_bin" \
    --window \
    --write-dir "$write_dir" \
    --isolation \
    --isolation-dir "$isolation_dir" \
    --config "$project_root/area17-test/spring.conf" \
    "$project_root/area17-test/start.txt"
status=$?
set -e

if grep -q "$return_marker" "$write_dir/infolog.txt" 2>/dev/null; then
    echo "Area 17 requested a return to the WASM menu."
    exec "$project_root/run-wasm.sh"
fi

exit "$status"
