#!/usr/bin/env bash

set -euo pipefail

VERIFICATION_ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$VERIFICATION_ROOT/.." && pwd)
ENGINE_ROOT=${SPRING_BAR_DIR:-/home/gajop/projects/spring-projects/spring-bar}
ENGINE_INSTALL="$ENGINE_ROOT/build-amd64-linux/install"

GAMES_DIR="$PROJECT_ROOT/spring-linux/games"
MAPS_DIR="$PROJECT_ROOT/spring-linux/maps"
FIXTURES_DIR="$VERIFICATION_ROOT/fixtures"
SHARED_FONTCACHE="$VERIFICATION_ROOT/cache/fontcache"

DEFAULT_CONFIG="$PROJECT_ROOT/wasm-test/spring.conf"
VISUAL_CONFIG="$PROJECT_ROOT/area17-test/spring.conf"

VF_TEST_ROOT=""
VF_ISOLATION=""
VF_WRITE_DIR=""
VF_START_FILE=""
VF_CONFIG_FILE=""
VF_OUT_DIR=""
VF_ENGINE_STATUS=0

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
        [[ -x $candidate ]] || candidate="$PROJECT_ROOT/spring-linux/$name"
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

vf_stage_game() {
    local dir=${1:?game dir} staged
    staged="$VF_ISOLATION/games/$(basename "$dir")"
    rm -rf -- "$staged"
    mkdir -p "$staged"
    (cd "$dir" && tar --exclude=./wasm-src --exclude=./target -cf - .) | (cd "$staged" && tar -xf -)
    printf '%s\n' "$staged"
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
        grep -oE '\(([0-9.]+)\)' | tr -d '()' || true
}

vf_within() {
    awk -v value="${1:-1}" -v limit="${2:?limit}" 'BEGIN { exit !(value * 100 <= limit) }'
}

vf_percent() {
    awk -v value="${1:-1}" 'BEGIN { printf "%.1f", value * 100 }'
}

vf_keep_workspace_unless() {
    local keep=${KEEP_TEST_ARTIFACTS:-0}
    [[ $keep == 1 ]] && return 0
    [[ $VF_TEST_ROOT == /tmp/* || $VF_TEST_ROOT == "${TMPDIR:-/tmp}"/* ]] || return 0
    rm -rf -- "$VF_TEST_ROOT"
}

vf_link_engine_data() {
    local base="$ENGINE_INSTALL/base" fonts="$ENGINE_INSTALL/fonts"
    [[ -d $base ]] || { base="$PROJECT_ROOT/spring-linux/base"; fonts="$PROJECT_ROOT/spring-linux/fonts"; }
    ln -sfn "$base" "$VF_ISOLATION/base"
    ln -sfn "$fonts" "$VF_ISOLATION/fonts"

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
    ln -sfn "$dir" "$VF_ISOLATION/games/$(basename "$dir")"
}

vf_link_map() {
    local path=${1:?map path}; shift
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
    sed -E -i "s/[Hh]ostport=[0-9]+;/hostport=$(shuf -i 20000-60000 -n 1);/" "$VF_START_FILE"
    [[ -n $minspeed ]] && sed -E -i "s/minspeed=[^;]+;/minspeed=$minspeed;/" "$VF_START_FILE"
    [[ -n $maxspeed ]] && sed -E -i "s/maxspeed=[^;]+;/maxspeed=$maxspeed;/" "$VF_START_FILE"
    return 0
}

vf_start_inline() {
    VF_START_FILE="$VF_TEST_ROOT/start.txt"
    cat >"$VF_START_FILE"
    sed -E -i "s/[Hh]ostport=[0-9]+;/hostport=$(shuf -i 20000-60000 -n 1);/" "$VF_START_FILE"
}

vf_config() {
    local fixture=${1:-$DEFAULT_CONFIG}
    [[ -f $fixture ]] || vf_die "config not found: $fixture"
    VF_CONFIG_FILE="$VF_TEST_ROOT/spring.conf"
    cp "$fixture" "$VF_CONFIG_FILE"
    printf '\nInfoConsoleGeometry = 0 0 0 0\nMaxTextureAtlasSizeX = 16384\nMaxTextureAtlasSizeY = 16384\n' \
        >>"$VF_CONFIG_FILE"
    # Verification runs are silent unless VF_SOUND=1.
    [[ ${VF_SOUND:-0} == 1 ]] || printf 'snd_volmaster = 0\n' >>"$VF_CONFIG_FILE"
}

vf_run_headless() {
    local seconds=${1:?seconds} engine
    engine=$(vf_engine_bin headless)
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
    return 0
}

vf_run_visual() {
    local seconds=${1:?seconds} screen=${2:-1280x720x24} engine
    engine=$(vf_engine_bin visual)
    rm -f -- "$VF_WRITE_DIR/infolog.txt"
    rm -rf -- "${VF_WRITE_DIR:?}/screenshots"/*

    set +e
    ASAN_OPTIONS=detect_leaks=0:allocator_may_return_null=1 \
    LIBGL_ALWAYS_SOFTWARE=1 \
    SDL_VIDEODRIVER=x11 \
    WAYLAND_DISPLAY= \
        timeout --signal=TERM "${seconds}s" \
        xvfb-run -a -s "-screen 0 $screen +extension GLX" \
        "$engine" \
        --window \
        --write-dir "$VF_WRITE_DIR" \
        --isolation \
        --isolation-dir "$VF_ISOLATION" \
        --config "$VF_CONFIG_FILE" \
        "$VF_START_FILE" >"$VF_WRITE_DIR/stdout.txt" 2>&1
    VF_ENGINE_STATUS=$?
    set -e
    return 0
}

vf_build() {
    local source_root=${1:?wasm-src} features=${2:-}
    [[ -d $source_root ]] || vf_die "wasm source not found: $source_root"
    (
        cd "$source_root"
        cargo fmt --all -- --check
        if [[ -n $features ]]; then
            cargo clippy --workspace --features "$features" \
                --target wasm32-unknown-unknown --release -- -D warnings
            cargo build --workspace --features "$features" \
                --target wasm32-unknown-unknown --release
        else
            cargo clippy --workspace --target wasm32-unknown-unknown --release -- -D warnings
            cargo build --workspace --target wasm32-unknown-unknown --release
        fi
    )
}

vf_restore_modules() {
    local source_root=${1:?wasm-src}
    (cd "$source_root" && just copy) >/dev/null 2>&1 || true
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
