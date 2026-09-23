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
FIRE_SHARE=60

# Stages the port with e2e modules (in-game cases and the GRAVITAS_SHOT capture).
gravitas_stage() {
    local staged
    vf_build "$SOURCE_ROOT" e2e
    staged=$(vf_stage_game "$GAME_DIR")
    vf_install_modules "$staged" \
        gravitas_rules_wasm:LuaRules/wasm/gravitas-rules.wasm \
        gravitas_ui_wasm:LuaUI/wasm/gravitas-ui.wasm
    vf_link_map "$MAP_DIR"
    vf_start_file "$START_FILE"
}

gravitas_headless() {
    local seconds=${1:-40}
    trap 'vf_keep_workspace_unless' EXIT INT TERM

    vf_workspace gravitas-headless
    vf_link_game "$GAME_DIR"
    vf_link_map "$MAP_DIR"
    vf_start_file "$START_FILE"
    vf_quit_when --frame 900
    vf_config
    vf_run_headless "$seconds"
    vf_save_logs
    vf_summary
}

gravitas_e2e() {
    local seconds=${1:-40} failures=0 cases_failed

    vf_workspace gravitas-e2e
    trap 'vf_keep_workspace_unless' EXIT INT TERM
    gravitas_stage
    vf_write_settings <<'CFG'
UseFontConfigLib = 0
CFG
    vf_quit_when 'E2E summary passed='
    vf_config
    vf_run_headless "$seconds"
    vf_save_logs
    [[ -s "$VF_OUT_DIR/last.combined.txt" ]] || vf_die 'engine produced no output'

    echo 'in-game cases:'
    grep -oE 'E2E case .*' "$VF_OUT_DIR/last.combined.txt" | sed 's/^E2E case /  /' || true
    cases_failed=$(grep -cE 'E2E case .* FAIL' "$VF_OUT_DIR/last.combined.txt" || true)
    failures=$((failures + cases_failed))
    if ! grep -qE 'E2E summary passed=[0-9]+ failed=0' "$VF_OUT_DIR/last.combined.txt"; then
        echo '  FAIL  the suite did not finish with every case passing'
        failures=$((failures + 1))
    fi

    echo 'build:'
    gravitas_check "the shipped rules module carries no test code" \
        gravitas_absent_in_wasm "$GAME_DIR/LuaRules/wasm/gravitas-rules.wasm" 'E2E case'
    gravitas_check "the shipped ui module carries no test code" \
        gravitas_absent_in_wasm "$GAME_DIR/LuaUI/wasm/gravitas-ui.wasm" 'GRAVITAS_SHOT'
    gravitas_check "clippy is clean without the feature" gravitas_clippy_clean
    gravitas_check "clippy is clean with the feature" gravitas_clippy_clean --features e2e

    echo 'engine log:'
    gravitas_check "no lua error" gravitas_absent '(\[LuaRules\]|\[LuaUI\]) Error|attempt to (index|call)'
    gravitas_check "no unit or weapon def warning" gravitas_absent 'Warning: (Unit|Weapon)Defs:'
    gravitas_check "no undefined CEG" gravitas_absent 'CCEG::Load'
    gravitas_check "every model has a primary texture" gravitas_absent 'could not load primary texture'
    gravitas_check "no zero-power unit" gravitas_absent 'has really low power'
    gravitas_check "no re-entered world state" gravitas_absent 'world state re-entered'

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

gravitas_absent_in_wasm() {
    ! strings "$1" | grep -qF "$2"
}

gravitas_clippy_clean() {
    (
        cd "$SOURCE_ROOT"
        cargo clippy --workspace "$@" --target wasm32-unknown-unknown --release \
            --target-dir "$BUILD_CACHE/Gravitas-wasm.sdd" 2>&1 | grep -qE '^(error|warning)'
    ) && return 1
    return 0
}

gravitas_shots() {
    local seconds=${1:-40} shot previous='' checksum
    local -a taken

    command -v xvfb-run >/dev/null 2>&1 || vf_die 'xvfb-run not found'
    vf_workspace gravitas-shots stable
    gravitas_stage
    vf_write_settings <<CFG
Fullscreen = 0
UseFontConfigLib = 0
XResolutionWindowed = 1280
YResolutionWindowed = 720
WindowBorderless = 1
WindowPosX = 0
WindowPosY = 0
GroundDetail = 200
MaxMapDetail = 5
LODScale = 2.0
CFG
    vf_config "$VISUAL_CONFIG"
    vf_run_visual "$seconds"
    vf_save_logs

    # The capture repeats while the engine settles; keep distinct frames only.
    while read -r shot; do
        checksum=$(md5sum "$shot" | cut -d' ' -f1)
        [[ $checksum == "$previous" ]] && continue
        previous=$checksum
        taken+=("$shot")
    done < <(vf_screenshots)
    [[ ${#taken[@]} -eq 1 ]] || vf_die "expected 1 distinct screenshot, got ${#taken[@]}"

    vf_golden gravitas arena "${taken[0]}" "${SHOT_TOLERANCE:-10}"
    gravitas_hud_and_fire "$FIXTURES/goldens/arena.png" "$VF_OUT_DIR/goldens/arena.png"

    echo
    [[ $GRAVITAS_FAILURES -eq 0 ]] || { echo "gravitas shots: $GRAVITAS_FAILURES check(s) need a look"; return 1; }
    vf_goldens_done
    echo '>>> Gravitas shots match golden <<<'
}

gravitas_hud_and_fire() {
    local golden=$1 current=$2 hud hud_percent now want floor
    [[ -f $golden && -f $current ]] || return 0

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

case "${1:-e2e}" in
    headless) gravitas_headless "${2:-}" ;;
    e2e) gravitas_e2e "${2:-}" ;;
    shots) gravitas_shots "${2:-}" ;;
    *) vf_die 'usage: gravitas.sh [e2e|shots|headless] [seconds]' ;;
esac
