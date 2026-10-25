#!/usr/bin/env bash
# Focused Lua check: clicks, upgrade, loss, and retained UI restart state.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
original=${FLOVE_LUA_DIR:-$GAMES_DIR/Flove.sdd}
lua "$FIXTURES_DIR/flove/lua_regressions.lua" "$original" "$GAMES_DIR/Flove-wasm.sdd"
lua "$FIXTURES_DIR/flove/outline_regressions.lua" "$original"
vf_workspace flove-lua-platinum stable
staged=$(vf_stage_game "$original")
cat > "$staged/LuaUI/Widgets/zz_platinum_probe.lua" <<'LUA'
function widget:GetInfo() return {name='FlovePlatinumProbe',layer=100000,enabled=true,handler=true} end
local shot = 0
local function find(control, text)
    if control.caption and control.caption:find(text,1,true) then return control end
    for _,child in ipairs(control.children or {}) do local got=find(child,text); if got then return got end end
end
local function click(text)
    local control=assert(find(WG.Chili.Screen0,text),'missing button '..text)
    assert(control.OnClick and control.OnClick[1],'button has no callback '..text)
    control.OnClick[1](control)
end
function widget:GameFrame(n)
    if n == 10 then click('Hard')
    elseif n == 20 then click('Skip Tutorial')
    elseif n == 35 then
        local spireUI=assert(widgetHandler:FindWidget('Spire UI, also prevents use of mouse for anything else'))
        local x,y=Spring.WorldToScreenCoords(4800,Spring.GetGroundHeight(4800,5700),5700)
        assert(spireUI:MousePress(x,y,1),'LMB was not handled')
        spireUI:MouseRelease(x,y,1)
    elseif n == 50 then
        for _,id in ipairs(Spring.GetTeamUnits(1)) do
            if Spring.GetUnitDefID(id)==UnitDefNames.treelevel1.id then
                for i=1,3 do Spring.SendLuaRulesMsg('upgrade|'..id) end
                break
            end
        end
    elseif n == 70 or n == 90 then
        for _,id in ipairs(Spring.GetTeamUnits(1)) do
            if Spring.GetUnitDefID(id)==UnitDefNames.treelevel1.id and (Spring.GetUnitRulesParam(id,'upgradeProgress') or 0)>0 then
                Spring.SendLuaRulesMsg('upgrade|'..id); break
            end
        end
    elseif n == 160 then
        assert((Spring.GetGameRulesParam('platinum_zaps') or 0)>0,'Lua LMB did not spawn zap')
        local upgraded=false
        for _,id in ipairs(Spring.GetTeamUnits(1)) do if Spring.GetUnitDefID(id)==UnitDefNames.treelevel2.id then upgraded=true end end
        assert(upgraded,'upgrade shots never upgraded a tree')
        Spring.Echo('FLOVE LUA WEAPONS PASSED'); shot=1
    elseif n == 340 then
        assert(Spring.GetGameRulesParam('gameOver')==1,'loss was not reported'); shot=2
        if not Spring.IsCheatingEnabled() then Spring.SendCommands('cheat') end
    elseif n == 350 then
        assert(Spring.IsCheatingEnabled()); click('Restart')
    elseif n == 380 then
        assert(Spring.GetGameRulesParam('gameOver')==0,'restart retained game over')
        assert(Spring.GetGameRulesParam('difficulty')==2,'restart lost difficulty')
        assert(Spring.GetGameRulesParam('story')==1,'restart did not restore intro')
        assert(Spring.IsCheatingEnabled(),'restart changed cheats')
        local spires=0
        for _,id in ipairs(Spring.GetAllUnits()) do if Spring.GetUnitDefID(id)==UnitDefNames.spire.id then spires=spires+1 end end
        assert(spires==1,'restart did not replace world')
        Spring.Echo('FLOVE LUA RESTART PASSED'); shot=3
    end
end
function widget:DrawScreenPost()
    if shot>0 then
        local w,h=Spring.GetViewGeometry()
        assert(gl.SaveImage(0,0,w,h,'screenshots/screen_lua_'..shot..'.png'))
        if shot==3 then Spring.Echo('FLOVE LUA PLATINUM SMOKE PASSED'); Spring.SendCommands('quitforce') end
        shot=0
    end
end
LUA
cat > "$staged/LuaRules/Gadgets/zz_platinum_probe.lua" <<'LUA'
function gadget:GetInfo() return {name='FlovePlatinumProbe',layer=100000,enabled=true} end
if not gadgetHandler:IsSyncedCode() then return false end
local shots=0
function gadget:Initialize() Script.SetWatchWeapon(WeaponDefNames.zap.id,true) end
function gadget:ProjectileCreated(_,_,weapon)
    if weapon==WeaponDefNames.zap.id then shots=shots+1; Spring.SetGameRulesParam('platinum_zaps',shots) end
end
function gadget:GameFrame(n)
    if n==320 then
        for _,id in ipairs(Spring.GetAllUnits()) do
            if Spring.GetUnitDefID(id)==UnitDefNames.spire.id then Spring.DestroyUnit(id,false,true); break end
        end
    end
end
LUA
vf_link_map "$MAPS_DIR/LD34-map.sdd" 'The Grove 0.3.sdd'
vf_start_file "$(vf_launch_script flove lua)"
vf_start_set FixedRNGSeed 1
vf_config
vf_graphics flove
vf_run_visual 35
vf_save_logs
vf_require_clean_exit
vf_require 'FLOVE LUA PLATINUM SMOKE PASSED'
vf_require 'FLOVE LUA WEAPONS PASSED'
vf_require 'FLOVE LUA RESTART PASSED'
vf_forbid_runtime_failures
vf_require_screenshots 3
vf_summary
vf_collect_screenshots
