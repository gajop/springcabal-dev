#!/usr/bin/env bash
# Short Lua review run: source checks, weapons, loss, and a restart with cheats on.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
lua "$FIXTURES_DIR/hunted/lua_regressions.lua" "$GAMES_DIR/Hunted.sdd"
vf_workspace "hunted-lua-platinum${HUNTED_LUA_SHADOWS:+-shadows-$HUNTED_LUA_SHADOWS}" stable
# Start with test-owned UI settings, rather than old widget names from the
# player's profile. Removing the isolation symlink never changes that profile.
[[ ! -L $VF_ISOLATION/LuaUI ]] || rm -- "$VF_ISOLATION/LuaUI"
mkdir -p "$VF_ISOLATION/LuaUI"
rm -rf -- "$VF_WRITE_DIR/LuaUI"
staged=$(vf_stage_game "$GAMES_DIR/Hunted.sdd")
cat > "$staged/LuaUI/Widgets/zz_platinum_probe.lua" <<'LUA'
function widget:GetInfo()
    return {name = 'PlatinumProbe', layer = 100000, enabled = true, handler = true}
end
local step = 0
function widget:GameFrame(n)
    if n == 10 then
        Spring.SendLuaRulesMsg('movegun|3150|0|3480')
    elseif n == 20 then
        Spring.SendLuaRulesMsg('shotgun|3150|0|3480')
        Spring.SendLuaRulesMsg('placeStructure|' .. UnitDefNames.mine.id .. '|3150|0|3480')
    elseif n == 120 then
        assert(Spring.GetGameRulesParam('shots_fired') == 1, 'shotgun did not fire')
        assert(Spring.GetGameRulesParam('mines_placed') == 1, 'mine was not placed')
        Spring.Echo('HUNTED LUA WEAPONS PASSED')
        step = 1
    elseif n == 330 then
        step = 2
        -- Cheat changes are synced commands; let the server apply this one
        -- before exercising Restart with cheats already enabled.
        if not Spring.IsCheatingEnabled() then Spring.SendCommands('cheat') end
    elseif n == 340 then
        assert(Spring.IsCheatingEnabled(), 'probe did not enable cheats before restart')
        local ending = assert(widgetHandler:FindWidget('Chili EndGame Window'))
        assert(ending:KeyPress(13, {}, false), 'Enter did not restart the hunt')
    elseif n == 370 then
        assert(Spring.GetGameRulesParam('carrot_count') == 100, 'restart did not restore carrots')
        assert(Spring.GetGameRulesParam('shots_fired') == 0, 'restart did not reset shots')
        assert(Spring.GetGameRulesParam('mines_placed') == 0, 'restart did not reset mines')
        assert(Spring.IsCheatingEnabled(), 'restart changed the existing cheat state')
        Spring.Echo('HUNTED LUA RESTART PASSED')
        step = 3
    end
end
function widget:DrawScreenPost()
    if step >= 1 and step <= 3 then
        local w, h = Spring.GetViewGeometry()
        assert(gl.SaveImage(0, 0, w, h, 'screenshots/screen_lua_' .. step .. '.png'))
        if step == 3 then
            Spring.Echo('HUNTED LUA PLATINUM SMOKE PASSED')
            Spring.SendCommands('quitforce')
        end
        step = 0
    end
end
LUA
cat > "$staged/LuaRules/Gadgets/zz_platinum_probe.lua" <<'LUA'
function gadget:GetInfo()
    return {name = 'PlatinumProbe', layer = 100000, enabled = true}
end
if not gadgetHandler:IsSyncedCode() then return false end
function gadget:GameFrame(n)
    if n == 310 then
        Spring.SetGameRulesParam('carrot_count', 0)
    end
end
LUA
vf_link_map "$MAPS_DIR/HuntedMap.sdd" 'Hunted - v04.sdd'
vf_start_file "$(vf_launch_script hunted lua)"
vf_config
vf_graphics hunted
[[ -z ${HUNTED_LUA_SHADOWS:-} ]] || vf_config_set Shadows "$HUNTED_LUA_SHADOWS"
vf_run_visual 35 1024x720x24
vf_save_logs
vf_require_clean_exit
vf_require 'HUNTED LUA PLATINUM SMOKE PASSED' 'Lua smoke did not finish'
vf_require 'HUNTED LUA RESTART PASSED' 'Lua restart did not finish'
vf_forbid_runtime_failures
vf_require_screenshots 3
vf_summary
vf_collect_screenshots
