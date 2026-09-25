#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

# Golden RMSE limit, about twice the run-to-run noise measured on 2026-09-23 (2.6%).
GOLDEN_TOLERANCE=${GOLDEN_TOLERANCE:-5}

GAME_DIR="$GAMES_DIR/Flove-wasm.sdd"
SOURCE_ROOT="$GAME_DIR/wasm-src"
MAP_DIR="$MAPS_DIR/LD34-map.sdd"
MAP_ALIAS='The Grove 0.3.sdd'
FIXTURES="$FIXTURES_DIR/flove"
START_FILE="$(vf_launch_script flove)"
MODULES=(
    flove_rules_wasm:LuaRules/wasm/flove-rules.wasm
    flove_rules_unsynced_wasm:LuaRules/wasm/flove-rules-unsynced.wasm
    flove_ui_wasm:LuaUI/wasm/flove-ui.wasm
)

# Stages the port with headless-integration modules and prints the copy.
flove_stage() {
    local staged
    staged=$(vf_stage_game "$GAME_DIR")
    vf_install_modules "$staged" "${MODULES[@]}"
    vf_link_map "$MAP_DIR" "$MAP_ALIAS"
    printf '%s\n' "$staged"
}

# Starts the scripted scenario (test_scenario.lua).
flove_start() {
    vf_start_file "$START_FILE"
    vf_modoption test_mode 1
    # The rules draw from the engine's synced RNG; pin it so runs repeat.
    vf_start_set FixedRNGSeed 1
}

flove_headless() {
    local seconds=${1:-45}
    vf_cleanup_on_exit

    vf_build "$SOURCE_ROOT" headless-integration
    vf_workspace flove-headless
    flove_stage >/dev/null
    flove_start
    vf_quit_when 'ALL FLOVE RUST INTEGRATION TESTS PASSED' 'ALL FLOVE EXTENDED TEST ASSERTIONS PASSED'
    vf_config
    vf_run_headless "$seconds"
    vf_save_logs
    vf_require_clean_exit

    vf_note 'Flove headless run finished'
    printf 'Rust rules assertions passed:  %s\n' "$(vf_count '\[Flove-Rust-Test\] ASSERTION PASSED')"
    printf 'Rust UI input assertions passed: %s\n' "$(vf_count '\[Flove-UI-Test\] ASSERTION PASSED')"
    printf 'Scenario assertions passed:    %s\n' "$(vf_count '\[Flove-Test\] ASSERTION PASSED')"
    vf_summary

    vf_forbid 'ASSERTION FAILED' 'one or more in-game assertions failed'
    vf_require 'ALL FLOVE RUST INTEGRATION TESTS PASSED' 'the Rust rules suite did not complete'
    vf_require 'ALL FLOVE EXTENDED TEST ASSERTIONS PASSED' 'the scenario suite did not complete'
    vf_forbid_runtime_failures
    echo '>>> Flove headless verification passed <<<'
}

flove_visual() {
    local seconds=${1:-45} shots

    # Only the scenario's commands: the Rust integration suites would restart
    # the round and click through the story between the shots.
    vf_build "$SOURCE_ROOT" e2e
    vf_workspace flove-visual stable
    flove_stage >/dev/null
    flove_start
    vf_config "$VISUAL_CONFIG"
    vf_graphics flove
    vf_run_visual "$seconds"
    vf_save_logs
    # test_scenario.lua ends the run with quitforce.
    vf_require_clean_exit

    shots=$(vf_require_screenshots 3)
    vf_require 'ALL FLOVE EXTENDED TEST ASSERTIONS PASSED' 'the scenario did not complete'
    vf_forbid 'ASSERTION FAILED' 'an in-game assertion failed'
    vf_forbid_runtime_failures 'the Flove visual run'
    # test_scenario.lua announces each capture ("Taking screenshot 2 (spire zap
    # in flight)"); those descriptions name the goldens.
    vf_note 'Flove goldens'
    vf_goldens_announced flove '\[Flove-Test\] Taking screenshot '
    printf 'captured %s screenshot(s) in %s\n' "$shots" "$(vf_collect_screenshots)"
    vf_goldens_done
    echo '>>> Flove visual verification passed <<<'
}

