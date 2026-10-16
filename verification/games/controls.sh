#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

CONTROLS_GAMES=(area17 flove gravitas hunted mycube partsneeded ttld)

controls_speed_key() {
    local key=$1 comparison=$2 before after deadline
    before=$(grep -aE '\[controls\] speed wanted=' "$VF_X_LOG" | tail -1 | sed -E 's/.*wanted=//')
    vf_x_tap "$key"
    deadline=$((SECONDS + 10))
    while (( SECONDS < deadline )); do
        after=$(grep -aE '\[controls\] speed wanted=' "$VF_X_LOG" | tail -1 | sed -E 's/.*wanted=//')
        if awk -v before="$before" -v after="$after" -v direction="$comparison" \
            'BEGIN { exit !(direction == "up" ? after > before : after < before) }'; then
            printf '  PASS  %s changed speed from %s to %s\n' "$key" "$before" "$after"
            return 0
        fi
        sleep 0.1
    done
    echo "$key did not change game speed from $before" >&2
    return 1
}

controls_chat() {
    local deadline
    VF_X_LINE=$(wc -l <"$VF_X_LOG")
    vf_x_tap Pause
    vf_x_wait '\[controls\] state frame=[0-9]+ paused=1' 10 || return 1
    vf_x_tap Return
    vf_x_wait '\[controls\] chat writing=1' 10 || return 1
    xdotool type --clearmodifiers --delay 30 'SpringCabal chat checkx'
    vf_x_tap BackSpace
    sleep 0.5
    import -window root "$VF_OUT_DIR/chat-open.png"
    vf_x_tap Return
    vf_x_wait '\[controls\] chat writing=0' 10 || return 1
    deadline=$((SECONDS + 10))
    until grep -aEq '<[^>]+> (Allies: |Spectators: )?SpringCabal chat check$' "$VF_X_LOG"; do
        (( SECONDS < deadline )) || return 1
        sleep 0.1
    done
    echo '  PASS  Enter opened chat; editing and submission worked'

    vf_x_tap Return
    vf_x_wait '\[controls\] chat writing=1' 10 || return 1
    vf_x_tap Escape
    vf_x_wait '\[controls\] chat writing=0' 10 || return 1
    echo '  PASS  Escape closed chat'
    VF_X_LINE=$(wc -l <"$VF_X_LOG")
    vf_x_tap Pause
    vf_x_wait '\[controls\] state frame=[0-9]+ paused=0' 10 || return 1
}

