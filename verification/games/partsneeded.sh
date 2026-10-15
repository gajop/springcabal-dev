#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

# Golden RMSE limit.  Run-to-run drift has not been measured for this suite;
# 8% matches the other scenario suites (see verification/README.md).
GOLDEN_TOLERANCE=${GOLDEN_TOLERANCE:-8}
# Shots 3 and 4, taken on a settled camera: two runs differ by about 1%.
SETTLED_TOLERANCE=3
# A shot darker than this (mean grey, 0-1) is a black screen; the dungeon
# shots are about 0.08-0.11.
NOT_BLACK_MEAN=0.04
# The end screen's two lines of text in a 1280x720 frame.
ENDING_TEXT_CROP=440x110+420+315

GAME_DIR="$GAMES_DIR/PartsNeeded-wasm.sdd"
LUA_GAME_DIR="$GAMES_DIR/PartsNeeded.sdd"
SOURCE_ROOT="$GAME_DIR/wasm-src"
MAP_DIR="$MAPS_DIR/LD35-map.sdd"
TEST_MARKER='ALL PARTS NEEDED INTEGRATION TESTS PASSED'
ENDING_TEST_MARKER='PARTS NEEDED ENDING INTEGRATION TEST PASSED'
RESTART_TEST_MARKER='PARTS NEEDED RESTART INTEGRATION TEST PASSED'
SAME_PASS_TEST_MARKER='PARTS NEEDED SAME-PASS INTEGRATION TEST PASSED'
MODULES=(
    partsneeded_rules_wasm:LuaRules/wasm/partsneeded-rules.wasm
    partsneeded_ui_wasm:LuaUI/wasm/partsneeded-ui.wasm
)

partsneeded_assets() {
    local asset
    for asset in \
        "$GAME_DIR/LuaRules/Gadgets/unit_script.lua" \
        "$GAME_DIR/LuaRules/draw.lua" \
        "$GAME_DIR/LuaUI/images/ground/s_ok.png" \
        "$GAME_DIR/LuaUI/images/ground/b_ok.png" \
        "$LUA_GAME_DIR/Scripts/wisp.lua" \
        "$MAP_DIR/mapinfo.lua"; do
        [[ -f $asset ]] || vf_die "required asset is missing: $asset"
    done
}

# partsneeded_not_black NAME IMAGE: fail unless IMAGE's mean grey reaches
# NOT_BLACK_MEAN.
partsneeded_not_black() {
    local name=${1:?name} image=${2:?image} mean
    [[ -f $image ]] || vf_die "no image for $name"
    mean=$(convert "$image" -colorspace gray -format '%[fx:mean]' info:)
    awk -v mean="$mean" -v floor="$NOT_BLACK_MEAN" 'BEGIN { exit !(mean >= floor) }' ||
        vf_die "$name is black (mean grey $mean, floor $NOT_BLACK_MEAN)"
    printf '  BRIGHT   %s (mean grey %s)\n' "$name" "$mean"
}

partsneeded_stage() {
    local features=$1 staged
    partsneeded_assets
    vf_build "$SOURCE_ROOT" "$features"
    staged=$(vf_stage_game "$GAME_DIR")
    vf_install_modules "$staged" "${MODULES[@]}"
    vf_link_map "$MAP_DIR"
    vf_start_file "$(vf_launch_script partsneeded)"
}

partsneeded_headless() {
    local seconds=${1:-120}
    vf_cleanup_on_exit

    vf_workspace partsneeded-headless
    partsneeded_stage headless-integration
    vf_quit_when "$TEST_MARKER" "$ENDING_TEST_MARKER" "$RESTART_TEST_MARKER" "$SAME_PASS_TEST_MARKER" \
        "PARTS NEEDED UI HANDSHAKE PASSED"
    vf_config
    vf_run_headless "$seconds"
    vf_save_logs
    vf_require_clean_exit

    vf_require "$TEST_MARKER" 'the headless integration assertions did not pass'
    vf_require 'PARTS NEEDED UI HANDSHAKE PASSED' 'the UI hello never reached the rules'
    vf_require "$ENDING_TEST_MARKER" 'the type-1 ending integration assertions did not pass'
    vf_require "$RESTART_TEST_MARKER" 'the restart integration assertions did not pass'
    vf_require "$SAME_PASS_TEST_MARKER" \
        'the same-pass lever and kill plate assertions did not pass'
    vf_forbid 'ASSERTION FAILED' 'an integration assertion failed'
    vf_forbid 'LuaUnitScript.*error' 'a Lua unit script failed'
    vf_forbid_runtime_failures
    vf_forbid 'Unknown tag "(new|clone|append)"|really low power|table for CEG .* invalid|excess char' \
        'the game data still produces engine warnings'

    grep -- '\[PartsNeeded-Rust-Test\]' "$(vf_count_log)" || true
    echo '>>> Parts Needed headless verification passed <<<'
}

partsneeded_visual() {
    local seconds=${1:-75} shots

    vf_workspace partsneeded-visual stable
    partsneeded_stage e2e,headless-integration
    vf_config "$VISUAL_CONFIG"
    vf_run_visual "$seconds"
    vf_save_logs
    # The e2e widget quits after the ending's final shot.
    vf_require_clean_exit
    shots=$(vf_require_screenshots 6)
    vf_require "$TEST_MARKER" 'Parts Needed did not reach its test marker'
    vf_require "$ENDING_TEST_MARKER" 'Parts Needed did not reach its ending test marker'
    vf_forbid 'ASSERTION FAILED' 'an in-game assertion failed'
    vf_forbid_runtime_failures 'the Parts Needed visual run'
    vf_forbid 'E2E camera not settled' \
        'shot 3 or 4 was taken while the camera was still moving'

    vf_note 'Parts Needed goldens'
    local all_shots index
    mapfile -t all_shots < <(vf_screenshots)
    # Shots 1 and 2 are taken on fixed frames; 3 and 4 wait for the camera
    # to settle on the body, so they get a tight limit. The dungeon is dark:
    # an all-black frame is only 10% off these goldens, hence the floor.
    for index in 0 1 2 3; do
        partsneeded_not_black "shot_$((index + 1))" "${all_shots[$index]}"
    done
    vf_golden partsneeded shot_1 "${all_shots[0]}"
    vf_golden partsneeded shot_2 "${all_shots[1]}"
    vf_golden partsneeded shot_3 "${all_shots[2]}" "$SETTLED_TOLERANCE"
    vf_golden partsneeded shot_4 "${all_shots[3]}" "$SETTLED_TOLERANCE"
    # Shots 5 and 6 are the ending's start and final frame. The start is left
    # out: the arriving wisps' spawn offsets come from the synced RNG. The
    # final frame is white but for the end screen's two lines: compare those.
    vf_golden partsneeded ending_final "${all_shots[5]}" "$GOLDEN_TOLERANCE" "$ENDING_TEXT_CROP"
    vf_goldens_done
    printf 'Parts Needed visual E2E passed: %s screenshot(s) in %s\n' "$shots" "$(vf_collect_screenshots)"
}

case "${1:-}" in
    headless) partsneeded_headless "${2:-}" ;;
    visual) partsneeded_visual "${2:-}" ;;
    *) vf_die 'usage: partsneeded.sh [headless|visual] [seconds]' ;;
esac
