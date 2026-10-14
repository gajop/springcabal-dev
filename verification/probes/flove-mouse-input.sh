#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
# Real SDL events in Xvfb; this probe never opens the user desktop.
VF_RENDERER=software
vf_workspace flove-input-platinum stable
vf_build "$GAMES_DIR/Flove-wasm.sdd/wasm-src" ""
staged=$(vf_stage_game "$GAMES_DIR/Flove-wasm.sdd")
vf_install_modules "$staged" flove_rules_wasm:LuaRules/wasm/flove-rules.wasm flove_rules_unsynced_wasm:LuaRules/wasm/flove-rules-unsynced.wasm flove_ui_wasm:LuaUI/wasm/flove-ui.wasm
cat > "$staged/LuaRules/Gadgets/zz_input_probe.lua" <<'LUA'
function gadget:GetInfo() return {name='FloveInputProbe',layer=100000,enabled=true} end
if gadgetHandler:IsSyncedCode() then
    local shots, flowers = 0, 0
    function gadget:Initialize() Script.SetWatchWeapon(WeaponDefNames.zap.id,true); Script.SetWatchWeapon(WeaponDefNames.flowershot.id,true) end
    function gadget:ProjectileCreated(_,_,weapon)
        if weapon == WeaponDefNames.zap.id then shots=shots+1; Spring.SetGameRulesParam('click_shots',shots) end
        if weapon == WeaponDefNames.flowershot.id then flowers=flowers+1; Spring.SetGameRulesParam('click_flowers',flowers) end
    end
else
    local boot, ready, finished = false,false,false
    function gadget:Update()
        if not boot and Spring.GetGameFrame() > 10 then boot=true; Spring.Echo('FLOVE INPUT BOOT') end
        if not ready then
            local started = false
            for _,id in ipairs(Spring.GetTeamUnits(1)) do
                if Spring.GetUnitRulesParam(id,'story') == 0 then started=true; break end
            end
            if started then
                local w,h = Spring.GetViewGeometry()
                for x=math.floor(w*.3),math.floor(w*.7),40 do
                    for y=math.floor(h*.3),math.floor(h*.7),40 do
                        local _,p = Spring.TraceScreenRay(x,y,true)
                        if p and p[1]>2048 and p[1]<8192 and p[3]>2048 and p[3]<8192 then
                            Spring.Echo('FLOVE CLICK '..x..' '..(h-1-y)); ready=true; return
                        end
                    end
                end
            end
        elseif not finished and (Spring.GetGameRulesParam('click_shots') or 0)>0 and (Spring.GetGameRulesParam('click_flowers') or 0)>0 then
            finished=true; Spring.Echo('FLOVE PHYSICAL LMB AND RMB PASSED'); Spring.SendCommands('quitforce')
        end
    end
end
LUA
vf_link_map "$MAPS_DIR/LD34-map.sdd" 'The Grove 0.3.sdd'
vf_start_file "$(vf_launch_script flove)"
vf_config
vf_graphics flove
export FLOVE_REAL_ENGINE=$(vf_engine_bin visual)
export FLOVE_INPUT_LOG="$VF_WRITE_DIR/stdout.txt"
export SPRING_ENGINE_BIN="$FIXTURES_DIR/flove/mouse-input-engine.sh"
vf_run_visual 45
vf_save_logs
vf_summary
vf_require_clean_exit
vf_require 'FLOVE PHYSICAL LMB AND RMB PASSED'
vf_forbid_runtime_failures
