#!/usr/bin/env bash
# Run logs, assertions, screenshots, provenance and goldens. Sourced by common.sh.

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

vf_log() {
    cat "$VF_WRITE_DIR/stdout.txt" "$VF_WRITE_DIR/infolog.txt" 2>/dev/null
}

vf_save_logs() {
    cp -f "$VF_WRITE_DIR/stdout.txt" "$VF_OUT_DIR/last.stdout.txt" 2>/dev/null || true
    cp -f "$VF_WRITE_DIR/infolog.txt" "$VF_OUT_DIR/last.infolog.txt" 2>/dev/null || true
    vf_log >"$VF_OUT_DIR/last.combined.txt" 2>/dev/null || true
    printf 'logs: %s\n' "$VF_OUT_DIR/last.combined.txt"
    vf_forbid '\b(Error|Warning):' 'the engine reported an error or warning'
    if [[ ${VF_RUN_RENDERER:-} == gpu ]]; then
        local renderer size
        renderer=$(grep -m1 -oE 'GL renderer : .*' "$VF_OUT_DIR/last.combined.txt" | sed 's/GL renderer : //' || true)
        [[ -n $renderer ]] || vf_die 'offscreen GPU rendering did not initialize'
        if grep -qiE 'llvmpipe|softpipe|swrast|SwiftShader|Software Rasterizer' <<<"$renderer"; then
            vf_die "offscreen GPU rendering selected a software renderer: $renderer"
        fi
        size=$(sed -nE 's/.*display-mode set to ([0-9]+x[0-9]+)x.*/\1/p' "$VF_OUT_DIR/last.combined.txt" | head -1)
        [[ $size == "$VF_RUN_SIZE" ]] || vf_die "offscreen drawable is $size; requested $VF_RUN_SIZE (update the engine's offscreen sizing support)"
    fi
}

# vf_count_log: the one log to count or list lines in.  last.combined.txt is
# stdout plus the infolog, and the engine writes every line to both, so
# counting in it doubles everything; it is only for vf_require/vf_forbid.
# The infolog is complete after a clean exit.  spring-headless only flushes it
# on a clean exit, so after a timeout or crash use stdout instead.
vf_count_log() {
    if [[ ${VF_ENGINE_STATUS:-0} -eq 0 && -s $VF_OUT_DIR/last.infolog.txt ]]; then
        printf '%s\n' "$VF_OUT_DIR/last.infolog.txt"
    else
        printf '%s\n' "$VF_OUT_DIR/last.stdout.txt"
    fi
}

vf_summary() {
    local log
    log=$(vf_count_log)
    [[ -f $log ]] || return 0
    printf 'Errors: %s  Warnings: %s\n' \
        "$(grep -c -E '\bError:' "$log" || true)" \
        "$(grep -c -E '\bWarning:' "$log" || true)"
}

vf_count() {
    grep -c -- "${1:?pattern}" "$(vf_count_log)" 2>/dev/null || true
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

# vf_forbid_runtime_failures [WHAT]: no Wasm trap, callin error, panic, Lua
# error or crash in the run's log (lib/failures.sh).  Every suite calls it.
vf_forbid_runtime_failures() {
    vf_forbid "$RUNTIME_FAILURE_PATTERN" "${1:-the run} contains a runtime failure"
}

# vf_require_clean_exit: the engine must have exited with status 0.  Headless
# suites end themselves with quitforce (vf_quit_when), so a timeout (124)
# means the run never finished, and anything else is a crash.
vf_require_clean_exit() {
    case $VF_ENGINE_STATUS in
        0) return 0 ;;
        124) vf_die "the engine was stopped by the timeout (status 124) before the suite ended it; read $VF_OUT_DIR/last.stdout.txt" ;;
        *) vf_die "the engine exited with status $VF_ENGINE_STATUS (crash or abnormal exit); read $VF_OUT_DIR/last.stdout.txt" ;;
    esac
}

