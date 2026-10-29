#!/usr/bin/env bash
# Start scripts, engine settings, launches and driven input. Sourced by common.sh.

vf_engine_bin() {
    local mode=${1:?mode} name candidate
    case "$mode" in
        headless) name=spring-headless; candidate=${SPRING_HEADLESS_BIN:-} ;;
        visual) name=spring; candidate=${SPRING_ENGINE_BIN:-} ;;
        *) vf_die "vf_engine_bin: unknown mode '$mode'" ;;
    esac

    if [[ -z $candidate ]]; then
        candidate="$ENGINE_INSTALL/$name"
    fi
    [[ -x $candidate ]] || vf_die "engine not found: $candidate
Build it with: cd '$ENGINE_ROOT' && ./docker-build-v2/build.sh linux"
    printf '%s\n' "$candidate"
}

vf_start_file() {
    local fixture=${1:?start fixture}
    [[ -f $fixture ]] || vf_die "start script not found: $fixture"

    VF_START_FILE="$VF_TEST_ROOT/start.txt"
    cp "$fixture" "$VF_START_FILE"
    vf_random_host_port
    if [[ -n ${VF_RUST_JOBS:-} ]]; then
        case "$VF_RUST_JOBS" in off|on|check) ;; *) vf_die 'VF_RUST_JOBS must be off, on or check' ;; esac
        vf_modoption rust_jobs "$VF_RUST_JOBS"
    fi
}

# vf_speed MIN [MAX]: the game speed range, and so the speed the game starts
# at (1, clamped into the range).  The engine reads MinSpeed and MaxSpeed only
# from [modoptions] (defaults 0.1 and 20); the launch scripts set neither.
# Headless runs default to 100x and visual runs to 1x (vf_default_speed);
# call this before the run to choose otherwise.
vf_speed() {
    local min=${1:?min speed} max=${2:-$1}
    vf_modoption MinSpeed "$min"
    vf_modoption MaxSpeed "$max"
}

# vf_default_speed SPEED: pin the speed (VF_SPEED overrides it, for
# debugging) unless the suite chose one.
vf_default_speed() {
    grep -qiE '(^|[[:space:];{])MaxSpeed[[:space:]]*=' <(vf_modoptions_text) || vf_speed "${VF_SPEED:-${1:?speed}}"
}

# The [modoptions] section of the current start script.
vf_modoptions_text() {
    python3 - "$VF_START_FILE" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
section = re.search(r'(?i)\[modoptions\]\s*\{([^}]*)\}', text)
print(section.group(1) if section else '')
PY
}

vf_start_inline() {
    VF_START_FILE="$VF_TEST_ROOT/start.txt"
    cat >"$VF_START_FILE"
    vf_random_host_port
    if [[ -n ${VF_RUST_JOBS:-} ]]; then
        case "$VF_RUST_JOBS" in off|on|check) ;; *) vf_die 'VF_RUST_JOBS must be off, on or check' ;; esac
        vf_modoption rust_jobs "$VF_RUST_JOBS"
    fi
}

# Every run gets its own host port, so runs never collide on the fixed 8452 of
# the launch scripts (which spell it HostPort, hostport or Hostport).
vf_random_host_port() {
    sed -E -i "s/hostport[[:space:]]*=[[:space:]]*[0-9]+;/hostport=$(shuf -i 20000-60000 -n 1);/I" "$VF_START_FILE"
}

# vf_start_set KEY VALUE: set a top-level [GAME] entry such as GameType,
# MapName or FixedRNGSeed (key match is case-insensitive; added if missing).
vf_start_set() {
    local key=${1:?key} value=${2?value}
    [[ -f $VF_START_FILE ]] || vf_die 'vf_start_set: no start script yet'
    if grep -qiE "(^|[[:space:];])${key}[[:space:]]*=" "$VF_START_FILE"; then
        KEY=$key VALUE=$value perl -i -pe \
            's/(^|[\s;])\Q$ENV{KEY}\E\s*=[^;]*;/$1$ENV{KEY}=$ENV{VALUE};/i' "$VF_START_FILE"
    else
        KEY=$key VALUE=$value perl -0 -i -pe \
            's/(\[GAME\]\s*\{)/$1\n$ENV{KEY}=$ENV{VALUE};/i' "$VF_START_FILE"
    fi
}