# Renders the original Lua outline gadget and the Rust port in the same staged
# game, then reports the pixel difference.  Informational: the two renderers
# are expected to differ slightly.
flove_outline() {
    local seconds=${1:-60} staged out="$VERIFICATION_ROOT/out/flove-outline"

    vf_build "$SOURCE_ROOT" headless-integration

    vf_note 'Rendering the Lua gadget baseline'
    vf_workspace flove-outline stable
    staged=$(flove_stage)
    cp "$FIXTURES/gadget_gfx_outline.lua" "$staged/LuaRules/Gadgets/gfx_outline.lua"
    cat >"$staged/LuaRules/wasm/manifest.txt" <<'MANIFEST'
module(flove-rules, LuaRules/wasm/flove-rules.wasm, rules-synced, 0, 1.0.0)
MANIFEST
    flove_outline_shot lua_baseline "$seconds"

    vf_note 'Rendering the Rust WASM port'
    vf_workspace flove-outline stable
    flove_stage >/dev/null
    flove_outline_shot rust_wasm "$seconds"

    vf_note 'Comparing'
    compare -metric AE "$out/lua_baseline.png" "$out/rust_wasm.png" "$out/diff.png" 2>&1 || true
    printf '\n%s\n' "baseline: $out/lua_baseline.png"
    printf '%s\n' "port:     $out/rust_wasm.png"
    printf '%s\n' "diff:     $out/diff.png"
}

flove_outline_shot() {
    local tag=${1:?tag} seconds=${2:?seconds} shot
    flove_start
    vf_config "$FIXTURES/spring.conf"
    vf_run_visual "$seconds"

    shot=$(vf_screenshots | head -n 1)
    [[ -n $shot ]] || { vf_save_logs; vf_die "failed to capture $tag.png"; }
    cp "$shot" "$VF_OUT_DIR/$tag.png"
    printf 'captured %s\n' "$VF_OUT_DIR/$tag.png"
}

# Pins every tree's wisps to a stage and captures it, so the effect can be
# inspected without waiting 165 frames per stage.
flove_wisps() {
    local stage=${1:-all} seconds=${2:-90} st

    vf_build "$SOURCE_ROOT" headless-integration
    if [[ $stage != all ]]; then
        flove_wisps_render "$stage" "$seconds"
        return
    fi
    for st in 0 1 2 3; do
        flove_wisps_render "$st" "$seconds"
    done
    printf '\nScreenshots are in %s. Pixel diffs between separate runs are not a\n' \
        "$VERIFICATION_ROOT/out/flove-wisps"
    printf 'reliable signal: two runs of the identical config differ by ~11000 pixels.\n'
}

flove_wisps_render() {
    local stage=${1:?stage} seconds=${2:-90} staged shot wisps

    vf_workspace flove-wisps stable
    staged=$(flove_stage)
    flove_helper 0 "$stage" 9999 15 200 >"$staged/LuaRules/Gadgets/force_wisps.lua"
    flove_start
    vf_config "$FIXTURES/spring.conf"
    vf_run_visual "$seconds"
    vf_save_logs

    vf_require '\[Flove-Wisp-Test\]' 'the wisp helper never ran'
    grep -o '\[Flove-Wisp-Test\][^"]*' "$VF_OUT_DIR/last.combined.txt" | tail -1

    shot=$(vf_screenshots | tail -n 1)
    [[ -n $shot ]] || vf_die 'no screenshot captured'
    cp "$shot" "$VF_OUT_DIR/stage$stage.png"
    printf 'stage %s -> %s\n' "$stage" "$VF_OUT_DIR/stage$stage.png"

    [[ $stage == -1 || $stage == 0 ]] && return 0
    wisps=$(grep -o '\[Flove-Wisp-Test\][^"]*' "$VF_OUT_DIR/last.combined.txt" |
        tail -1 | grep -oE 'wisps=[0-9]+' | cut -d= -f2)
    [[ ${wisps:-0} -gt 0 ]] || vf_die 'the trees carry no wisps at all'
}