# vf_require_exit_or_timeout: status 0, or 124 when the timeout ended the run.
# Visual scenarios that don't quit themselves (Area 17, TTLD) always end by
# the timeout; for those, completion is proven by the required markers and
# screenshot counts, not by the exit status.  Any other status (a crash, a
# signal, xvfb failing to start) fails.
vf_require_exit_or_timeout() {
    [[ $VF_ENGINE_STATUS -eq 124 ]] && return 0
    vf_require_clean_exit
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
# Only a directory that is itself the top of a git checkout gets a commit: a
# plain folder inside another repository (build/maps/, or anything under the
# gitignored spring-linux/) would otherwise report that repository's HEAD.
vf_source_line() {
    local label=$1 path=$2 top rev dirty
    if [[ -d $path ]] && top=$(git -C "$path" rev-parse --show-toplevel 2>/dev/null) &&
        [[ $(readlink -f "$top") == "$(readlink -f "$path")" ]]; then
        rev=$(git -C "$path" rev-parse HEAD)
        dirty=$(git -C "$path" status --porcelain --untracked-files=no | wc -l)
        printf '%-10s %s  %s %s%s\n' "$label" "${path#"$PROJECT_ROOT"/}" \
            "$(git -C "$path" rev-parse --abbrev-ref HEAD)" "$rev" \
            "$([[ $dirty -gt 0 ]] && echo "  +$dirty uncommitted files")"
    elif [[ -f $path ]]; then
        printf '%-10s %s  sha1 %s\n' "$label" "${path#"$PROJECT_ROOT"/}" "$(sha1sum "$path" | cut -d' ' -f1)"
    else
        printf '%-10s %s  (not version-controlled)\n' "$label" "${path#"$PROJECT_ROOT"/}"
    fi
}

# vf_crates_line: where the shared springcabal crates came from.  With the
# [patch] that setup-dev-engine writes into .cargo/config.toml, the local
# springcabal-rs checkout; otherwise the git revision in each game's Cargo.lock.
vf_crates_line() {
    local checkout="$PROJECT_ROOT/springcabal-rs"
    if [[ -d $checkout ]] && grep -qs 'springcabal-rs' "$PROJECT_ROOT/.cargo/config.toml"; then
        vf_source_line "springcabal" "$checkout"
    else
        printf '%-10s %s\n' "springcabal" "git dependency (revision in the game's wasm-src/Cargo.lock)"
    fi
}

# vf_engine_version: the version string of the rendering engine binary.
vf_engine_version() {
    local bin=${SPRING_ENGINE_BIN:-$ENGINE_INSTALL/spring}
    [[ -x $bin ]] || { printf 'unknown (no %s)\n' "$bin"; return; }
    timeout 20 "$bin" --version 2>/dev/null | grep -m1 -E 'version' || printf 'unknown\n'
}

# Renderer identity of the last run, as "key value" lines (the format of the
# gallery's renderer.txt):
#   backend      software | gpu | screen (VF_RENDERER)
#   gl_renderer  the GL renderer string: the GPU, or llvmpipe and its LLVM
#   gl_version   the GL version string, which names the driver
# Pixels are only compared against goldens from the same backend, GPU and
# driver; a different one skips the pixel checks with a message.
vf_renderer_info() {
    local log="$VF_WRITE_DIR/stdout.txt"
    printf 'backend %s\n' "${VF_RUN_RENDERER:-$(vf_renderer)}"
    printf 'gl_renderer %s\n' "$(grep -m1 -oE 'GL renderer : .*' "$log" 2>/dev/null | sed 's/GL renderer : //')"
    printf 'gl_version %s\n' "$(grep -m1 -oE 'GL version  : .*' "$log" 2>/dev/null | sed 's/GL version  : //')"
}

# vf_recorded_renderer DIR: the renderer info a golden directory was recorded
# with: DIR/renderer.txt, else the renderer/gpu/gl lines of DIR/PROVENANCE.txt
# (goldens recorded before renderer.txt existed).  Prints nothing if neither.
vf_recorded_renderer() {
    local dir=${1:?golden dir}
    if [[ -s $dir/renderer.txt ]]; then
        cat "$dir/renderer.txt"
    elif [[ -s $dir/PROVENANCE.txt ]]; then
        awk '$1 == "renderer" { $1 = ""; print "backend" $0 }
             $1 == "gpu"      { $1 = ""; print "gl_renderer" $0 }
             $1 == "gl"       { $1 = ""; print "gl_version" $0 }' "$dir/PROVENANCE.txt"
    fi
}

# vf_renderer_matches DIR: whether the last run's renderer is the one the
# goldens in DIR were recorded with.  On a mismatch, prints both and returns 1.
# No record at all counts as a match.
vf_renderer_matches() {
    local dir=${1:?golden dir} recorded current
    recorded=$(vf_recorded_renderer "$dir")
    [[ -n $recorded ]] || return 0
    current=$(vf_renderer_info)
    [[ $recorded == "$current" ]] && return 0
    printf '  WARNING  the goldens in %s were recorded on another renderer; pixels cannot be compared.\n' \
        "${dir#"$PROJECT_ROOT"/}"
    printf '           recorded: %s\n' "$(tr '\n' ';' <<<"$recorded" | sed 's/;$//; s/;/; /g')"
    printf '           this run: %s\n' "$(tr '\n' ';' <<<"$current" | sed 's/;$//; s/;/; /g')"
    printf '           Re-record them on this renderer (just update-goldens), or match VF_RENDERER.\n'
    return 1
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
# from, so a recording can be reproduced or explained later.  The engine line
# is the binary's own version string; "engine src" is the spring-bar checkout,
# whose working tree also provides the spring crates.  Uses the log of the last
# run in $VF_WRITE_DIR for the logged version and the GPU.
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
        vf_crates_line
        printf '%-10s %s  %s\n' "engine" "${ENGINE_INSTALL#"$PROJECT_ROOT"/}" "$(vf_engine_version)"
        [[ -d $ENGINE_ROOT/.git ]] && vf_source_line "engine src" "$ENGINE_ROOT"
        printf '%-10s %s\n' "version" "$(grep -m1 -oE 'Spring Engine Version: .*|Recoil .*version.*' "$log" | head -1)"
        printf '%-10s %s\n' "renderer" "${VF_RUN_RENDERER:-$(vf_renderer)}"
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
        vf_renderer_info >"$FIXTURES_DIR/$game/goldens/renderer.txt"
        return 0
    fi
    if [[ ! -f $golden ]]; then
        printf '  MISSING  %s (run with VF_UPDATE_GOLDENS=1 to record it)\n' "$name"
        GOLDEN_FAILURES=$((GOLDEN_FAILURES + 1))
        return 0
    fi
    if ! vf_golden_renderer_ok "$game"; then
        if [[ ${VF_ALLOW_RENDERER_MISMATCH:-0} == 1 ]]; then
            printf '  SKIP     %s (recorded on another renderer, see above)\n' "$name"
        else
            printf '  FAIL     %s (recorded on another renderer, see above; VF_ALLOW_RENDERER_MISMATCH=1 skips it)\n' "$name"
            GOLDEN_FAILURES=$((GOLDEN_FAILURES + 1))
        fi
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

# vf_golden_renderer_ok GAME: vf_renderer_matches for the game's scenario
# goldens, checked (and explained) once per run.
VF_GOLDEN_RENDERER_OK=''
vf_golden_renderer_ok() {
    if [[ -z $VF_GOLDEN_RENDERER_OK ]]; then
        VF_GOLDEN_RENDERER_OK=1
        vf_renderer_matches "$FIXTURES_DIR/${1:?game}/goldens" || VF_GOLDEN_RENDERER_OK=0
    fi
    [[ $VF_GOLDEN_RENDERER_OK == 1 ]]
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
