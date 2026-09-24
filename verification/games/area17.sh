#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

# Golden RMSE limit.  Run-to-run drift measured 0.4-5.5% (2026-09-23); the
# scenario runs in real time, not frame-locked like the galleries.
GOLDEN_TOLERANCE=${GOLDEN_TOLERANCE:-8}

GAME_DIR="$GAMES_DIR/Area17-wasm.sdd"
SOURCE_ROOT="$GAME_DIR/wasm-src"
START_FILE="$(vf_launch_script area17)"
MODULES=(
    area17_rules_wasm:LuaRules/wasm/area17-rules.wasm
    area17_ui_wasm:LuaUI/wasm/area17-ui.wasm
)

# Stages the game with modules built for FEATURES, plus the patched map.
area17_stage() {
    local features=$1 staged
    vf_build "$SOURCE_ROOT" "$features"
    staged=$(vf_stage_game "$GAME_DIR")
    vf_install_modules "$staged" "${MODULES[@]}"
    # The Lua observer and the visual scenario's camera; test-only.
    cp "$FIXTURES_DIR/area17/scenario.lua" "$staged/LuaRules/Gadgets/test_area17_scenario.lua"
    vf_link_map "$("$PROJECT_ROOT/scripts/area17-map.sh" --dir)"
}

# Build hygiene: fmt, clippy, and the installed modules match a fresh build of
# the source, built outside the checkout (see area17_static_target).
area17_static() {
    local reference="$SOURCE_ROOT/target" target pair crate installed fresh

    VF_OUT_DIR="$VERIFICATION_ROOT/out/area17-static"
    mkdir -p "$VF_OUT_DIR"
    target=$(area17_static_target "$reference")
    vf_build "$SOURCE_ROOT" '' "$target"
    for pair in "${MODULES[@]}"; do
        crate=${pair%%:*}
        installed="$GAME_DIR/${pair#*:}"
        fresh="$VF_OUT_DIR/$crate.wasm"
        [[ -s "$VF_BUILD_OUT/$crate.wasm" ]] || vf_die "missing build artifact: $crate.wasm"
        # Name the fresh build's target directory as `just copy` names it.
        FROM=$target TO=$reference perl -0777 -pe 's/\Q$ENV{FROM}\E/$ENV{TO}/g' \
            "$VF_BUILD_OUT/$crate.wasm" | area17_code_only >"$fresh"
        area17_code_only <"$installed" >"$fresh.installed"
        cmp "$fresh" "$fresh.installed" ||
            vf_die "$installed does not match its source; rebuild it with \`just copy\` in $SOURCE_ROOT"
    done

    if grep -rnE --include='*.rs' '\bunsafe\b|align4|to_le_bytes|from_le_bytes|#!\[allow\(clippy::all\)\]' \
        "$SOURCE_ROOT/rules-synced/src" "$SOURCE_ROOT/ui/src"; then
        vf_die 'Area 17 source contains unsafe/ABI-packing/lint-suppression code'
    fi

    local manifest
    for manifest in "$GAME_DIR/LuaRules/wasm/manifest.txt" "$GAME_DIR/LuaUI/wasm/manifest.txt"; do
        [[ $(grep -c '^module(' "$manifest") -eq 1 ]] || vf_die "expected exactly one module in $manifest"
    done

    echo '>>> Area 17 static verification passed <<<'
}

# A wasm module without its custom sections (the name section, producers):
# code, data, types, imports and exports.  ThinLTO suffixes local symbol
# names with a hash of the object file's path (`.llvm.<hash>`), so the name
# section changes with the target directory even when the code does not.
area17_code_only() {
    python3 -c '
import sys
data = sys.stdin.buffer.read()
def leb(i):
    value = shift = 0
    while True:
        byte = data[i]; i += 1
        value |= (byte & 0x7f) << shift; shift += 7
        if byte < 0x80:
            return value, i
out, i = bytearray(data[:8]), 8
while i < len(data):
    size, body = leb(i + 1)
    if data[i] != 0:
        out += data[i:body + size]
    i = body + size
sys.stdout.buffer.write(out)
'
}

