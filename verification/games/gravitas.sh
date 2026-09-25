#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

GAME_DIR="$GAMES_DIR/Gravitas-wasm.sdd"
SOURCE_ROOT="$GAME_DIR/wasm-src"
MAP_DIR="$MAPS_DIR/Gravitas-map.sdd"
FIXTURES="$FIXTURES_DIR/gravitas"
START_FILE="$(vf_launch_script gravitas)"
HUD_REGION=1280x60+0+660
# The health bar inside HUD_REGION tracks live health, so its fill width, its
# colour and its readout all depend on whether the player has been hit by the
# time the shot is taken. Mask it and let this check assert what its name says:
# that the HUD chrome renders identically. Every other element in the region is
# pixel-identical run to run, so the tolerance stays tight.
HUD_LIVE_REGION='460,4 668,56'
HUD_TOLERANCE=1
E2E_TARGET="$BUILD_CACHE/Gravitas-wasm.sdd"
SHIP_TARGET="$BUILD_CACHE/Gravitas-wasm.sdd-ship"
FIRE_SHARE=60

# Stages the port with test modules built for FEATURES: headless-integration
# (the in-game cases) or e2e (the cases, and the screenshot they request).
gravitas_stage() {
    local features=$1 staged
    vf_build "$SOURCE_ROOT" "$features" "$E2E_TARGET"
    staged=$(vf_stage_game "$GAME_DIR")
    vf_install_modules "$staged" \
        gravitas_rules_wasm:LuaRules/wasm/gravitas-rules.wasm \
        gravitas_ui_wasm:LuaUI/wasm/gravitas-ui.wasm
    vf_link_map "$MAP_DIR"
    vf_start_file "$START_FILE"
}

# The shipped modules in the checkout, on the launch script players get, with
# no input for 900 frames.
gravitas_headless() {
    local seconds=${1:-40}
    vf_cleanup_on_exit

    vf_workspace gravitas-headless
    vf_link_game "$GAME_DIR"
    vf_link_map "$MAP_DIR"
    vf_start_file "$START_FILE"
    vf_quit_when --frame 900
    vf_config
    vf_run_headless "$seconds"
    vf_save_logs
    vf_require_clean_exit
    vf_summary

    echo 'checks:'
    gravitas_check "the whole level spawns" gravitas_present 'level spawned: ([0-9]+) of \1 units'
    gravitas_check "the HUD loads" gravitas_present 'Gravitas RmlUi HUD initialized'
    gravitas_check "no wasm trap, callin error, panic or crash" gravitas_absent "$RUNTIME_FAILURE_PATTERN"
    # Headless loads no textures, so the HUD's heart image is the one warning.
    gravitas_check "no warning but the headless HUD image" gravitas_only_known_warnings

    echo
    [[ $GRAVITAS_FAILURES -eq 0 ]] || { echo "gravitas headless: $GRAVITAS_FAILURES check(s) failed"; return 1; }
    echo '>>> Gravitas headless passed <<<'
}

gravitas_present() {
    grep -qE "$1" "$VF_OUT_DIR/last.combined.txt"
}

gravitas_only_known_warnings() {
    ! grep -E 'Warning:' "$VF_OUT_DIR/last.combined.txt" |
        grep -vqE 'Warning: \[RmlUi\] Could not load texture: LuaUI/Images/heart.png'
}

