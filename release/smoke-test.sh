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
work="$(mktemp -d "${TMPDIR:-/tmp}/springcabal-smoke.XXXXXX")"

[[ -x "$bundle/spring-headless" ]] || { echo "no spring-headless in $bundle" >&2; exit 1; }

# The exact start scripts the menu launches (it compiles these files in).
mapfile -t scripts < <(ls "$project_root"/launch/games/*/{wasm,lua}.txt)

failures=0
printf '%-36s %-10s %-8s %s\n' GAME RESULT FRAMES ERRORS
for script in "${scripts[@]}"; do
    game=$(basename "$(dirname "$script")")
    game_type="$game/$(basename "$script" .txt)"
    run="$work/${game}-$(basename "$script" .txt)"
    mkdir -p "$run"
    sed -E "s/([Hh]ost[Pp]ort)=[0-9]+;/\1=$(shuf -i 20000-60000 -n 1);/" "$script" > "$run/start.txt"
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