flove_helper() {
    sed -e "s/__FORCE_START__/${1:?}/" -e "s/__STAGE__/${2:?}/" -e "s/__COUNT__/${WISP_COUNT:-6}/" \
        -e "s/__SHOT_NATURAL__/${3:?}/" -e "s/__PIN_FROM__/${4:?}/" -e "s/__SHOT_PINNED__/${5:?}/" \
        "$FIXTURES/gadget_force_wisps.lua"
}

# Renders the pre-port Flove.sdd for A/B against the port.
flove_original() {
    local seconds=${1:-200} original="$GAMES_DIR/Flove.sdd" staged shot
    [[ -d $original ]] || vf_die "the pre-port game is not present: $original"

    vf_workspace flove-original stable
    staged=$(vf_stage_game "$original")
    sed 's/__SHOT_FRAME__/600/' "$FIXTURES/gadget_original_boot.lua" \
        >"$staged/LuaRules/Gadgets/original_boot.lua"
    flove_helper 1 -1 9999 9999 9999 >"$staged/LuaRules/Gadgets/force_wisps.lua"
    vf_link_map "$MAP_DIR" "$MAP_ALIAS"

    flove_start
    vf_start_set gametype 'Flove $VERSION'
    vf_config "$FIXTURES/spring.conf"
    vf_run_visual "$seconds"
    vf_save_logs

    vf_require '\[Flove-Wisp-Test\] original' 'the original game never reached the sample frame'
    grep -o '\[Flove-Wisp-Test\][^"]*' "$VF_OUT_DIR/last.combined.txt" | tail -1

    shot=$(vf_screenshots | tail -n 1)
    [[ -n $shot ]] || vf_die 'no screenshot captured'
    cp "$shot" "$VF_OUT_DIR/original.png"
    printf 'original -> %s\n' "$VF_OUT_DIR/original.png"
}

# Lua and Rust unit-script poses: seven mushroom variants run the same
# deterministic probe (fixtures/flove/animation_probe.lua) in the original
# game and in the port built with `animation-trace` (only the unit-script
# gadget, no AI or rounds); skeletons, event frames and every piece matrix of
# frames 3-210 must match within 2e-3.
flove_animation_trace() {
    local seconds=${1:-45}
    vf_cleanup_on_exit
    vf_build "$SOURCE_ROOT" animation-trace
    flove_animation_run lua "$GAMES_DIR/Flove.sdd" 'Flove $VERSION' "$seconds"
    flove_animation_run rust "$GAME_DIR" 'Flove WASM 0.1.0-wasm' "$seconds"
    python3 "$VERIFICATION_ROOT/unit-scripts/compare_flove_animation.py" \
        "$VERIFICATION_ROOT/out/flove-animation-lua/trace.log" \
        "$VERIFICATION_ROOT/out/flove-animation-rust/trace.log"
    echo '>>> Flove Lua/Rust animation trace verification passed <<<'
}

