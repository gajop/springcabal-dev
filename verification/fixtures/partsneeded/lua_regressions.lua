-- Exercise shipped Lua gadgets, following the existing Lua regression suites.
local root = assert(arg[1])
local function loadGadget(file, env)
    setmetatable(env, {__index=_G})
    local chunk = assert(loadfile(root .. '/LuaRules/Gadgets/' .. file .. '.lua'))
    setfenv(chunk,env)()
    return env.gadget
end

local frame, game, units = 0, {}, {[1]={},[2]={},[3]={},[4]={}}
local env = {gadget={}, GG={}, UnitDefNames={npcwisp={id=1}},
    gadgetHandler={IsSyncedCode=function() return true end}}
env.Spring = {
    GetAllUnits=function() return {1,2,3,4} end,
    GetUnitDefID=function() return 1 end,
    GetGameFrame=function() return frame end,
    GetUnitPosition=function() return 0,0,0 end,
    GetGameRulesParam=function(key) return game[key] end,
    SetGameRulesParam=function(key,value) game[key]=value end,
    GetUnitRulesParam=function(id,key) return units[id] and units[id][key] end,
    SetUnitRulesParam=function(id,key,value) assert(units[id]); units[id][key]=value end,
    PlaySoundFile=function() end,
    DestroyUnit=function(id)
        assert(units[id], 'destroyed an already removed wisp')
        env.gadget:UnitDestroyed(id,1)
        units[id]=nil
    end,
}
local deaths = loadGadget('unit_wisp_death',env)
deaths:Initialize()
assert(game.alive_wisps==4)
frame=10; env.GG.KillWisp(1)
frame=20; env.GG.SaveWisp(2,5)
frame=24; deaths:GameFrame(frame); assert(units[2])
frame=25; deaths:GameFrame(frame); assert(not units[2] and game.saved_wisps==1)
frame=30; env.GG.KillWisp(3,2); env.Spring.DestroyUnit(3)
frame=32; deaths:GameFrame(frame); assert(game.killed_wisps==0)
frame=40; env.GG.SaveWisp(4,5)
frame=41; env.GG.KillWisp(4,10)
frame=45; deaths:GameFrame(frame); assert(units[4], 'rescheduling used the old deadline')
frame=51; deaths:GameFrame(frame)
assert(not units[4] and game.saved_wisps==2, 'rescheduling lost the existing saved flag')
frame=54; deaths:GameFrame(frame); assert(units[1])
frame=55; deaths:GameFrame(frame)
assert(not units[1] and game.killed_wisps==1 and game.alive_wisps==0)

local defs, drawn = {[10]=1,[20]=2,[30]=4,[40]=2,[50]=4}, {}
local visual = {gadget={}, UnitDefNames={wisp={id=1},npcwisp={id=2},light={id=3}},
    GL={}, gadgetHandler={IsSyncedCode=function() return false end}}
visual.gl = setmetatable({
    CreateShader=function() return 1 end,
    GetShaderLog=function() return '' end,
    GetUniformLocation=function(_,name) return name end,
    Uniform=function(name,value) if name=='unitID' then drawn[#drawn+1]=value end end,
}, {__index=function() return function() end end})
visual.Spring = {
    GetAllUnits=function() return {10,20,30} end,
    GetUnitDefID=function(id) return defs[id] end,
    SetUnitNoDraw=function() end,
    GetUnitViewPosition=function() return 0,0,0 end,
    GetUnitRulesParam=function() return nil end,
    GetGameRulesParam=function() return 1 end,
    GetGameFrame=function() return 10 end,
    GetFrameTimeOffset=function() return 0 end,
    GetGameSeconds=function() return 1 end,
}
local sprites = loadGadget('unit_wisp_draw',visual)
sprites:Initialize()
local function expect(ids)
    drawn={}; sprites:DrawScreenEffects()
    assert(table.concat(drawn,',')==ids, 'wisp roster: '..table.concat(drawn,','))
end
expect('10,20')
sprites:UnitCreated(40,2); sprites:UnitCreated(50,4); expect('10,20,40')
sprites:UnitDestroyed(20); expect('10,40')
sprites:UnitLeftLos(40); expect('10')
sprites:UnitEnteredLos(40,2); expect('10,40')
print('PASS Parts Needed Lua: death/save deadlines, rescheduling, external destruction, counters, sprite creation/destruction/LOS')