controls_driver() {
    local frame paused before after screenshot deadline
    xdotool mousemove 640 360
    vf_x_wait '\[controls\] bindings (PASS|FAIL)' 60 || return 1
    [[ $VF_X_MATCH == *'bindings PASS'* ]] || return 1
    if [[ ${CONTROLS_START_DIALOG:-0} == 1 ]]; then
        vf_x_tap Return
        VF_X_LINE=$(wc -l <"$VF_X_LOG")
    fi
    if [[ ${CONTROLS_FLOVE_INTRO:-0} == 1 ]]; then
        vf_x_tap 1
        vf_x_tap s
        VF_X_LINE=$(wc -l <"$VF_X_LOG")
    fi
    vf_x_wait '\[controls\] state frame=[0-9]+ paused=[01]' 10 || return 1
    paused=${VF_X_MATCH##*paused=}
    if [[ $paused == 1 ]]; then
        vf_x_tap Pause
        vf_x_wait '\[controls\] state frame=[0-9]+ paused=0' 10 || return 1
    fi

    vf_x_wait '\[controls\] speed wanted=' 10 || return 1
    controls_speed_key alt+equal up || return 1
    controls_speed_key alt+minus down || return 1

    VF_X_LINE=$(wc -l <"$VF_X_LOG")
    vf_x_tap Pause
    vf_x_wait '\[controls\] state frame=[0-9]+ paused=1' 10 || return 1
    before=$(sed -E 's/.*state frame=([0-9]+).*/\1/' <<<"$VF_X_MATCH")
    sleep 0.3
    local latest
    latest=$(grep -aE '\[controls\] state frame=[0-9]+ paused=[01]' "$VF_X_LOG" | tail -1)
    [[ $latest == *'paused=1' ]] || { echo 'Pause did not remain active' >&2; return 1; }
    after=$(sed -E 's/.*state frame=([0-9]+).*/\1/' <<<"$latest")
    [[ $before == "$after" ]] || { echo "Pause advanced from frame $before to $after" >&2; return 1; }
    printf '  PASS  Pause froze frame %s\n' "$before"

    frame=$before
    VF_X_LINE=$(wc -l <"$VF_X_LOG")
    vf_x_tap Pause
    deadline=$((SECONDS + 10))
    while (( SECONDS < deadline )); do
        vf_x_wait '\[controls\] state frame=[0-9]+ paused=0' 2 || continue
        frame=$(sed -E 's/.*state frame=([0-9]+).*/\1/' <<<"$VF_X_MATCH")
        (( frame > before )) && break
    done
    (( frame > before )) || { echo 'Unpausing did not advance the simulation' >&2; return 1; }
    printf '  PASS  Pause resumed at frame %s\n' "$frame"

    if [[ ${CONTROLS_MOVEMENT_TEST:-0} == 1 ]]; then
        local round move_key
        for round in 1 2 3; do
            if [[ $round == 2 ]]; then
                vf_x_tap t
                controls_chat || return 1
                vf_x_tap t
            fi
            move_key=w
            [[ $round != 2 ]] || move_key=s
            vf_x_hold "$move_key" 1
            vf_x_wait '\[controls\] movement (PASS|FAIL)' 10 || return 1
            [[ $VF_X_MATCH == *'movement PASS'* ]] || { echo "$VF_X_MATCH" >&2; return 1; }
            printf '  PASS  Ship movement round %s\n' "$round"
        done
    else
        controls_chat || return 1
    fi

    if [[ ${CONTROLS_RTS_TEST:-0} == 1 ]]; then
        grep -aq '\[controls\] RTS unit selected' "$VF_X_LOG" || return 1
        vf_x_tap ctrl+1
        vf_x_wait '\[controls\] RTS control group PASS' 10 || return 1
        vf_x_tap m
        vf_x_wait '\[controls\] RTS move command PASS' 10 || return 1
        echo '  PASS  MyCube control groups and move command'
    fi

    vf_x_tap F12
    deadline=$((SECONDS + 10))
    while (( SECONDS < deadline )); do
        screenshot=$(vf_screenshots | head -1)
        [[ -n $screenshot ]] && break
        sleep 0.1
    done
    [[ -n $screenshot ]] || { echo 'F12 did not write a screenshot' >&2; return 1; }
    echo '  PASS  F12 wrote a screenshot'
    vf_x_wait '\[controls\] screenshot observed; quitting' 10 || return 1
    vf_x_wait '\[SpringApp::Kill\]\[9\]' 15 || return 1
    deadline=$((SECONDS + 5))
    while kill -0 "$VF_X_ENGINE_PID" 2>/dev/null; do
        (( SECONDS < deadline )) || return 1
        sleep 0.1
    done
}

controls_case() (
    local game=$1 variant=$2 seconds=$3 directory map staged draw status=0
    case "$game" in
        area17) directory=Area17-wasm.sdd; map=$("$PROJECT_ROOT/scripts/area17-map.sh" --dir); [[ $variant == wasm ]] || directory=Area-17.sdd ;;
        flove) directory=Flove-wasm.sdd; map=LD34-map.sdd ;;
        gravitas) directory=Gravitas-wasm.sdd; map=Gravitas-map.sdd ;;
        hunted) directory=Hunted-wasm.sdd; map=HuntedMap.sdd ;;
        mycube) directory=MyCube-wasm.sdd; map=MyCube_v1-wasm.sdd; [[ $variant == wasm ]] || map=MyCube_v1.sd7 ;;
        partsneeded) directory=PartsNeeded-wasm.sdd; map=LD35-map.sdd ;;
        ttld) directory=ToTheLastDrop-wasm.sdd; map=LD43-map.sdd ;;
        *) vf_die "unknown controls game: $game" ;;
    esac
    [[ $variant == wasm ]] || directory=${directory/-wasm.sdd/.sdd}
    vf_note "Controls: $game/$variant"
    vf_workspace "controls-$game-$variant"
    vf_cleanup_on_exit
    staged=$(vf_stage_game "$GAMES_DIR/$directory")
    mkdir -p "$staged/LuaRules/Gadgets"
    cp "$FIXTURES_DIR/controls/probe.lua" "$staged/LuaRules/Gadgets/zz_verify_controls.lua"
    draw="$staged/LuaRules/draw.lua"
    if ! grep -q 'gadgets\.lua' "$draw"; then
        if grep -vE '^[[:space:]]*(--.*)?$' "$draw" | grep -qvE '^[[:space:]]*return true[[:space:]]*$'; then
            vf_die "controls observer cannot replace unsynced code in $draw"
        fi
        cat >"$draw" <<'LUA'
