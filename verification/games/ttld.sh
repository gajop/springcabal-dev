#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

# Golden RMSE limit, about twice the run-to-run noise measured on 2026-09-23 (0.1%).
GOLDEN_TOLERANCE=${GOLDEN_TOLERANCE:-1}

GAME_DIR="$GAMES_DIR/ToTheLastDrop-wasm.sdd"
LUA_GAME_DIR="$GAMES_DIR/ToTheLastDrop.sdd"
SOURCE_ROOT="$GAME_DIR/wasm-src"
MAP_DIR="$MAPS_DIR/LD43-map.sdd"
MAP_NAME='Eyam'
GAME_NAME='To the Last Drop WASM 0.1.0-wasm'
LUA_GAME_NAME='ToTheLastDrop.sdd'
TEST_MARKER='ALL TO THE LAST DROP INTEGRATION TESTS PASSED'

ttld_assets() {
    local asset
    for asset in \
        "$GAME_DIR/LuaUI/wasm/ttld.rml" \
        "$GAME_DIR/LuaUI/wasm/ttld.rcss" \
        "$GAME_DIR/GameData/weapondefs_post.lua" \
        "$GAME_DIR/effects/nothing.lua" \
        "$GAME_DIR/Bitmaps/GPL/flame.png" \
        "$MAP_DIR/mapinfo.lua"; do
        [[ -f $asset ]] || vf_die "required asset is missing: $asset"
    done
    [[ ! -e "$MAP_DIR/shaders" ]] ||
        vf_die "map still overrides the engine SMF shaders: $MAP_DIR/shaders"
}

ttld_start() {
    local game_name=${1:-$GAME_NAME}
    vf_start_inline <<EOS
[GAME]
{
[team0] { startposx=5580; startposz=7100; allyteam=0; teamleader=0; }
[team1] { startposx=5650; startposz=2700; allyteam=1; teamleader=0; }
[team2] { startposx=5650; startposz=2700; allyteam=2; teamleader=0; }
[allyteam0] { numallies=0; }
[allyteam1] { numallies=0; }
[allyteam2] { numallies=0; }
[player0] { team=0; spectator=0; name=wasm-test; }
minspeed=100; maxspeed=100; ishost=1; hostip=127.0.0.1; gamemode=0; numteams=3; numusers=1; numplayers=1; myplayernum=0; myplayername=wasm-test; hostport=8452; startpostype=0; gamestartdelay=0;
gametype=$game_name; mapname=$MAP_NAME;
}
EOS
    # The rules draw from the engine's synced RNG; pin it so runs repeat.
    vf_start_set FixedRNGSeed 1
}

ttld_lua_visual() {
    local seconds=${1:-20} screen=${2:-1280x720x24} staged shots

    vf_workspace ttld-lua-visual stable
    staged=$(vf_stage_game "$LUA_GAME_DIR")
    # The original test starts directly in gameplay. The normal intro window
    # pauses the game and captures the mouse, which would make an automated
    # hover test measure the intro rather than the unit render path.
    rm -f "$staged/LuaUI/Widgets/ui_begingame.lua"
    cp "$FIXTURES_DIR/ttld/lua_render_fixture.lua" \
        "$staged/LuaRules/Gadgets/ttld_lua_render_fixture.lua"
    cp "$FIXTURES_DIR/ttld/lua_hover_capture.lua" \
        "$staged/LuaUI/Widgets/ttld_lua_hover_capture.lua"

    vf_link_game "$staged"
    vf_link_map "$MAP_DIR"
    ttld_start "$LUA_GAME_NAME"
    vf_config "$VISUAL_CONFIG"
    printf 'AllowDeferredMapRendering = 1\nAllowDeferredModelRendering = 1\nAllowDeferredModelBufferClear = 1\n' >>"$VF_CONFIG_FILE"
    vf_run_visual "$seconds" "$screen"
    vf_save_logs
    vf_require_exit_or_timeout

    shots=$(vf_require_screenshots 3)
    vf_require '\[TTLD Lua E2E\] fixture boss=[0-9]+ orkbig=[0-9]+' \
        'Lua render fixture did not spawn both units'
    vf_require '\[TTLD Lua E2E\] hover orkboss unit=[0-9]+.*trace=unit:[0-9]+' \
        'Lua hover did not trace orkboss'
    vf_require '\[TTLD Lua E2E\] hover orkbig unit=[0-9]+.*trace=unit:[0-9]+' \
        'Lua hover did not trace orkbig'
    vf_forbid 'LuaRules.*(Error|error)|LuaUI.*(Error|error)|attempt to (index|call)|Lua.*syntax' \
        'the Lua render run contains a runtime failure'
    printf 'captured %s Lua screenshot(s) in %s\n' "$shots" "$(vf_collect_screenshots)"
    echo '>>> To the Last Drop Lua visual verification passed <<<'
}