# The modules embed their build directory: the spring crate's generated
# bindings live in OUT_DIR, and their panic locations name it.  So a build in
# verification/cache/ can't be byte-identical to the checkout's target/, which
# the suites never write to.  Instead, build into a cache directory whose path
# has exactly the length of REFERENCE, so the only difference is the text of
# that path, which area17_static replaces before comparing.  (Cargo's metadata
# hashes don't depend on the target directory.)
area17_static_target() {
    local reference=${1:?reference} base pad
    for base in "$BUILD_CACHE/Area17-static-" "${TMPDIR:-/tmp}/vf-a17-"; do
        pad=$(( ${#reference} - ${#base} ))
        if (( pad >= 1 )); then
            printf '%s%s\n' "$base" "$(printf '%*s' "$pad" '' | tr ' ' x)"
            return
        fi
    done
    vf_die "no build directory as short as $reference; the static check needs one of equal length"
}

area17_headless() {
    local seconds=${1:-90}
    vf_cleanup_on_exit

    vf_workspace area17-headless
    area17_stage headless-integration
    vf_start_file "$START_FILE" 100.0 100.0
    vf_modoption test_mode 1
    vf_quit_when 'ALL AREA17 RUST INTEGRATION TESTS PASSED' 'ALL AREA17 LUA INTEGRATION TESTS PASSED'
    vf_config
    vf_run_headless "$seconds"
    vf_save_logs
    vf_require_clean_exit

    vf_note 'Area 17 headless run finished'
    printf 'Rust integration assertions passed: %s\n' "$(vf_count '\[Area17-Rust-Test\] ASSERTION PASSED')"
    printf 'Lua gameplay assertions passed:    %s\n' "$(vf_count '\[Area17-Lua-Test\] ASSERTION PASSED')"
    vf_summary

    vf_require 'ALL AREA17 RUST INTEGRATION TESTS PASSED' 'the Rust suite did not complete'
    vf_require 'ALL AREA17 LUA INTEGRATION TESTS PASSED' 'the Lua suite did not complete'
    vf_forbid 'ASSERTION FAILED' 'one or more in-game assertions failed'
    vf_forbid 'Wasm.*(trap|error|Error)|CallIn.*(error|Error)|panic' \
        'the run contains a runtime failure'
    echo '>>> Area 17 headless verification passed <<<'
}

area17_visual() {
    local seconds=${1:-60} shots before after changed

    vf_workspace area17-visual stable
    area17_stage e2e
    vf_start_file "$START_FILE"
    vf_modoption visual_test 1
    vf_config "$VISUAL_CONFIG"
    vf_graphics area17
    vf_run_visual "$seconds"
    vf_save_logs

    vf_require_exit_or_timeout

    shots=$(vf_require_screenshots 3)

    before="$VF_OUT_DIR/crater-before.png"
    after="$VF_OUT_DIR/crater-after.png"
    convert "$(vf_screenshots | head -n 1)" -crop 360x360+460+100 +repage "$before"
    convert "$(vf_screenshots | tail -n 1)" -crop 360x360+460+100 +repage "$after"
    changed=$(compare -metric AE -fuzz 8% "$before" "$after" null: 2>&1 || true)
    [[ $changed =~ ^[0-9]+$ ]] || vf_die "crater comparison produced no pixel count: $changed"
    (( changed >= 1500 )) || vf_die "rendered crater assertion failed (changed pixels: $changed)"

    vf_require '\[Area17-Visual-Test\] Captured visual smoke-test screenshots' \
        'the visual smoke-test scenario did not complete'
    vf_require 'Area 17 RmlUi HUD render pass reached' \
        'the RmlUi render pass was never reached'
    vf_require 'Area 17 test resources granted' \
        "the rules never received the e2e test's resources request"
    vf_require 'Area 17 RmlUi callback: technology toggle' \
        'clicking the technology button never reached its RmlUi callback'
    vf_require 'UI input reached the rules through the engine: four weapons fired, four abilities requested' \
        "the UI's weapon and ability input did not reach the rules"
    vf_forbid 'Wasm.*(trap|error|Error)|CallIn.*(error|Error)|panic|ASSERTION FAILED' \
        'the visual run contains a runtime failure'

    vf_note 'Area 17 goldens'
    vf_goldens_by_index area17 frame_020 frame_080 frame_450
    vf_goldens_done

    printf 'crater changed pixels: %s\n' "$changed"
    printf 'captured %s screenshot(s) in %s\n' "$shots" "$(vf_collect_screenshots)"
    echo '>>> Area 17 visual verification passed <<<'
}

case "${1:-}" in
    static) area17_static ;;
    headless) area17_headless "${2:-}" ;;
    visual) area17_visual "${2:-}" ;;
    all) area17_static; area17_headless; area17_visual ;;
    *) vf_die 'usage: area17.sh [static|headless|visual|all] [seconds]' ;;
esac