gadget = {}
gadgetHandler = { IsSyncedCode = function() return false end }
VFS.Include("LuaRules/Gadgets/zz_verify_controls.lua", nil, VFS.ZIP_FIRST)
function Update() gadget:Update() end
LUA
    fi
    if [[ $game == gravitas && $variant == lua ]]; then
        vf_link_game "$GAMES_DIR/Scenario-Editor-Gravitas.sdd"
        vf_link_game "$GAMES_DIR/Scenario-Editor-Core.sdd"
        ln -sfn "$PROJECT_ROOT/spring-linux/projects" "$VF_ISOLATION/projects"
    fi
    [[ $map == /* ]] || map="$MAPS_DIR/$map"
    vf_link_map "$map"
    vf_start_file "$(vf_launch_script "$game" "$variant")"
    vf_start_set FixedRNGSeed 1
    if [[ $variant == lua && $game != gravitas && $game != hunted ]]; then
        mkdir -p "$staged/LuaUI/Widgets"
        cp "$FIXTURES_DIR/controls/chili_chat.lua" "$staged/LuaUI/Widgets/zz_verify_chat.lua"
        vf_modoption controls_chili_test 1
    fi
    if [[ $game == area17 && $variant == wasm ]]; then
        export CONTROLS_MOVEMENT_TEST=1
        vf_modoption controls_movement_test 1
    fi
    if [[ $game == mycube ]]; then
        export CONTROLS_RTS_TEST=1
        vf_modoption controls_rts_test 1
    fi
    if [[ $game == ttld ]]; then
        export CONTROLS_START_DIALOG=1
    fi
    if [[ $game == flove && $variant == wasm ]]; then
        export CONTROLS_FLOVE_INTRO=1
    fi
    vf_speed 50 200
    vf_config "$VISUAL_CONFIG"
    vf_graphics "$game"
    vf_config_set WindowBorderless 1
    vf_config_set UseFontConfigLib 0
    vf_config_set InfoConsoleGeometry '0.02 0.75 0.45 0.2'
    # shellcheck disable=SC2034
    VF_X_LINE=0
    vf_run_driven "$seconds" controls_driver || status=$?
    vf_save_logs
    vf_collect_screenshots >/dev/null
    [[ $status == 0 ]] || vf_die "controls driver failed: $game/$variant (logs: $VF_OUT_DIR/last.stdout.txt)"
    vf_require_clean_exit
    vf_forbid '\[controls\] FAIL' 'controls bindings check failed'
    vf_require '\[controls\] screenshot observed; quitting' 'the controls observer did not finish'
    vf_forbid_runtime_failures "the $game/$variant controls run"
    echo ">>> Controls passed: $game/$variant <<<"
)

selection=${1:-all}
variant=${2:-both}
seconds=${3:-60}
[[ $variant == both || $variant == wasm || $variant == lua ]] || vf_die 'controls variant must be both, wasm or lua'
if [[ $selection == all ]]; then
    games=("${CONTROLS_GAMES[@]}")
else
    games=("$selection")
fi
failures=()
for game in "${games[@]}"; do
    for current in wasm lua; do
        [[ $variant == both || $variant == "$current" ]] || continue
        controls_case "$game" "$current" "$seconds" || failures+=("$game/$current")
    done
done
if (( ${#failures[@]} )); then
    printf 'Controls failed: %s\n' "${failures[*]}" >&2
    exit 1
fi