# Stages the port with modules built for FEATURES.
ttld_stage() {
    local features=$1 staged
    ttld_assets
    vf_build "$SOURCE_ROOT" "$features"
    staged=$(vf_stage_game "$GAME_DIR")
    vf_install_modules "$staged" \
        ttld_rules_wasm:LuaRules/wasm/ttld-rules.wasm \
        ttld_rules_unsynced_wasm:LuaRules/wasm/ttld-rules-unsynced.wasm \
        ttld_ui_wasm:LuaUI/wasm/ttld-ui.wasm
    vf_link_map "$MAP_DIR"
    ttld_start
}

ttld_assert_leader_render() {
    local baseline fixture line coords
    local leader_id leader_x leader_y orkbig_id orkbig_x orkbig_y
    local width height size=140 anchor=80
    local leader_left leader_top orkbig_left orkbig_top
    local leader_screen_y orkbig_screen_y box=260
    local leader_box_left leader_box_top leader_box_right leader_box_bottom
    local orkbig_box_left orkbig_box_top orkbig_box_right orkbig_box_bottom
    local work="$VF_TEST_ROOT/leader-render"
    local -a render_shots
    local leader_pixels orkbig_pixels

    mapfile -t render_shots < <(vf_screenshots)
    [[ ${#render_shots[@]} -ge 2 ]] || vf_die 'leader render test needs baseline and fixture screenshots'
    baseline=${render_shots[0]}
    fixture=${render_shots[1]}

    line=$(grep -E 'TTLD E2E leader render pixels:' "$VF_OUT_DIR/last.combined.txt" | tail -1 || true)
    coords=$(sed -E 's/.*leader=Some\(\(([0-9]+), ([0-9.]+), ([0-9.]+)\)\) orkbig=Some\(\(([0-9]+), ([0-9.]+), ([0-9.]+)\)\).*/\1 \2 \3 \4 \5 \6/' <<<"$line")
    read -r leader_id leader_x leader_y orkbig_id orkbig_x orkbig_y <<<"$coords"
    [[ $leader_id =~ ^[0-9]+$ && $orkbig_id =~ ^[0-9]+$ ]] ||
        vf_die "leader render test did not report both fixture units: $line"

    read -r width height <<<"$(identify -format '%w %h' "$fixture")"
    leader_x=$(printf '%.0f' "$leader_x")
    leader_y=$(printf '%.0f' "$leader_y")
    orkbig_x=$(printf '%.0f' "$orkbig_x")
    orkbig_y=$(printf '%.0f' "$orkbig_y")
    leader_left=$((leader_x - size / 2))
    leader_top=$((height - leader_y - anchor))
    orkbig_left=$((orkbig_x - size / 2))
    orkbig_top=$((height - orkbig_y - anchor))
    for value in "$leader_left" "$leader_top" "$orkbig_left" "$orkbig_top"; do
        [[ $value -ge 0 ]] || vf_die "leader render crop is outside the screenshot: $line"
    done
    [[ $((leader_left + size)) -le $width && $((orkbig_left + size)) -le $width ]] ||
        vf_die "leader render crop exceeds screenshot width: $line"
    [[ $((leader_top + size)) -le $height && $((orkbig_top + size)) -le $height ]] ||
        vf_die "leader render crop exceeds screenshot height: $line"

    mkdir -p "$work"
    # Keep the unzoomed fixture frame as the human-facing comparison.  The
    # equal-size boxes make it possible to compare both units without changing
    # their scale or camera between screenshots; the small crops below remain
    # machine-only pixel-diff inputs.
    cp "$fixture" "$work/leader-render-full.png"
    leader_screen_y=$((height - leader_y))
    orkbig_screen_y=$((height - orkbig_y))
    leader_box_left=$((leader_x - box / 2))
    leader_box_top=$((leader_screen_y - box / 2))
    leader_box_right=$((leader_box_left + box))
    leader_box_bottom=$((leader_box_top + box))
    orkbig_box_left=$((orkbig_x - box / 2))
    orkbig_box_top=$((orkbig_screen_y - box / 2))
    orkbig_box_right=$((orkbig_box_left + box))
    orkbig_box_bottom=$((orkbig_box_top + box))
    convert "$fixture" \
        -stroke '#00e5ff' -strokewidth 4 -fill none \
        -draw "rectangle $leader_box_left,$leader_box_top $leader_box_right,$leader_box_bottom" \
        -draw "rectangle $orkbig_box_left,$orkbig_box_top $orkbig_box_right,$orkbig_box_bottom" \
        -fill white -stroke black -strokewidth 2 -pointsize 22 \
        -annotate "+$((leader_box_left + 8))+$((leader_box_top + 28))" 'orkboss (2.5x)' \
        -annotate "+$((orkbig_box_left + 8))+$((orkbig_box_top + 28))" 'orkbig (1x)' \
        "$work/leader-render-full-marked.png"
    convert "$baseline" -crop "${size}x${size}+${leader_left}+${leader_top}" +repage "$work/leader-baseline.png"
    convert "$fixture" -crop "${size}x${size}+${leader_left}+${leader_top}" +repage "$work/leader-fixture.png"
    convert "$baseline" -crop "${size}x${size}+${orkbig_left}+${orkbig_top}" +repage "$work/orkbig-baseline.png"
    convert "$fixture" -crop "${size}x${size}+${orkbig_left}+${orkbig_top}" +repage "$work/orkbig-fixture.png"
    leader_pixels=$(compare -metric AE -fuzz 4% "$work/leader-baseline.png" "$work/leader-fixture.png" null: 2>&1 || true)
    orkbig_pixels=$(compare -metric AE -fuzz 4% "$work/orkbig-baseline.png" "$work/orkbig-fixture.png" null: 2>&1 || true)
    [[ $leader_pixels =~ ^[0-9]+$ && $orkbig_pixels =~ ^[0-9]+$ ]] ||
        vf_die "leader render pixel comparison failed (leader='$leader_pixels' orkbig='$orkbig_pixels')"
    (( leader_pixels > orkbig_pixels * 2 )) ||
        vf_die "ork leader is not rendered enlarged (leader changed $leader_pixels pixels, orkbig changed $orkbig_pixels)"
    printf 'leader render pixels: leader=%s orkbig=%s (baseline=%s fixture=%s)\n' \
        "$leader_pixels" "$orkbig_pixels" "$(basename "$baseline")" "$(basename "$fixture")"
    printf 'leader render comparison: %s\n' "$work/leader-render-full-marked.png"
}

ttld_headless() {
    local seconds=${1:-45}
    vf_cleanup_on_exit

    vf_workspace ttld-headless
    ttld_stage headless-integration
    vf_quit_when "$TEST_MARKER"
    vf_config
    vf_run_headless "$seconds"
    vf_save_logs
    vf_require_clean_exit

    vf_require "$TEST_MARKER" 'the headless integration assertions did not pass'
    vf_forbid 'world state re-entered' 'the synced module re-entered its world state'
    vf_forbid 'Wasm.*(trap|error|Error)|CallIn.*(error|Error)|panic|LuaUnitScript.*error' \
        'the run contains a runtime failure'
    vf_forbid 'Unknown tag "(new|clone|append)"|really low power|table for CEG .* invalid|Failed to load icon|excess char' \
        'the game data still produces engine warnings'

    grep -- '\[TTLD-Rust-Test\]' "$(vf_count_log)" || true
    echo '>>> To the Last Drop headless verification passed <<<'
}

ttld_pose_parity() {
    local seconds=${1:-14}
    local rust_log lua_log
    vf_cleanup_on_exit

    vf_workspace ttld-pose-rust stable
    ttld_stage pose-probe
    vf_quit_when '[UnitScriptProbe] DONE unit='
    vf_config
    vf_run_headless "$seconds"
    vf_save_logs
    vf_require_clean_exit
    rust_log=$(vf_count_log)
    vf_require '\[UnitScriptProbe\] DONE unit=[0-9]+ last_frame=195' \
        'Rust pose probe did not complete'
    vf_forbid 'Wasm.*(trap|error|Error)|CallIn.*(error|Error)|panic|\[UnitScriptProbe\] ERROR' \
        'Rust pose probe contains a runtime failure'

    vf_workspace ttld-pose-lua stable
    staged=$(vf_stage_game "$LUA_GAME_DIR")
    mkdir -p "$staged/LuaRules/Gadgets"
    rm -f "$staged/LuaUI/Widgets/ui_begingame.lua"
    cp "$FIXTURES_DIR/ttld/lua_pose_probe.lua" \
        "$staged/LuaRules/Gadgets/ttld_lua_pose_probe.lua"
    vf_link_game "$staged"
    vf_link_map "$MAP_DIR"
    ttld_start "$LUA_GAME_NAME"
    vf_quit_when '[UnitScriptProbe] DONE unit='
    vf_config
    vf_run_headless "$seconds"
    vf_save_logs
    vf_require_clean_exit
    lua_log=$(vf_count_log)
    vf_require '\[UnitScriptProbe\] DONE unit=[0-9]+ last_frame=195' \
        'Lua pose probe did not complete'
    vf_forbid 'LuaRules.*(Error|error)|Lua.*syntax|\[UnitScriptProbe\] ERROR' \
        'Lua pose probe contains a runtime failure'

    if ! diff -u \
        <(grep -E '\[UnitScriptProbe\] (map|info) ' "$lua_log" |
            sed -E 's/.*\[UnitScriptProbe\] //; s/[[:space:]]+$//' | sort -u) \
        <(grep -E '\[UnitScriptProbe\] (map|info) ' "$rust_log" |
            sed -E 's/.*\[UnitScriptProbe\] //; s/[[:space:]]+$//' | sort -u); then
        vf_die 'Lua and Rust skeleton maps/offsets differ'
    fi
    python3 "$VERIFICATION_ROOT/unit-scripts/compare.py" \
        "$lua_log" "$rust_log" --tolerance 1e-4
    echo '>>> To the Last Drop Lua/Rust pose parity verification passed <<<'
}

ttld_visual() {
    local seconds=${1:-150} screen=${2:-1280x720x24} shots

    vf_workspace ttld-visual stable
    ttld_stage e2e
    # Particle effects draw from the engine's unsynced RNG.
    vf_start_set FixedUnsyncedRNGSeed 1
    vf_quit_when 'TTLD E2E done'
    vf_config "$VISUAL_CONFIG"
    printf 'AllowDeferredMapRendering = 1\nAllowDeferredModelRendering = 1\nAllowDeferredModelBufferClear = 1\n' >>"$VF_CONFIG_FILE"
    vf_run_visual "$seconds" "$screen"
    vf_save_logs
    vf_require_clean_exit

    vf_require 'TTLD E2E done' 'the e2e run did not reach its last step'
    vf_forbid 'TTLD E2E missed the pause' 'a golden screenshot was not taken on its paused frame'
    shots=$(vf_require_screenshots 14)
    ttld_assert_leader_render
    vf_require 'TTLD E2E hover check fixture=orkboss unit=([0-9]+) hud_target=\1 cursor=\1( |$)' \
        'hovering the ork leader did not make it the HUD target'
    vf_require 'TTLD E2E hover check fixture=orkbig unit=([0-9]+) hud_target=\1 cursor=\1( |$)' \
        'hovering a big ork did not make it the HUD target'
    vf_require 'TTLD E2E mouse wheel accepted=true .*captured=true' \
        'the HUD did not capture the mouse wheel'
    vf_require 'TTLD E2E poultice sent: true' 'the e2e Poultice cast was not accepted'
    vf_require 'TTLD E2E poultice target=[0-9]+ after=.* moved=[1-9][0-9]{2,}' \
        'Poultice did not throw its target 100+ elmos'
    vf_require 'TTLD E2E tracking after_move: .* error=0\.[0-9]' \
        'the camera did not keep tracking the moving blood mage'
    vf_require 'TTLD E2E tracking late: .* error=0\.[0-9]' \
        'the camera did not keep tracking the blood mage to the end of its walk'
    vf_require 'TTLD E2E selection seeded=1' 'selection fixture did not select the player'
    vf_require 'TTLD E2E selection cleared=0' 'the player remained selected in the engine UI'
    vf_forbid 'GLSL-PO::Validate\] program-object name: SMFShader' \
        'the map SMF shader still fails to validate; terrain will not render'
    vf_note 'To the Last Drop goldens'
    vf_goldens_by_index ttld shot_1 shot_2
    # The fireball shot: its drain's blood puffs are random (1.4% between
    # runs); a fireball missing or a frame off is 7% or more.
    local -a all_shots
    mapfile -t all_shots < <(vf_screenshots)
    vf_golden ttld shot_3 "${all_shots[2]}" 3
    vf_goldens_done
    printf 'captured %s screenshot(s) in %s\n' "$shots" "$(vf_collect_screenshots)"
    echo '>>> To the Last Drop visual verification passed <<<'
}

case "${1:-}" in
    headless) ttld_headless "${2:-}" ;;
    visual) ttld_visual "${2:-}" "${3:-}" ;;
    lua-visual) ttld_lua_visual "${2:-}" "${3:-}" ;;
    pose-parity) ttld_pose_parity "${2:-}" ;;
    *) vf_die 'usage: ttld.sh [headless|visual|lua-visual|pose-parity] [seconds] [screen]' ;;
esac