flove_animation_run() {
    local label=$1 source_game=$2 game_name=$3 seconds=$4 staged movement
    vf_workspace "flove-animation-$label"
    staged=$(vf_stage_game "$source_game")
    find "$staged/LuaRules/Gadgets" -maxdepth 1 -type f -name '*.lua' -delete
    if [[ $label == lua ]]; then
        # The engine's Lua unit-script dispatcher, not gameplay logic: keep it
        # so the baseline runs the original unit scripts.
        cp "$source_game/LuaRules/Gadgets/unit_script.lua" "$staged/LuaRules/Gadgets/unit_script.lua"
        # The legacy weapon headers pass a numeric piece ID as a CEG name.
        # Keep the original callins and pose changes, but stop that old effect
        # bug from crashing the baseline, and trace the callins.
        sed -i '/^function CustomEmitter(pieceName, effectName)$/a\	if type(effectName) ~= "string" then return end' \
            "$staged/Scripts/UnitBase.lua"
        sed -i '/^function script.AimWeapon(weaponID, heading, pitch)$/a\	Spring.Echo(string.format("[FloveAnimTrace] LUA_AIM_REQUEST heading=%.6f pitch=%.6f", heading, pitch))' \
            "$staged/Scripts/UnitBase.lua"
        sed -i '/^function script.StartMoving()$/a\	Spring.Echo("[FloveAnimTrace] LUA_START_MOVING")' \
            "$staged/Scripts/UnitBase.lua"
        sed -i '/^function script.StopMoving()$/a\	Spring.Echo("[FloveAnimTrace] LUA_STOP_MOVING")' \
            "$staged/Scripts/UnitBase.lua"
        for movement in "$staged"/Scripts/headers/bipedal_{mushroom,heavymushroom,kingmushroom}_movement.lua; do
            sed -i '/^animations = {/i\	local floveTraceMove = Move\
	Move = function(piece, axis, destination, speed)\
	\tSpring.Echo(string.format("[FloveAnimTrace] LUA_MOVE_COMMAND frame=%d piece=%d axis=%d target=%.3f speed=%.3f", Spring.GetGameFrame(), piece, axis, destination, speed or 0))\
	\treturn floveTraceMove(piece, axis, destination, speed)\
	end' "$movement"
        done
    else
        vf_install_modules "$staged" "${MODULES[@]}"
    fi
    cp "$FIXTURES/animation_probe.lua" "$staged/LuaRules/Gadgets/flove_animation_probe.lua"
    vf_link_map "$MAP_DIR" "$MAP_ALIAS"
    vf_start_inline <<EOS
[GAME]
{
[team0] { startposx=5250; startposz=4500; allyteam=0; teamleader=0; }
[team1] { startposx=5250; startposz=4500; allyteam=1; teamleader=0; }
[allyteam0] { numallies=0; }
[allyteam1] { numallies=0; }
[player0] { team=0; spectator=0; name=flove-animation-probe; }
[modoptions] { test_mode=0; }
ishost=1; hostip=127.0.0.1; gamemode=0; numteams=2; numusers=1; numplayers=1; myplayernum=0; myplayername=flove-animation-probe; hostport=8452; startpostype=0; gamestartdelay=0;
gametype=$game_name; mapname=$(basename "$MAP_ALIAS" .sdd);
}
EOS
    vf_quit_when '[FloveAnimTrace] DONE'
    vf_config
    vf_run_headless "$seconds"
    vf_save_logs
    vf_require_clean_exit
    vf_forbid '\[FloveAnimTrace\] ERROR' "the $label animation trace reported an error"
    [[ $label == lua ]] || vf_forbid_runtime_failures "the $label animation trace"
    vf_require '\[FloveAnimTrace\] DONE' "the $label animation trace did not complete"
    cp "$(vf_count_log)" "$VF_OUT_DIR/trace.log"
}

case "${1:-}" in
    headless) flove_headless "${2:-}" ;;
    visual) flove_visual "${2:-}" ;;
    outline) flove_outline "${2:-}" ;;
    wisps) flove_wisps "${2:-}" "${3:-}" ;;
    original) flove_original "${2:-}" ;;
    animation-trace) flove_animation_trace "${2:-}" ;;
    *) vf_die 'usage: flove.sh [headless|visual|outline|original|animation-trace] [seconds] | wisps [stage] [seconds]' ;;
esac
