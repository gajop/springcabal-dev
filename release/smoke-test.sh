#!/usr/bin/env bash
# Smoke-test every menu entry and the menu on the real GPU through SDL's
# offscreen driver (Linux) or Wine/VirtualGL in Xvfb (Windows). Runs use the shipped graphics
# profile and per-game overrides. Any warning, error or runtime failure fails.
# Games must load and remain running until the timeout; frame counts are
# informational because some games start paused or stop logging frames.
#
# Usage: release/smoke-test.sh BUNDLE [seconds] [--wine WINE]
set -uo pipefail

bundle="$(cd "${1:?bundle directory}" && pwd)"
shift
seconds=45
wine_loader=''
if [[ ${1:-} != --* && $# -gt 0 ]]; then seconds=$1; shift; fi
if [[ $# -gt 0 ]]; then
    [[ $# -eq 2 && $1 == --wine ]] || { echo 'Usage: smoke-test.sh BUNDLE [seconds] [--wine WINE]' >&2; exit 2; }
    wine_loader=$(command -v "$2") || exit 2
fi
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -n $wine_loader && ${SPRINGCABAL_SMOKE_XVFB:-} != 1 ]]; then
    exec xvfb-run -a env SPRINGCABAL_SMOKE_XVFB=1 "$project_root/release/smoke-test.sh" "$bundle" "$seconds" --wine "$wine_loader"
fi
work="$(mktemp -d "${TMPDIR:-/tmp}/springcabal-smoke.XXXXXX")"

engine="$bundle/SpringCabal"
launch=()
if [[ -n $wine_loader ]]; then
    engine="$bundle/SpringCabal.exe"
    vglrun=${VF_VGLRUN:-$(command -v vglrun)}
    [[ -x $vglrun ]] || { echo 'Windows GPU smoke checks require VF_VGLRUN or vglrun' >&2; exit 2; }
    wine_server=${WINESERVER:-$(command -v wineserver)}
    [[ -x $wine_server ]] || { echo 'Set WINESERVER for this Wine installation' >&2; exit 2; }
    # Own this prefix and its server; never stop another task's Wine runtime.
    export WINEPREFIX="$work/wineprefix" WINEARCH=win64 WINEDEBUG=-all
    export WINELOADER="$wine_loader" WINESERVER="$wine_server"
    cleanup_wine() {
        local smoke_status=$?
        trap - EXIT
        timeout 15s "$wine_server" -k || smoke_status=1
        timeout 30s "$wine_server" -w || smoke_status=1
        if (( smoke_status == 0 )); then rm -rf -- "$work/wineprefix"; fi
        exit "$smoke_status"
    }
    trap cleanup_wine EXIT
    launch=("$vglrun" -d "${VF_VGL_DISPLAY:-egl}" -c proxy "$wine_loader")
fi
[[ -f "$engine" ]] || { echo "no SpringCabal executable in $bundle" >&2; exit 1; }
[[ -f "$bundle/springsettings.cfg" ]] || { echo "no springsettings.cfg in $bundle" >&2; exit 1; }
path_arg() {
    if [[ -n $wine_loader ]]; then printf 'Z:%s' "${1//\//\\}"; else printf '%s' "$1"; fi
}
run_engine() {
    local duration=$1 directory=$2
    shift 2
    local environment=(env -u LIBGL_ALWAYS_SOFTWARE)
    if [[ -n $wine_loader ]]; then
        environment+=(-u SDL_VIDEODRIVER)
    else
        environment+=(SDL_VIDEODRIVER=offscreen)
    fi
    "${environment[@]}" python3 "$project_root/release/smoke-run.py" \
        --seconds "$duration" --guard "$directory/guard.json" \
        --max-minutes "${VF_MAX_IDLE_MINUTES:-1440}" -- \
        "${launch[@]}" "$(path_arg "$engine")" \
        --window --isolation --isolation-dir "$(path_arg "$bundle")" \
        --write-dir "$(path_arg "$directory")" \
        --config "$(path_arg "$directory/spring.conf")" "$@"
}
# Use the bundled fonts, as verification/sdk-menu/run.py does. The engine's
# bundled Fontconfig can predate the host configuration syntax; each fresh
# write directory otherwise scans the host fonts and reports parser warnings.
python3 - "$bundle/fonts" "$work" <<'PY'
from pathlib import Path
import sys
from xml.sax.saxutils import escape
fonts, work = map(Path, sys.argv[1:])
(work / "fonts.conf").write_text(
    f'<fontconfig><dir>{escape(str(fonts))}</dir>'
    f'<cachedir>{escape(str(work / "fontcache"))}</cachedir></fontconfig>\n'
)
PY
export FONTCONFIG_FILE="$work/fonts.conf"
# shellcheck source=../verification/lib/failures.sh
source "$project_root/verification/lib/failures.sh"
crash_pattern='Segmentation fault|\[Fatal\]|wasm trap|panicked at|AddressSanitizer'
diagnostic_pattern='\b(Error|Warning):'
software_pattern='llvmpipe|softpipe|swrast|SwiftShader|software|lavapipe|GDI Generic|Microsoft Basic Render'

# config OUT [GRAPHICS]: the shipped profile, the game's overrides, no sound.
config() {
    local out=$1 graphics=${2:-} key value
    cp "$bundle/springsettings.cfg" "$out"
    set_key() {
        sed -i -E "/^[[:space:]]*$1[[:space:]]*=/d" "$out"
        printf '%s = %s\n' "$1" "$2" >>"$out"
    }
    if [[ -f $graphics ]]; then
        while IFS='=' read -r key value; do
            key=${key//[[:space:]]/}
            [[ -z $key || $key == \#* ]] && continue
            set_key "$key" "$(sed 's/^[[:space:]]*//; s/[[:space:]]*$//' <<<"$value")"
        done <"$graphics"
    fi
    set_key snd_volmaster 0
    set_key Fullscreen 0
    set_key WindowBorderless 1
    set_key WindowPosX 0
    set_key WindowPosY 0
    set_key XResolutionWindowed 1280
    set_key YResolutionWindowed 720
}

# Check both Lua and WASM runs, including a renderer identity from startup.
clean_log() {
    local log=$1 renderer size
    if grep -iE "$diagnostic_pattern|$crash_pattern|$RUNTIME_FAILURE_PATTERN" "$log"; then
        return 1
    fi
    renderer=$(sed -nE 's/.*GL renderer[[:space:]]*:[[:space:]]*//p' "$log" | head -1)
    if [[ -z $renderer ]]; then
        echo 'missing GL renderer identity' >&2
        return 1
    fi
    if grep -qiE "$software_pattern" <<<"$renderer"; then
        printf 'software renderer: %s\n' "$renderer" >&2
        return 1
    fi
    size=$(sed -nE 's/.*\[GR::LogDisplayMode\] display-mode set to ([0-9]+x[0-9]+)x[0-9]+bpp.*/\1/p' "$log" | tail -1)
    if [[ $size != 1280x720 ]]; then
        printf 'unexpected drawable size: %s (expected 1280x720)\n' "${size:-missing}" >&2
        return 1
    fi
}

# The exact start scripts the menu launches (it compiles these files in).
mapfile -t scripts < <(ls "$project_root"/launch/games/*/{wasm,lua}.txt)

failures=0
printf '%-36s %-10s %-8s %-8s %s\n' GAME RESULT FRAMES ERRORS WARNINGS
for script in "${scripts[@]}"; do
    game=$(basename "$(dirname "$script")")
    game_type="$game/$(basename "$script" .txt)"
    run="$work/${game}-$(basename "$script" .txt)"
    mkdir -p "$run"
    sed -E "s/([Hh]ost[Pp]ort)=[0-9]+;/\1=$(shuf -i 20000-60000 -n 1);/" "$script" > "$run/start.txt"
    config "$run/spring.conf" "$project_root/launch/games/$game/graphics.cfg"

    run_engine "$seconds" "$run" "$(path_arg "$run/start.txt")" > "$run/stdout.txt" 2>&1
    status=$?

    # infolog.txt is only flushed on a clean exit; stdout has the same log.
    log="$run/stdout.txt"
    last_frame="$(grep -oE '\[f=[0-9]+\]' "$log" | tail -1 | tr -dc '0-9' | sed 's/^0*//')"
    errors="$(grep -ciE '\bError:' "$log")"
    warnings="$(grep -ciE '\bWarning:' "$log")"
    log_ok=0
    clean_log "$log" || log_ok=1
    if grep -q "finished loading and is now ingame" "$log" && (( status == 124 )) \
        && (( log_ok == 0 )); then
        result=ok
    else
        result="FAIL($status)"
        failures=$((failures + 1))
    fi
    printf '%-36s %-10s %-8s %-8s %s\n' "$game_type" "$result" "${last_frame:-0}" "${errors:-0}" "${warnings:-0}"
done

run="$work/menu"
mkdir -p "$run"
config "$run/spring.conf"
run_engine 90 "$run" > "$run/stdout.txt" 2>&1
status=$?
log="$run/stdout.txt"
errors="$(grep -ciE '\bError:' "$log")"
warnings="$(grep -ciE '\bWarning:' "$log")"
log_ok=0
clean_log "$log" || log_ok=1
# The engine prefers the native SDK menu when the bundle contains both backends.
if grep -Eq 'Wasm manifest loaded from WasmMenu/manifest.json|Successfully loaded native module WasmMenu/libNativeMenu.so' "$log" \
    && (( status == 0 || status == 124 )) && (( log_ok == 0 )); then
    printf '%-36s %-10s %-8s %-8s %s\n' 'WasmMenu' ok - "${errors:-0}" "${warnings:-0}"
else
    printf '%-36s %-10s %-8s %-8s %s\n' 'WasmMenu' "FAIL($status)" - "${errors:-0}" "${warnings:-0}"
    failures=$((failures + 1))
fi

echo ""
echo "Logs: $work"
exit $(( failures > 0 ))
