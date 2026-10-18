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

gravitas_enable_logs() {
    cat >> "$VF_ISOLATION/games/$(basename "$GAME_DIR")/LuaRules/draw.lua" <<'LUA'
Spring.SetLogSectionFilterLevel("gravitas-wasm", "info")
Spring.SetLogSectionFilterLevel("gravitas-ui", "info")
LUA
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
    gravitas_enable_logs
    vf_config
    vf_run_headless "$seconds"
    vf_save_logs
    vf_require_clean_exit
    vf_summary

    echo 'checks:'
    gravitas_check "the whole level spawns" gravitas_present 'level spawned: ([0-9]+) of \1 units'
    gravitas_check "the HUD loads" gravitas_present 'Gravitas RmlUi HUD initialized'
    gravitas_check "no wasm trap, callin error, panic or crash" gravitas_absent "$RUNTIME_FAILURE_PATTERN"

    echo
    [[ $GRAVITAS_FAILURES -eq 0 ]] || { echo "gravitas headless: $GRAVITAS_FAILURES check(s) failed"; return 1; }
    echo '>>> Gravitas headless passed <<<'
}

gravitas_present() {
    grep -qE "$1" "$VF_OUT_DIR/last.combined.txt"
}

gravitas_e2e() {
    local seconds=${1:-40} failures=0 cases_failed log

    vf_workspace gravitas-e2e
    vf_cleanup_on_exit
    gravitas_stage headless-integration
    vf_quit_when 'E2E summary passed='
    gravitas_enable_logs
    vf_config
    # The input case releases and re-presses jump through UI Update. At the
    # usual 100x test speed both edges can fall between UI polls. Use normal
    # gameplay speed so this end-to-end test observes each input transition.
    vf_default_speed 1
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

    vf_workspace gravitas-shots stable
    gravitas_stage e2e
    vf_quit_when 'E2E summary passed='
    gravitas_enable_logs
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

# play / lua-play: the player's controls through real input, on the WASM port
# or the Lua game: walk, jump with Space, E and the middle button (twice with
# Space), push and pull a crate, push one beyond the gun's range, and leave
# with Ctrl+Q.  fixtures/gravitas/play_observer.lua sets each step up and
# checks it; gravitas_play_driver presses the keys.
PLAY_STEPS=8

gravitas_play() {
    local variant=$1 seconds=${2:-240} staged draw log
    vf_cleanup_on_exit
    if [[ $variant == lua ]]; then
        vf_workspace gravitas-lua-play
        staged=$(vf_stage_game "$GAMES_DIR/Gravitas.sdd")
        # The menu starts the Lua game through the scenario editor.
        vf_link_game "$GAMES_DIR/Scenario-Editor-Gravitas.sdd"
        vf_link_game "$GAMES_DIR/Scenario-Editor-Core.sdd"
        ln -sfn "$PROJECT_ROOT/spring-linux/projects" "$VF_ISOLATION/projects"
    else
        vf_workspace gravitas-play
        staged=$(vf_stage_game "$GAME_DIR")
    fi
    cp "$FIXTURES/play_observer.lua" "$staged/LuaRules/Gadgets/zz_verify_play.lua"
    # The port runs no unsynced gadgets (draw.lua is `return true`); give the
    # observer's unsynced half an entry point of its own.
    draw="$staged/LuaRules/draw.lua"
    if [[ $variant != lua ]]; then
        grep -vE '^[[:space:]]*(--.*)?$' "$draw" | grep -qvE '^[[:space:]]*return true[[:space:]]*$' &&
            vf_die "$draw runs its own unsynced code; add the play observer there"
        cat >"$draw" <<'LUA'
-- Verification entry point: the port runs no unsynced gadgets, so run only
-- the play observer's unsynced half.
gadget = {}
gadgetHandler = { IsSyncedCode = function() return false end }
VFS.Include("LuaRules/Gadgets/zz_verify_play.lua", nil, VFS.ZIP_FIRST)
function GameFrame(n) gadget:GameFrame(n) end
LUA
    fi
    vf_link_map "$MAP_DIR"
    vf_start_file "$(vf_launch_script gravitas "$variant")"
    vf_config "$VISUAL_CONFIG"
    vf_graphics gravitas

    local status=0
    vf_run_driven "$seconds" gravitas_play_driver || status=$?
    vf_save_logs
    log="$VF_OUT_DIR/last.stdout.txt"

    echo 'steps:'
    grep -a -oE '\[vf-play\] (PASS|FAIL) .*' "$log" | sed 's/^\[vf-play\] /  /' || true
    echo 'checks:'
    gravitas_check "every step passed" grep -aqE "\[vf-play\] summary passed=$PLAY_STEPS failed=0" "$log"
    gravitas_check "Ctrl+Q went back to the menu" grep -aq 'user exited to menu' "$log"
    gravitas_check "no wasm trap, callin error, panic or crash" gravitas_absent "$RUNTIME_FAILURE_PATTERN"
    [[ $status -eq 0 ]] || echo "  (the driver stopped early: status $status)"

    echo
    [[ $GRAVITAS_FAILURES -eq 0 ]] || { echo "gravitas $variant play: $GRAVITAS_FAILURES check(s) failed"; return 1; }
    echo ">>> Gravitas $variant play passed <<<"
}

# rules / lua-rules: game rules headless, on the WASM port or the Lua game:
# a crate presses a plate down, a thrown robot takes the game's collision
# damage, and B.O.B fires continuously (fixtures/gravitas/rules_observer.lua).
# Plus a log with no def, effect or texture warning.
RULES_CASES=3

gravitas_rules() {
    local variant=$1 seconds=${2:-120} suite=${3:-rules} staged log prefix=vf-rules expected=$RULES_CASES
    if [[ $suite == bob ]]; then
        prefix=vf-bob
        expected=1
    fi
    vf_cleanup_on_exit
    if [[ $variant == lua ]]; then
        vf_workspace "gravitas-lua-$suite"
        staged=$(vf_stage_game "$GAMES_DIR/Gravitas.sdd")
        vf_link_game "$GAMES_DIR/Scenario-Editor-Gravitas.sdd"
        vf_link_game "$GAMES_DIR/Scenario-Editor-Core.sdd"
        ln -sfn "$PROJECT_ROOT/spring-linux/projects" "$VF_ISOLATION/projects"
    else
        vf_workspace "gravitas-$suite"
        staged=$(vf_stage_game "$GAME_DIR")
    fi
    cp "$FIXTURES/${suite}_observer.lua" "$staged/LuaRules/Gadgets/zz_verify_rules.lua"
    vf_link_map "$MAP_DIR"
    vf_start_file "$(vf_launch_script gravitas "$variant")"
    vf_quit_when "[$prefix] summary"
    vf_config
    vf_run_headless "$seconds"
    vf_save_logs
    vf_require_clean_exit
    log=$(vf_count_log)

    echo 'cases:'
    grep -a -oE "\[$prefix\] (PASS|FAIL) .*" "$log" | sed "s/^\[$prefix\] /  /" || true
    echo 'checks:'
    gravitas_check "every case passed" grep -aqE "\[$prefix\] summary passed=$expected failed=0" "$log"
    gravitas_check "no unit or weapon def warning" gravitas_absent 'Warning: (Unit|Weapon)Defs:|has really low power'
    gravitas_check "no undefined CEG" gravitas_absent 'CCEG::Load'
    gravitas_check "every model has a primary texture" gravitas_absent 'could not load primary texture'
    gravitas_check "no wasm trap, callin error, panic or crash" gravitas_absent "$RUNTIME_FAILURE_PATTERN"

    echo
    [[ $GRAVITAS_FAILURES -eq 0 ]] || { echo "gravitas $variant rules: $GRAVITAS_FAILURES check(s) failed"; return 1; }
    echo ">>> Gravitas $variant rules passed <<<"
}

# Waits for each "[vf-play] go STEP key=KEY x=X y=Y" and plays it.  The
# pointer stays over the window, so key presses reach the game.
gravitas_play_driver() {
    local line step key x y
    xdotool mousemove 640 360
    while vf_x_wait '\[vf-play\] go ' 180; do
        line=$VF_X_MATCH
        step=$(sed -E 's/.*go ([^ ]+) .*/\1/' <<<"$line")
        key=$(sed -E 's/.* key=([^ ]+) .*/\1/' <<<"$line")
        x=$(sed -E 's/.* x=([^ ]+) .*/\1/' <<<"$line")
        y=$(sed -E 's/.* y=([^ ]+)$/\1/' <<<"$line" | tr -d '\r')
        echo "driver: $step ($key at $x,$y)"
        case $key in
            mouse1 | mouse3)
                xdotool mousemove "$x" "$y"
                sleep 0.2
                xdotool mousedown "${key#mouse}"
                sleep 0.7
                # A picture of the shot, for when the step fails.
                import -window root "$VF_OUT_DIR/step-$step.png" 2>/dev/null || true
                sleep 0.8
                xdotool mouseup "${key#mouse}"
                ;;
            mouse2) vf_x_button "$x" "$y" 2 0.15 ;;
            ctrl+q)
                xdotool mousemove 640 360
                vf_x_tap ctrl+q
                vf_x_wait 'user exited to menu' 30
                return
                ;;
            *)
                if [[ $x != - ]]; then
                    xdotool mousemove "$x" "$y"
                    sleep 0.2
                    vf_x_tap "$key"
                else
                    xdotool mousemove 640 360
                    vf_x_hold "$key" 1.5
                fi
                ;;
        esac
    done
    echo 'driver: no next step from the game'
    return 1
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
    play) gravitas_play wasm "${2:-}" ;;
    lua-play) gravitas_play lua "${2:-}" ;;
    rules) gravitas_rules wasm "${2:-}" ;;
    lua-rules) gravitas_rules lua "${2:-}" ;;
    bob) gravitas_rules wasm "${2:-}" bob ;;
    lua-bob) gravitas_rules lua "${2:-}" bob ;;
    *) vf_die 'usage: gravitas.sh [e2e|shots|headless|play|lua-play|rules|lua-rules|bob|lua-bob] [seconds]' ;;
esac
