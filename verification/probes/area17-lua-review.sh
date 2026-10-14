#!/usr/bin/env bash
# Focused Lua checks: upgrade effects, controls, UFO death/respawn, and victory.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
lua_game=${1:-$GAMES_DIR/Area-17.sdd}
lua "$FIXTURES_DIR/area17/lua_regressions.lua" "$lua_game"
vf_workspace area17-lua-platinum stable
staged=$(vf_stage_game "$lua_game")
cat > "$staged/LuaRules/Gadgets/zz_platinum_probe.lua" <<'LUA'
function gadget:GetInfo()
    return {name = 'PlatinumProbe', layer = -100000, enabled = true}
end
if not gadgetHandler:IsSyncedCode() then return false end
local ufo, oldUfo, startX, initialHealth
local function findUfo()
    for _, id in ipairs(Spring.GetAllUnits()) do
        if Spring.GetUnitDefID(id) == UnitDefNames.ufo.id then return id end
    end
end
function gadget:GameFrame(n)
    if n == 5 then
        ufo = assert(findUfo(), 'UFO missing at startup')
        startX = Spring.GetUnitPosition(ufo)
        initialHealth = select(2, Spring.GetUnitHealth(ufo))
        Spring.SetGameRulesParam('biomass', 1000000)
        Spring.SetGameRulesParam('research', 1000000)
    elseif n == 45 then
        local _, maxHP = Spring.GetUnitHealth(ufo)
        assert(math.abs(maxHP - initialHealth * 1.4) < 0.1, 'armor did not scale health')
        for slot = 13,16 do
            local base = WeaponDefs[UnitDefs[UnitDefNames.ufo.id].weapons[slot].weaponDef].reload
            assert(math.abs(Spring.GetUnitWeaponState(ufo,slot,'reloadTime') - base / 1.15) < 1/30,
                'point-defense reload upgrade mismatch')
        end
        assert(Spring.GetUnitRulesParam(ufo,'selfMoveSpeedChange') > 1, 'haste did not change speed')
        Spring.Echo('AREA17 LUA UPGRADES PASSED')
    elseif n == 90 then
        local x = Spring.GetUnitPosition(ufo)
        assert(x > startX + 10, 'UFO did not move')
        oldUfo = ufo
        Spring.DestroyUnit(ufo, false, true)
    elseif n == 205 then
        ufo = assert(findUfo(), 'UFO did not respawn')
        assert(ufo ~= oldUfo, 'probe did not observe a new UFO')
        local _, maxHP = Spring.GetUnitHealth(ufo)
        assert(math.abs(maxHP - initialHealth * 1.4) < 0.1, 'respawn lost armor upgrade')
        Spring.Echo('AREA17 LUA RESPAWN PASSED')
    elseif n == 310 then
        local x,y,z = Spring.GetUnitPosition(ufo)
        Spring.CreateUnit('endcube',x,y-10,z,0,1)
    elseif n == 330 then
        assert(Spring.GetGameRulesParam('gameWon') == 1, 'queen capture did not win')
        assert(Spring.GetGameRulesParam('gameOver') == 1, 'victory did not end the game')
        Spring.Echo('AREA17 LUA VICTORY PASSED')
    end
end
LUA
cat > "$staged/LuaUI/Widgets/zz_platinum_probe.lua" <<'LUA'
function widget:GetInfo()
    return {name = 'PlatinumProbe', layer = 100000, enabled = true, handler = true}
end
local shot, screenshots = 0, 0
function widget:GameFrame(n)
    if n == 10 then
        Spring.SendLuaRulesMsg('upgrade|armor')
        Spring.SendLuaRulesMsg('unlock|shield')
        Spring.SendLuaRulesMsg('unlock|antiMissilePointDefense')
        Spring.SendLuaRulesMsg('upgrade|antiMissilePointDefense')
        Spring.SendLuaRulesMsg('unlock|haste')
        Spring.SendLuaRulesMsg('unlock|pulseLaser')
        Spring.SendLuaRulesMsg('changeWeapon|pulseLaser')
    elseif n == 20 then
        Spring.SendLuaRulesMsg('ability|haste')
    end
    if n >= 30 and n <= 80 then
        Spring.SendLuaRulesMsg('movement|1|0')
    end
    if n == 60 then
        local movement = assert(widgetHandler:FindWidget('Movement Control'))
        local hidden = assert(widgetHandler:FindWidget('Hides the default interface'))
        assert(hidden:CommandNotify(CMD.MOVE, {100,0,100}, {}), 'RTS command was not blocked')
        local upgrade = assert(widgetHandler:FindWidget('Upgrade widget for spaceships'))
        upgrade:KeyPress(Spring.GetKeyCode('t'),{},false)
        assert(upgrade:KeyPress(27,{},false), 'Escape did not close the tech panel')
        assert(movement:KeyPress(Spring.GetKeyCode('d'),{},false), 'direct movement key was not captured')
        shot = 1
    elseif n == 220 then
        shot = 2
    elseif n == 350 then
        assert(widgetHandler:FindWidget('Chili EndGame Window'), 'end screen widget missing')
        shot = 3
    end
end
function widget:DrawScreenPost()
    if shot > 0 then
        local w,h = Spring.GetViewGeometry()
        assert(gl.SaveImage(0,0,w,h,'screenshots/screen_lua_' .. shot .. '.png'))
        screenshots = screenshots + 1
        shot = 0
        if screenshots == 3 then
            Spring.Echo('AREA17 LUA PLATINUM SMOKE PASSED')
            Spring.SendCommands('quitforce')
        end
    end
end
LUA
vf_link_map "$("$PROJECT_ROOT/scripts/area17-map.sh" --dir)"
vf_start_file "$(vf_launch_script area17 lua)"
vf_config
vf_graphics area17
vf_run_visual 35
vf_save_logs
vf_require_clean_exit
vf_require 'AREA17 LUA PLATINUM SMOKE PASSED' 'Lua smoke did not finish'
vf_require 'AREA17 LUA UPGRADES PASSED' 'Lua upgrades failed'
vf_require 'AREA17 LUA RESPAWN PASSED' 'Lua respawn failed'
vf_require 'AREA17 LUA VICTORY PASSED' 'Lua victory failed'
vf_forbid_runtime_failures
vf_require_screenshots 3
vf_summary
vf_collect_screenshots