# vf_modoption KEY VALUE: set a [modoptions] entry in the current start script,
# creating the section if the script has none.
vf_modoption() {
    local key=${1:?key} value=${2?value}
    [[ -f $VF_START_FILE ]] || vf_die 'vf_modoption: no start script yet'
    python3 - "$VF_START_FILE" "$key" "$value" <<'PY'
import re, sys
path, key, value = sys.argv[1:]
text = open(path).read()
entry = re.compile(r'(?im)^(\s*)' + re.escape(key) + r'\s*=[^;]*;')
section = re.search(r'(?i)\[modoptions\]\s*\{', text)
if section and entry.search(text, section.end()):
    text = entry.sub(lambda m: f"{m.group(1)}{key}={value};", text, count=1)
elif section:
    text = text[:section.end()] + f"\n{key}={value};" + text[section.end():]
else:
    end = text.rstrip().rfind('}')
    text = text[:end] + f"[modoptions]\n{{\n{key}={value};\n}}\n" + text[end:]
open(path, 'w').write(text)
PY
}

# vf_quit_when [--frame N] [MARKER...]
# End the run with quitforce once every MARKER (plain text) has been logged, on
# "ASSERTION FAILED", or at game frame N, instead of at the timeout. Only a
# clean exit flushes the headless infolog and lets an ASAN engine report
# leaks. The timeout stays as the backstop. Call after the start script is
# written; a linked game is staged as a copy first.
vf_quit_when() {
    local frame='' staged draw markers='' marker
    if [[ ${1:-} == --frame ]]; then
        frame=${2:?frame}
        shift 2
    fi
    # The staged copy (vf_stage_game runs in a subshell, so look for it), else
    # a copy of the linked game.
    local -a copies=()
    for staged in "$VF_ISOLATION"/games/*; do
        [[ -d $staged && ! -L $staged ]] && copies+=("$staged")
    done
    if (( ${#copies[@]} == 1 )); then
        staged=${copies[0]}
    elif (( ${#copies[@]} == 0 )) && [[ -n ${VF_GAME_DIR:-} && -L $VF_ISOLATION/games/$(basename "$VF_GAME_DIR") ]]; then
        rm -f -- "$VF_ISOLATION/games/$(basename "$VF_GAME_DIR")"
        staged=$(vf_stage_game "$VF_GAME_DIR")
    else
        vf_die "vf_quit_when: expected one staged or linked game, found ${#copies[@]} staged copies"
    fi
    mkdir -p "$staged/LuaRules/Gadgets"
    cp "$FIXTURES_DIR/quit.lua" "$staged/LuaRules/Gadgets/zz_verify_quit.lua"

    # Most WASM ports run no unsynced gadgets (draw.lua is empty or
    # `return true`); give those an entry point that runs only this one.
    draw="$staged/LuaRules/draw.lua"
    if ! grep -q 'gadgets\.lua' "$draw" 2>/dev/null; then
        if [[ -s $draw ]] && grep -vE '^[[:space:]]*(--.*)?$' "$draw" | grep -qvE '^[[:space:]]*return true[[:space:]]*$'; then
            vf_die "vf_quit_when: $draw runs its own unsynced code; add the quit gadget there"
        fi
        cat >"$draw" <<'LUA'
-- Verification entry point: this game has no unsynced gadgets, so run only
-- the verification quit gadget.
gadget = {}
gadgetHandler = { IsSyncedCode = function() return false end }
VFS.Include("LuaRules/Gadgets/zz_verify_quit.lua", nil, VFS.ZIP_FIRST)
function GameFrame(n) gadget:GameFrame(n) end
gadget:Initialize()
LUA
    fi

    for marker in "$@"; do
        [[ $marker != *[\;\}\|]* ]] || vf_die "vf_quit_when: marker cannot contain ; } or |: $marker"
        markers+=${markers:+||}$marker
    done
    [[ -n $markers || -n $frame ]] || vf_die 'vf_quit_when: give markers or --frame'
    [[ -z $markers ]] || vf_modoption vf_quit_markers "$markers"
    [[ -z $frame ]] || vf_modoption vf_quit_frame "$frame"
}

vf_config() {
    local fixture=${1:-$DEFAULT_CONFIG}
    [[ -f $fixture ]] || vf_die "config not found: $fixture"
    VF_CONFIG_FILE="$VF_TEST_ROOT/spring.conf"
    cp "$fixture" "$VF_CONFIG_FILE"
    # Test-only additions; none changes how the world renders.  The FPS/speed
    # counters would put changing numbers into screenshots.
    printf '\nInfoConsoleGeometry = 0 0 0 0\nMaxTextureAtlasSizeX = 16384\nMaxTextureAtlasSizeY = 16384\nShowFPS = 0\nShowSpeed = 0\nShowClock = 0\n' \
        >>"$VF_CONFIG_FILE"
    # Verification runs are silent unless VF_SOUND=1.
    [[ ${VF_SOUND:-0} == 1 ]] || printf 'snd_volmaster = 0\n' >>"$VF_CONFIG_FILE"
    if [[ -n ${VF_WORKER_THREADS:-} ]]; then
        [[ $VF_WORKER_THREADS =~ ^[1-9][0-9]?$ && $VF_WORKER_THREADS -le 64 ]] ||
            vf_die 'VF_WORKER_THREADS must be between 1 and 64'
        vf_config_set WorkerThreadCount "$VF_WORKER_THREADS"
    fi
}

# Settings for an ASAN engine; plain builds ignore them. Leak checking stays on
# with only the third-party leaks in lsan.supp suppressed, and a run that
# leaks fails (vf_check_leaks). Suppressions passed in LSAN_OPTIONS win.
vf_sanitizer_env() {
    export ASAN_OPTIONS=${ASAN_OPTIONS:-allocator_may_return_null=1}
    if [[ ${LSAN_OPTIONS:-} != *suppressions=* ]]; then
        export LSAN_OPTIONS="${LSAN_OPTIONS:+$LSAN_OPTIONS:}suppressions=$VERIFICATION_ROOT/lsan.supp:print_suppressions=0"
    fi
}

vf_check_leaks() {
    local stdout="$VF_WRITE_DIR/stdout.txt"
    grep -q 'ERROR: LeakSanitizer' "$stdout" 2>/dev/null || return 0
    cp -f -- "$stdout" "$VF_OUT_DIR/last.stdout.txt" 2>/dev/null || true
    grep -E '^SUMMARY: AddressSanitizer' "$stdout" >&2 || true
    vf_die "LeakSanitizer reported leaks (full report: $VF_OUT_DIR/last.stdout.txt; add a narrow third-party entry to verification/lsan.supp only if the stack never reaches engine or game code)"
}

vf_run_headless() {
    local seconds=${1:?seconds} engine
    if [[ $(vf_renderer) != headless ]]; then
        vf_default_speed 100
        vf_run_visual "$seconds"
        return
    fi
    VF_RUN_RENDERER=headless
    engine=$(vf_engine_bin headless)
    vf_sanitizer_env
    vf_default_speed 100
    rm -f -- "$VF_WRITE_DIR/infolog.txt"

    set +e
    timeout --signal=TERM "${seconds}s" "$engine" \
        --write-dir "$VF_WRITE_DIR" \
        --isolation \
        --isolation-dir "$VF_ISOLATION" \
        --config "$VF_CONFIG_FILE" \
        "$VF_START_FILE" >"$VF_WRITE_DIR/stdout.txt" 2>&1
    VF_ENGINE_STATUS=$?
    set -e
    vf_check_leaks
    return 0
}

# vf_graphics GAME: launch/games/GAME/graphics.cfg, the per-game overrides the
# menu (and run-wasm.sh, and the release) apply on top of springsettings.cfg.
vf_graphics() {
    local file="$LAUNCH_DIR/games/${1:?game}/graphics.cfg" key value
    [[ -f $file ]] || return 0
    while IFS='=' read -r key value; do
        key=${key//[[:space:]]/}
        [[ -z $key || $key == \#* ]] && continue
        vf_config_set "$key" "$(echo "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    done <"$file"
}

# vf_launch_script GAME [wasm|lua|editor]: the start script the menu uses.
vf_launch_script() {
    local file="$LAUNCH_DIR/games/${1:?game}/${2:-wasm}.txt"
    [[ -f $file ]] || vf_die "no launch script: $file"
    printf '%s\n' "$file"
}

# vf_config_set KEY VALUE: set one engine config entry (replacing any earlier).
vf_config_set() {
    local key=${1:?key} value=${2?value}
    [[ -f $VF_CONFIG_FILE ]] || vf_die 'vf_config_set: call vf_config first'
    sed -i -E "/^[[:space:]]*${key}[[:space:]]*=/d" "$VF_CONFIG_FILE"
    printf '%s = %s\n' "$key" "$value" >>"$VF_CONFIG_FILE"
}

# Rendering backend for visual runs (VF_RENDERER, or the suite's default):
#   software  Xvfb + Mesa llvmpipe: invisible, any size, not the real driver
#   gpu       the real GPU through SDL's offscreen video driver (EGL, no window)
#   screen    a real window on $DISPLAY: any size, takes over the screen
#   headless  CPU-only diagnostics, available for integration runs
# Goldens record the renderer they were made with (see lib/gallery.py).
vf_renderer() {
    printf '%s\n' "${VF_RENDERER:-${VF_DEFAULT_RENDERER:-gpu}}"
}

vf_run_visual() {
    local seconds=${1:?seconds} screen=${2:-1280x720x24} engine renderer width height
    engine=$(vf_engine_bin visual)
    renderer=$(vf_renderer)
    VF_RUN_RENDERER=$renderer
    width=${screen%%x*}
    height=${screen#*x}; height=${height%%x*}
    VF_RUN_SIZE="${width}x${height}"
    # Scenarios and captures run in real time.
    vf_default_speed 1
    rm -f -- "$VF_WRITE_DIR/infolog.txt"
    vf_sanitizer_env
    rm -rf -- "${VF_WRITE_DIR:?}/screenshots"/*

    local -a args=(--window --write-dir "$VF_WRITE_DIR" --isolation --isolation-dir "$VF_ISOLATION"
        --config "$VF_CONFIG_FILE" "$VF_START_FILE")
    set +e
    case "$renderer" in
        software)
            LIBGL_ALWAYS_SOFTWARE=1 SDL_VIDEODRIVER=x11 WAYLAND_DISPLAY= \
                timeout --signal=TERM "${seconds}s" \
                xvfb-run -a -s "-screen 0 $screen +extension GLX" \
                "$engine" "${args[@]}" >"$VF_WRITE_DIR/stdout.txt" 2>&1
            ;;
        gpu)
            vf_config_set Fullscreen 0
            vf_config_set WindowBorderless 1
            vf_config_set WindowPosX 0
            vf_config_set WindowPosY 0
            vf_config_set XResolutionWindowed "$width"
            vf_config_set YResolutionWindowed "$height"
            SDL_VIDEODRIVER=offscreen \
                timeout --signal=TERM "${seconds}s" \
                "$engine" "${args[@]}" >"$VF_WRITE_DIR/stdout.txt" 2>&1
            ;;
        screen)
            [[ -n ${DISPLAY:-} ]] || vf_die 'VF_RENDERER=screen needs $DISPLAY'
            vf_config_set Fullscreen 0
            vf_config_set XResolutionWindowed "$width"
            vf_config_set YResolutionWindowed "$height"
            timeout --signal=TERM "${seconds}s" \
                "$engine" "${args[@]}" >"$VF_WRITE_DIR/stdout.txt" 2>&1
            ;;
        *) set -e; vf_die "unknown VF_RENDERER: $renderer (software, gpu or screen)" ;;
    esac
    VF_ENGINE_STATUS=$?
    set -e
    local actual
    actual=$(grep -m1 -oE 'GL renderer : .*' "$VF_WRITE_DIR/stdout.txt" | sed 's/GL renderer : //' || true)
    printf 'renderer: %s (%s)\n' "$renderer" "${actual:-unknown}"
    vf_check_leaks
    return 0
}

# vf_run_driven SECONDS DRIVER [SCREEN]
# A visual run played through real input: the engine renders on its own Xvfb
# display (GPU rendering by default) in a window at 0,0. DRIVER runs
# alongside it with DISPLAY set and presses keys and buttons with xdotool
# (vf_x_* below), usually waiting for markers the game logs.  When the driver
# returns, the engine is stopped if it is still running.  The run's status is
# the driver's; VF_ENGINE_STATUS is the engine's (124 when stopped).
# GPU input runs use VirtualGL's EGL backend for rendering into the X display.
vf_run_driven() {
    local seconds=${1:?seconds} driver=${2:?driver} screen=${3:-1280x720x24}
    local engine width height display='' n xvfb_pid engine_pid status
    command -v xdotool >/dev/null || vf_die 'driven runs need xdotool'
    engine=$(vf_engine_bin visual)
    local renderer
    renderer=$(vf_renderer)
    local -a graphics_env=() graphics_command=()
    case "$renderer" in
        software) graphics_env+=(LIBGL_ALWAYS_SOFTWARE=1) ;;
        gpu|screen)
            local vglrun=${VF_VGLRUN:-}
            [[ -n $vglrun ]] || vglrun=$(command -v vglrun || true)
            [[ -n $vglrun && -x $vglrun ]] ||
                vf_die 'GPU input runs require VirtualGL; install vglrun or set VF_VGLRUN'
            graphics_command=("$vglrun" -d "${VF_VGL_DISPLAY:-egl}" -c proxy)
            ;;
        *) vf_die "driven runs need software, gpu or screen rendering: $renderer" ;;
    esac
    VF_RUN_RENDERER=$renderer
    width=${screen%%x*}
    height=${screen#*x}; height=${height%%x*}
    VF_RUN_SIZE="${width}x${height}"
    vf_default_speed 1
    rm -f -- "$VF_WRITE_DIR/infolog.txt"
    vf_sanitizer_env
    vf_config_set Fullscreen 0
    vf_config_set XResolutionWindowed "$width"
    vf_config_set YResolutionWindowed "$height"
    vf_config_set WindowPosX 0
    vf_config_set WindowPosY 0

    for n in $(seq 90 189); do
        [[ -e /tmp/.X11-unix/X$n || -e /tmp/.X$n-lock ]] || { display=:$n; break; }
    done
    [[ -n $display ]] || vf_die 'no free X display between :90 and :189'
    Xvfb "$display" -screen 0 "$screen" +extension GLX >/dev/null 2>&1 &
    xvfb_pid=$!
    # An interrupted suite still takes its display down (and keeps the
    # cleanup an EXIT trap set before).
    local previous_exit
    previous_exit=$(trap -p EXIT | sed -E "s/^trap -- '(.*)' EXIT$/\1/")
    # shellcheck disable=SC2064
    trap "kill $xvfb_pid 2>/dev/null || true; ${previous_exit:-:}" EXIT
    for n in $(seq 1 50); do
        [[ -e /tmp/.X11-unix/X${display#:} ]] && break
        sleep 0.1
    done

    env -u LIBGL_ALWAYS_SOFTWARE "${graphics_env[@]}" SDL_VIDEODRIVER=x11 WAYLAND_DISPLAY= DISPLAY=$display \
        timeout --foreground --kill-after=5s --signal=TERM "${seconds}s" "${graphics_command[@]}" "$engine" --window \
        --write-dir "$VF_WRITE_DIR" --isolation --isolation-dir "$VF_ISOLATION" \
        --config "$VF_CONFIG_FILE" "$VF_START_FILE" >"$VF_WRITE_DIR/stdout.txt" 2>&1 &
    engine_pid=$!

    set +e
    DISPLAY=$display VF_X_LOG="$VF_WRITE_DIR/stdout.txt" VF_X_ENGINE_PID=$engine_pid "$driver"
    status=$?
    if kill -0 "$engine_pid" 2>/dev/null; then
        pkill -TERM -P "$engine_pid" 2>/dev/null
        kill -TERM "$engine_pid" 2>/dev/null
    fi
    wait "$engine_pid"
    VF_ENGINE_STATUS=$?
    kill "$xvfb_pid" 2>/dev/null
    wait "$xvfb_pid" 2>/dev/null
    set -e
    local actual
    actual=$(grep -m1 -oE 'GL renderer : .*' "$VF_WRITE_DIR/stdout.txt" | sed 's/GL renderer : //' || true)
    printf 'renderer: %s (%s)\n' "$renderer" "${actual:-unknown}"
    if [[ $renderer != software ]]; then
        [[ -n $actual ]] || vf_die 'GPU input run did not report its renderer'
        if [[ ${actual,,} =~ llvmpipe|softpipe|swrast|swiftshader|software\ rasterizer ]]; then
            vf_die "GPU input run selected a software renderer: $actual"
        fi
    fi
    vf_check_leaks
    return "$status"
}

# Input for vf_run_driven drivers.  Keyboard input reaches the window under
# the pointer: there is no window manager, and xdotool's windowfocus leaves
# the engine deaf to keys, so never call it.
#
# vf_x_wait PATTERN [SECONDS]: wait for a log line matching PATTERN (ERE)
# after the line the previous wait matched, and put it in VF_X_MATCH.  Fails
# after SECONDS (default 60).  Call it directly, not in $( ): it remembers
# where it is in the log.
VF_X_LINE=0
VF_X_MATCH=''
vf_x_wait() {
    local pattern=${1:?pattern} seconds=${2:-60} match deadline
    deadline=$((SECONDS + seconds))
    while ((SECONDS < deadline)); do
        match=$(grep -a -n -E -- "$pattern" "$VF_X_LOG" 2>/dev/null |
            awk -F: -v from="$VF_X_LINE" '$1 > from { print; exit }')
        if [[ -n $match ]]; then
            VF_X_LINE=${match%%:*}
            VF_X_MATCH=${match#*:}
            return 0
        fi
        if [[ -n ${VF_X_ENGINE_PID:-} ]] && ! kill -0 "$VF_X_ENGINE_PID" 2>/dev/null; then
            return 1
        fi
        sleep 0.2
    done
    return 1
}

# vf_x_hold KEY SECONDS / vf_x_tap KEY: a key held down, or a short press
# (the game polls input once per frame, so a press needs a few frames).
vf_x_hold() {
    xdotool keydown "${1:?key}"
    sleep "${2:?seconds}"
    xdotool keyup "$1"
}

vf_x_tap() {
    vf_x_hold "${1:?key}" 0.15
}

# vf_x_button X Y BUTTON SECONDS: move the pointer to X,Y and hold a mouse
# button there.
vf_x_button() {
    xdotool mousemove "${1:?x}" "${2:?y}"
    sleep 0.2
    xdotool mousedown "${3:?button}"
    sleep "${4:?seconds}"
    xdotool mouseup "$3"
}
