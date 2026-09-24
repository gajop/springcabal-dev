#!/usr/bin/env bash

set -euo pipefail

VERIFICATION_ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$VERIFICATION_ROOT/.." && pwd)
ENGINE_ROOT=${SPRING_BAR_DIR:-$(dirname "$PROJECT_ROOT")/spring-bar}
# Same lookup order as run-wasm.sh: SPRING_ENGINE_DIR, the spring-bar build,
# then the release fetched by setup.sh.
ENGINE_INSTALL=${SPRING_ENGINE_DIR:-$ENGINE_ROOT/build-amd64-linux/install}
if [[ -z ${SPRING_ENGINE_DIR:-} && ! -x $ENGINE_INSTALL/spring && -x $PROJECT_ROOT/engine/current/spring ]]; then
    ENGINE_INSTALL="$PROJECT_ROOT/engine/current"
fi

# VF_GAMES_DIR points suites at other game checkouts (worktrees on a branch).
GAMES_DIR=${VF_GAMES_DIR:-$PROJECT_ROOT/spring-linux/games}
MAPS_DIR="$PROJECT_ROOT/spring-linux/maps"
FIXTURES_DIR="$VERIFICATION_ROOT/fixtures"
SHARED_FONTCACHE="$VERIFICATION_ROOT/cache/fontcache"

LAUNCH_DIR="$PROJECT_ROOT/launch"
# Every run uses the settings players get: the release profile that
# release/package.sh ships, plus the menu's per-game overrides (vf_graphics).
DEFAULT_CONFIG="$LAUNCH_DIR/springsettings.cfg"
VISUAL_CONFIG="$DEFAULT_CONFIG"
BUILD_CACHE="$VERIFICATION_ROOT/cache/target"
GOLDEN_FAILURES=0

VF_TEST_ROOT=""
VF_ISOLATION=""
VF_WRITE_DIR=""
VF_START_FILE=""
VF_CONFIG_FILE=""
VF_OUT_DIR=""
VF_ENGINE_STATUS=0
VF_BUILD_OUT=""

vf_die() {
    printf '%s\n' "$*" >&2
    exit 1
}

vf_note() {
    printf '\n=== %s ===\n' "$*"
}

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

vf_workspace() {
    local name=${1:?name} kind=${2:-temp}

    VF_OUT_DIR="$VERIFICATION_ROOT/out/$name"
    mkdir -p "$VF_OUT_DIR"

    if [[ $kind == stable ]]; then
        VF_TEST_ROOT="$VF_OUT_DIR/run"
    else
        VF_TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/$name-verify.XXXXXX")
    fi
    VF_ISOLATION="$VF_TEST_ROOT/isolation"
    VF_WRITE_DIR="$VF_TEST_ROOT/write"

    rm -rf -- "$VF_ISOLATION/games" "$VF_ISOLATION/maps"
    mkdir -p "$VF_ISOLATION/games" "$VF_ISOLATION/maps" \
        "$VF_WRITE_DIR/screenshots" "$VF_WRITE_DIR/cache"

    vf_share_fontcache
    vf_link_engine_data
}

vf_share_fontcache() {
    mkdir -p "$SHARED_FONTCACHE"
    rm -rf -- "$VF_WRITE_DIR/fontcache"
    ln -sfn "$SHARED_FONTCACHE" "$VF_WRITE_DIR/fontcache"
}

# Suites never modify a checkout under spring-linux/: anything that needs test
# modules, probe gadgets or edited files gets a private copy in the isolation
# view.  The checkout is what release/package.sh ships.
vf_stage_game() {
    local dir=${1:?game dir} staged
    VF_GAME_DIR=$dir
    staged="$VF_ISOLATION/games/$(basename "$dir")"
    rm -rf -- "$staged"
    mkdir -p "$staged"
    (cd "$dir" && tar --exclude=./wasm-src --exclude=./target --exclude=./.git -cf - .) | (cd "$staged" && tar -xf -)
    printf '%s\n' "$staged"
}