gravitas_e2e() {
    local seconds=${1:-40} failures=0 cases_failed log

    vf_workspace gravitas-e2e
    vf_cleanup_on_exit
    gravitas_stage headless-integration
    vf_quit_when 'E2E summary passed='
    vf_config
    vf_run_headless "$seconds"
    vf_save_logs
    [[ -s "$VF_OUT_DIR/last.combined.txt" ]] || vf_die 'engine produced no output'
    vf_require_clean_exit
    log=$(vf_count_log)

    echo 'in-game cases:'
    grep -oE 'E2E case .*' "$log" | sed 's/^E2E case /  /' || true
    cases_failed=$(grep -cE 'E2E case .* FAIL' "$log" || true)
    failures=$((failures + cases_failed))
    if ! grep -qE 'E2E summary passed=19 failed=0' "$log"; then
        echo '  FAIL  the suite did not finish with every case passing'
        failures=$((failures + 1))
    fi

    echo 'build:'
    gravitas_check "clippy is clean without the feature" gravitas_clippy_clean "$SHIP_TARGET"
    gravitas_check "clippy is clean with the feature" gravitas_clippy_clean "$E2E_TARGET" --features e2e
    gravitas_check "a build without the feature carries no test code" gravitas_ship_has_no_tests

    echo 'engine log:'
    gravitas_check "no lua error" gravitas_absent '(\[LuaRules\]|\[LuaUI\]) Error|attempt to (index|call)'
    gravitas_check "no unit or weapon def warning" gravitas_absent 'Warning: (Unit|Weapon)Defs:'
    gravitas_check "no undefined CEG" gravitas_absent 'CCEG::Load'
    gravitas_check "every model has a primary texture" gravitas_absent 'could not load primary texture'
    gravitas_check "no zero-power unit" gravitas_absent 'has really low power'
    gravitas_check "no wasm trap, callin error, panic or crash" gravitas_absent "$RUNTIME_FAILURE_PATTERN"

    echo
    if [[ ${GRAVITAS_FAILURES:-0} -eq 0 && $failures -eq 0 ]]; then
        echo '>>> Gravitas e2e passed <<<'
        return 0
    fi
    echo "gravitas e2e: $((failures + ${GRAVITAS_FAILURES:-0})) check(s) failed"
    return 1
}

GRAVITAS_FAILURES=0

gravitas_check() {
    local name=$1; shift
    if "$@" >/dev/null 2>&1; then
        echo "  PASS  $name"
    else
        echo "  FAIL  $name"
        GRAVITAS_FAILURES=$((GRAVITAS_FAILURES + 1))
    fi
}

gravitas_absent() {
    ! grep -qE "$1" "$VF_OUT_DIR/last.combined.txt"
}

# The modules a player gets: built from the source without the feature,
# apart from the e2e build, so neither build overwrites the other.
gravitas_ship_has_no_tests() {
    local out="$SHIP_TARGET/wasm32-unknown-unknown/release"
    gravitas_cargo build "$SHIP_TARGET" || return 1
    gravitas_absent_in_wasm "$out/gravitas_rules_wasm.wasm" 'E2E case' &&
        gravitas_absent_in_wasm "$out/gravitas_ui_wasm.wasm" 'gravitas_e2e|shot|'
}

gravitas_absent_in_wasm() {
    [[ -s $1 ]] || return 1
    ! strings "$1" | grep -qF "$2"
}

# Clippy fails on any warning (the workspace denies them, and -D warnings
# repeats it); its exit status is the verdict.
gravitas_clippy_clean() {
    local target=$1; shift
    gravitas_cargo clippy "$target" "$@" -- -D warnings
}

gravitas_cargo() {
    local command=$1 target=$2; shift 2
    (
        cd "$SOURCE_ROOT"
        flock /tmp/springcabal-build.lock cargo "$command" --workspace \
            --target wasm32-unknown-unknown --release --target-dir "$target" "$@"
    )
}

gravitas_shots() {
    local seconds=${1:-40} shot previous='' checksum
    local -a taken

    command -v xvfb-run >/dev/null 2>&1 || vf_die 'xvfb-run not found'
    vf_workspace gravitas-shots stable
    gravitas_stage e2e
    vf_quit_when 'E2E summary passed='
    vf_config "$VISUAL_CONFIG"
    vf_run_visual "$seconds"
    vf_save_logs
    vf_require_clean_exit
    vf_forbid_runtime_failures 'the Gravitas shots run'
    # The scene case checks, on the frame it asks for the shot, that every
    # unit is where its case left it; the golden below only checks the render.
    grep -qE 'E2E case visuals PASS' "$VF_OUT_DIR/last.combined.txt" ||
        vf_die "the arena was not in place for the shot: $(grep -m1 -oE 'E2E case visuals .*' "$VF_OUT_DIR/last.combined.txt" || echo 'no verdict')"

    # The capture repeats while the engine settles; keep distinct frames only.
    while read -r shot; do
        checksum=$(md5sum "$shot" | cut -d' ' -f1)
        [[ $checksum == "$previous" ]] && continue
        previous=$checksum
        taken+=("$shot")
    done < <(vf_screenshots)
    [[ ${#taken[@]} -eq 1 ]] || vf_die "expected 1 distinct screenshot, got ${#taken[@]}"

    # A render check only: run to run the same build renders a few percent
    # apart (fire and spark particles), about what a robot out of place
    # costs, so the scene case above checks where the units are. The limit
    # catches a scene that is missing or broken.
    vf_golden gravitas arena "${taken[0]}" "${SHOT_TOLERANCE:-4}"
    gravitas_hud_and_fire "$FIXTURES/goldens/arena.png" "$VF_OUT_DIR/goldens/arena.png"

    echo
    [[ $GRAVITAS_FAILURES -eq 0 ]] || { echo "gravitas shots: $GRAVITAS_FAILURES check(s) need a look"; return 1; }
    vf_goldens_done
    echo '>>> Gravitas shots match golden <<<'
}

gravitas_hud_and_fire() {
    local golden=$1 current=$2 hud hud_percent now want floor
    [[ -f $golden && -f $current ]] || return 0
    vf_golden_renderer_ok gravitas || return 0

    # `compare` takes no drawing options, so the masked crops are rendered
    # first. See vf_rmse: `compare` signals "images differ" through its status.
    local golden_hud="$VF_OUT_DIR/hud_golden.png" current_hud="$VF_OUT_DIR/hud_current.png"
    convert "$golden" -crop "$HUD_REGION" +repage \
        -fill black -draw "rectangle $HUD_LIVE_REGION" "$golden_hud"
    convert "$current" -crop "$HUD_REGION" +repage \
        -fill black -draw "rectangle $HUD_LIVE_REGION" "$current_hud"
    hud=$(compare -metric RMSE "$golden_hud" "$current_hud" null: 2>&1 |
        grep -oE '\(([0-9.]+)\)' | tr -d '()' || true)
    hud_percent=$(vf_percent "$hud")
    if vf_within "$hud" "$HUD_TOLERANCE"; then
        echo "  PASS  the hud is unchanged (${hud_percent}% off golden)"
    else
        echo "  FAIL  the hud is unchanged (${hud_percent}% off golden, limit ${HUD_TOLERANCE}%)"
        GRAVITAS_FAILURES=$((GRAVITAS_FAILURES + 1))
    fi

    now=$(gravitas_lit "$current")
    want=$(gravitas_lit "$golden")
    floor=$(( ${want:-0} * FIRE_SHARE / 100 ))
    if [[ ${now:-0} -ge $floor && ${want:-0} -gt 0 ]]; then
        echo "  PASS  the fire renders ($now lit pixels, golden has $want)"
    else
        echo "  FAIL  the fire renders (${now:-0} lit pixels, golden has ${want:-0})"
        GRAVITAS_FAILURES=$((GRAVITAS_FAILURES + 1))
    fi
}

gravitas_lit() {
    convert "$1" -fx "(r>0.6 && g<0.6 && g>0.1 && b<0.3) ? 1 : 0" \
        -format "%[fx:int(w*h*mean)]" info: 2>/dev/null
}

case "${1:-}" in
    headless) gravitas_headless "${2:-}" ;;
    e2e) gravitas_e2e "${2:-}" ;;
    shots) gravitas_shots "${2:-}" ;;
    *) vf_die 'usage: gravitas.sh [e2e|shots|headless] [seconds]' ;;
esac