# vf_install_modules STAGED CRATE:ARCHIVE_PATH...
# Copies modules from the last vf_build into a staged game copy.
vf_install_modules() {
    local staged=${1:?staged game} pair crate dest
    shift
    [[ -n $VF_BUILD_OUT ]] || vf_die 'vf_install_modules: call vf_build first'
    [[ $staged == "$VF_ISOLATION"/* ]] || vf_die "refusing to install modules outside the isolation view: $staged"
    for pair in "$@"; do
        crate=${pair%%:*}
        dest=${pair#*:}
        [[ -s "$VF_BUILD_OUT/$crate.wasm" ]] || vf_die "missing build artifact: $crate.wasm"
        cp "$VF_BUILD_OUT/$crate.wasm" "$staged/$dest"
    done
}

vf_write_settings() {
    cat >"$VF_WRITE_DIR/springsettings.cfg"
}

# `compare` exits non-zero whenever the images differ at all, so its status says
# nothing about success and must not reach `set -o pipefail`. A genuine failure
# (a missing or mismatched image) prints no metric, and the empty result fails
# the caller's tolerance check via vf_within's default.
vf_rmse() {
    compare -metric RMSE "${1:?a}" "${2:?b}" "${3:-null:}" 2>&1 |
        grep -oE '\(([0-9.]+(e[-+]?[0-9]+)?)\)' | tr -d '()' || true
}

vf_within() {
    awk -v value="${1:-1}" -v limit="${2:?limit}" 'BEGIN { exit !(value * 100 <= limit) }'
}

vf_percent() {
    awk -v value="${1:-1}" 'BEGIN { printf "%.1f", value * 100 }'
}

# vf_cleanup_on_exit: remove the temporary workspace when the suite ends.
# Only EXIT runs the cleanup.  INT and TERM just exit (130/143), which runs
# the EXIT trap once; a handler on INT itself would let the script continue
# after Ctrl+C and then clean up a second time on exit.
vf_cleanup_on_exit() {
    trap 'vf_keep_workspace_unless' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
}

vf_keep_workspace_unless() {
    local keep=${KEEP_TEST_ARTIFACTS:-0}
    [[ $keep == 1 ]] && return 0
    [[ $VF_TEST_ROOT == /tmp/* || $VF_TEST_ROOT == "${TMPDIR:-/tmp}"/* ]] || return 0
    rm -rf -- "$VF_TEST_ROOT"
}

vf_link_engine_data() {
    ln -sfn "$ENGINE_INSTALL/base" "$VF_ISOLATION/base"
    ln -sfn "$ENGINE_INSTALL/fonts" "$VF_ISOLATION/fonts"

    if [[ -d "$ENGINE_INSTALL/AI" ]]; then
        ln -sfn "$ENGINE_INSTALL/AI" "$VF_ISOLATION/AI"
    elif [[ -d "$PROJECT_ROOT/spring-linux/AI" ]]; then
        ln -sfn "$PROJECT_ROOT/spring-linux/AI" "$VF_ISOLATION/AI"
    fi
    [[ -d "$PROJECT_ROOT/spring-linux/LuaUI" ]] &&
        ln -sfn "$PROJECT_ROOT/spring-linux/LuaUI" "$VF_ISOLATION/LuaUI"
    return 0
}

vf_link_game() {
    local dir=${1:?game dir}
    [[ -e $dir ]] || vf_die "game archive not found: $dir"
    [[ $dir == "$VF_ISOLATION"/* ]] || VF_GAME_DIR=$dir
    [[ $dir == "$VF_ISOLATION"/* ]] && return 0
    ln -sfn "$dir" "$VF_ISOLATION/games/$(basename "$dir")"
}

vf_link_map() {
    local path=${1:?map path}; shift
    VF_MAP=$path
    [[ -e $path ]] || vf_die "map archive not found: $path"
    ln -sfn "$path" "$VF_ISOLATION/maps/$(basename "$path")"
    local alias
    for alias in "$@"; do
        ln -sfn "$path" "$VF_ISOLATION/maps/$alias"
    done
}

vf_start_file() {
    local fixture=${1:?start fixture} minspeed=${2:-} maxspeed=${3:-}
    [[ -f $fixture ]] || vf_die "start script not found: $fixture"

    VF_START_FILE="$VF_TEST_ROOT/start.txt"
    cp "$fixture" "$VF_START_FILE"
    vf_random_host_port
    [[ -n $minspeed ]] && sed -E -i "s/minspeed=[^;]+;/minspeed=$minspeed;/" "$VF_START_FILE"
    [[ -n $maxspeed ]] && sed -E -i "s/maxspeed=[^;]+;/maxspeed=$maxspeed;/" "$VF_START_FILE"
    return 0
}

vf_start_inline() {
    VF_START_FILE="$VF_TEST_ROOT/start.txt"
    cat >"$VF_START_FILE"
    vf_random_host_port
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
    engine=$(vf_engine_bin headless)
    vf_sanitizer_env
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
#   gpu       the real GPU through SDL's offscreen video driver (EGL, no
#             window): invisible, but SDL's offscreen display is 1024x768 and
#             the engine clamps its window to it, so at most 1024x736
#   screen    a real window on $DISPLAY: any size, takes over the screen
# Goldens record the renderer they were made with (see lib/gallery.py).
vf_renderer() {
    printf '%s\n' "${VF_RENDERER:-${VF_DEFAULT_RENDERER:-software}}"
}

vf_run_visual() {
    local seconds=${1:?seconds} screen=${2:-1280x720x24} engine renderer width height
    engine=$(vf_engine_bin visual)
    renderer=$(vf_renderer)
    width=${screen%%x*}
    height=${screen#*x}; height=${height%%x*}
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
            if (( width > 1024 || height > 736 )); then
                vf_die "the gpu renderer is limited to 1024x736 (SDL offscreen display); this run needs ${width}x${height}. Use VF_RENDERER=screen or software."
            fi
            vf_config_set Fullscreen 0
            vf_config_set WindowBorderless 1
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
    actual=$(grep -m1 -oE 'GL renderer : .*' "$VF_WRITE_DIR/stdout.txt" | sed 's/GL renderer : //')
    printf 'renderer: %s (%s)\n' "$renderer" "${actual:-unknown}"
    vf_check_leaks
    return 0
}

# vf_build SOURCE_ROOT [FEATURES]
# fmt + clippy + build into verification/cache/target/<game>, never into the
# checkout's own target/ (whose output `just copy` installs).  Sets VF_BUILD_OUT.
vf_build() {
    local source_root=${1:?wasm-src} features=${2:-} game target
    [[ -d $source_root ]] || vf_die "wasm source not found: $source_root"
    game=$(basename "$(dirname "$source_root")")
    target="$BUILD_CACHE/$game"
    local -a feature_args=()
    [[ -n $features ]] && feature_args=(--features "$features")
    (
        cd "$source_root"
        cargo fmt --all -- --check
        cargo clippy --workspace "${feature_args[@]}" --target wasm32-unknown-unknown \
            --release --target-dir "$target" -- -D warnings
        cargo build --workspace "${feature_args[@]}" --target wasm32-unknown-unknown \
            --release --target-dir "$target"
    ) || vf_die "build failed: $source_root ${features:+(features: $features)}"
    VF_BUILD_OUT="$target/wasm32-unknown-unknown/release"
}

vf_log() {
    cat "$VF_WRITE_DIR/stdout.txt" "$VF_WRITE_DIR/infolog.txt" 2>/dev/null
}

vf_save_logs() {
    cp -f "$VF_WRITE_DIR/stdout.txt" "$VF_OUT_DIR/last.stdout.txt" 2>/dev/null || true
    cp -f "$VF_WRITE_DIR/infolog.txt" "$VF_OUT_DIR/last.infolog.txt" 2>/dev/null || true
    vf_log >"$VF_OUT_DIR/last.combined.txt" 2>/dev/null || true
    printf 'logs: %s\n' "$VF_OUT_DIR/last.combined.txt"
}

vf_summary() {
    local log="$VF_OUT_DIR/last.combined.txt"
    [[ -f $log ]] || return 0
    printf 'Errors: %s  Warnings: %s\n' \
        "$(grep -c -E '\bError:' "$log" || true)" \
        "$(grep -c -E '\bWarning:' "$log" || true)"
}

vf_count() {
    grep -c -- "${1:?pattern}" "$VF_OUT_DIR/last.combined.txt" 2>/dev/null || true
}

vf_require() {
    local pattern=${1:?pattern} message=${2:-"expected marker not found: $1"}
    grep -q -E -- "$pattern" "$VF_OUT_DIR/last.combined.txt" 2>/dev/null || vf_die "$message"
}

vf_forbid() {
    local pattern=${1:?pattern} message=${2:-"forbidden pattern present: $1"}
    if grep -q -E -- "$pattern" "$VF_OUT_DIR/last.combined.txt" 2>/dev/null; then
        grep -E -- "$pattern" "$VF_OUT_DIR/last.combined.txt" >&2 || true
        vf_die "$message"
    fi
}

vf_screenshots() {
    find "$VF_WRITE_DIR/screenshots" -maxdepth 1 -name 'screen_*.png' -type f 2>/dev/null | sort
}

vf_require_screenshots() {
    local want=${1:?count} have
    have=$(vf_screenshots | wc -l)
    [[ $have -ge $want ]] || {
        vf_log | tail -40 >&2
        vf_die "captured $have screenshot(s), expected at least $want"
    }
    printf '%s\n' "$have"
}

vf_collect_screenshots() {
    local dest=${1:-$VF_OUT_DIR/screens}
    rm -rf -- "$dest"
    mkdir -p "$dest"
    local shot
    while read -r shot; do
        cp "$shot" "$dest/"
    done < <(vf_screenshots)
    printf '%s\n' "$dest"
}

# vf_source_line LABEL PATH: one provenance line for a game/map/engine source.
vf_source_line() {
    local label=$1 path=$2 top rev dirty
    if [[ -d $path ]] && top=$(git -C "$path" rev-parse --show-toplevel 2>/dev/null); then
        rev=$(git -C "$path" rev-parse HEAD)
        dirty=$(git -C "$path" status --porcelain --untracked-files=no | wc -l)
        printf '%-10s %s  %s %s%s\n' "$label" "${path#"$PROJECT_ROOT"/}" \
            "$(git -C "$path" rev-parse --abbrev-ref HEAD)" "$rev" \
            "$([[ $dirty -gt 0 ]] && echo "  +$dirty uncommitted files")"
    elif [[ -f $path ]]; then
        printf '%-10s %s  sha1 %s\n' "$label" "${path#"$PROJECT_ROOT"/}" "$(sha1sum "$path" | cut -d' ' -f1)"
    else
        printf '%-10s %s  (not a git checkout)\n' "$label" "${path#"$PROJECT_ROOT"/}"
    fi
}

# The game and map of the current run, resolved from the isolation view (the
# helpers that set them often run in a subshell).
vf_run_game() {
    local entry
    [[ -n ${VF_GAME_DIR:-} ]] && { printf '%s\n' "$VF_GAME_DIR"; return; }
    for entry in "$VF_ISOLATION"/games/*; do
        [[ -L $entry ]] && { readlink -f "$entry"; return; }
        [[ -d $entry ]] && { printf '%s\n' "$GAMES_DIR/$(basename "$entry")"; return; }
    done
}

vf_run_map() {
    local entry
    [[ -n ${VF_MAP:-} ]] && { printf '%s\n' "$VF_MAP"; return; }
    for entry in "$VF_ISOLATION"/maps/*; do
        readlink -f "$entry"
        return
    done
}

# vf_provenance FILE GAME_DIR MAP [MAP_SOURCE]: records what a golden was made
# from, so a recording can be reproduced or explained later.  Uses the log of
# the last run in $VF_WRITE_DIR for the engine version and GPU.
vf_provenance() {
    local file=${1:?file} game_dir=${2:?game dir} map=${3:?map} map_source=${4:-} log="$VF_WRITE_DIR/stdout.txt"
    mkdir -p "$(dirname "$file")"
    {
        printf 'recorded   %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        vf_source_line "dev repo" "$PROJECT_ROOT"
        vf_source_line "game" "$game_dir"
        vf_source_line "map" "$map"
        [[ -n $map_source ]] && vf_source_line "map from" "$map_source"
        [[ -d $PROJECT_ROOT/patches ]] && [[ $map == *Area17* ]] &&
            printf '%-10s patches/area17-map (in dev repo)\n' "map patch"
        vf_source_line "engine" "$ENGINE_INSTALL"
        [[ -d $ENGINE_ROOT/.git ]] && vf_source_line "engine src" "$ENGINE_ROOT"
        printf '%-10s %s\n' "version" "$(grep -m1 -oE 'Spring Engine Version: .*|Recoil .*version.*' "$log" | head -1)"
        printf '%-10s %s\n' "renderer" "$(vf_renderer)"
        printf '%-10s %s\n' "gpu" "$(grep -m1 -oE 'GL renderer : .*' "$log" | sed 's/GL renderer : //')"
        printf '%-10s %s\n' "gl" "$(grep -m1 -oE 'GL version  : .*' "$log" | sed 's/GL version  : //')"
        printf '%-10s %s\n' "settings" "launch/springsettings.cfg sha1 $(sha1sum "$LAUNCH_DIR/springsettings.cfg" | cut -c1-12)"
    } >"$file"
}

# vf_golden GAME NAME IMAGE [TOLERANCE_PERCENT] [CROP]
# Compares IMAGE with verification/fixtures/GAME/goldens/NAME.png by RMSE.
# Renders are not bit-identical between runs, so the default tolerance only
# catches real regressions (missing terrain, black screen, broken UI).  With
# VF_UPDATE_GOLDENS=1 the image replaces the golden instead.
vf_golden() {
    local game=${1:?game} name=${2:?name} image=${3:?image}
    local tolerance=${4:-${GOLDEN_TOLERANCE:-8}} crop=${5:-}
    local golden="$FIXTURES_DIR/$game/goldens/$name.png"
    local work="$VF_OUT_DIR/goldens" current difference
    [[ -f $image ]] || vf_die "no image for golden $name: $image"
    mkdir -p "$work"
    current="$work/$name.png"
    if [[ -n $crop ]]; then
        convert "$image" -crop "$crop" +repage "$current"
    else
        cp "$image" "$current"
    fi

    if [[ ${VF_UPDATE_GOLDENS:-0} == 1 ]]; then
        mkdir -p "$(dirname "$golden")"
        cp "$current" "$golden"
        printf '  UPDATED  %s\n' "${golden#"$PROJECT_ROOT"/}"
        vf_provenance "$FIXTURES_DIR/$game/goldens/PROVENANCE.txt" "$(vf_run_game)" "$(vf_run_map)"
        return 0
    fi
    if [[ ! -f $golden ]]; then
        printf '  MISSING  %s (run with VF_UPDATE_GOLDENS=1 to record it)\n' "$name"
        GOLDEN_FAILURES=$((GOLDEN_FAILURES + 1))
        return 0
    fi
    difference=$(vf_rmse "$golden" "$current" "$work/$name.diff.png")
    if vf_within "$difference" "$tolerance"; then
        printf '  PASS     %s (%s%% off golden)\n' "$name" "$(vf_percent "$difference")"
    else
        printf '  FAIL     %s (%s%% off golden, limit %s%%; diff: %s)\n' \
            "$name" "$(vf_percent "$difference")" "$tolerance" "$work/$name.diff.png"
        GOLDEN_FAILURES=$((GOLDEN_FAILURES + 1))
    fi
}

# vf_goldens_by_index GAME NAME... : the Nth screenshot of the run is golden NAME.
vf_goldens_by_index() {
    local game=${1:?game} index=0 name
    shift
    local -a shots
    mapfile -t shots < <(vf_screenshots)
    for name in "$@"; do
        [[ $index -lt ${#shots[@]} ]] || vf_die "golden $name: only ${#shots[@]} screenshot(s) captured"
        vf_golden "$game" "$name" "${shots[$index]}"
        index=$((index + 1))
    done
}

# vf_goldens_announced GAME PATTERN
# For games whose scenario logs a line before each capture: PATTERN is an ERE
# whose text after the match start names the shot (e.g. 'Taking screenshot').
# Each announcement is paired with the next file the engine saves, so extra
# screenshots taken elsewhere do not shift the mapping.  Names are slugged:
# "Taking screenshot 2 (spire zap in flight)" -> 02_spire_zap_in_flight.
vf_goldens_announced() {
    local game=${1:?game} pattern=${2:?pattern} name file count=0
    while IFS=$'\t' read -r name file; do
        vf_golden "$game" "$name" "$VF_WRITE_DIR/$file"
        count=$((count + 1))
    done < <(awk -v pattern="$pattern" '
        match($0, pattern) {
            text = substr($0, RSTART + RLENGTH)
            number = text; sub(/^[^0-9]*/, "", number); sub(/[^0-9].*$/, "", number)
            sub(/^[^(]*\(/, "", text); sub(/\).*$/, "", text)
            gsub(/[^A-Za-z0-9]+/, "_", text); sub(/^_/, "", text); sub(/_$/, "", text)
            pending = sprintf("%02d_%s", number, tolower(text))
            next
        }
        pending != "" && match($0, /saving "screenshots\/[^"]+"/) {
            file = substr($0, RSTART + 8, RLENGTH - 9)
            print pending "\t" file
            pending = ""
        }' "$VF_WRITE_DIR/stdout.txt")
    [[ $count -gt 0 ]] || vf_die "no announced screenshots matched: $pattern"
}

vf_goldens_done() {
    [[ $GOLDEN_FAILURES -eq 0 ]] || vf_die "$GOLDEN_FAILURES golden comparison(s) failed"
}
