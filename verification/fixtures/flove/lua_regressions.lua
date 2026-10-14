-- Run with lua lua_regressions.lua /path/to/Flove.sdd. No checkout writes.
local root = assert(arg[1], 'expected the Lua game directory')
local passed, failed = 0, 0
local function check(name, test)
    local ok, err = pcall(test)
    if ok then passed = passed + 1; print('PASS ' .. name)
    else failed = failed + 1; print('FAIL ' .. name .. ': ' .. tostring(err)) end
end
local function load(file, env)
    setmetatable(env, {__index = _G})
    local chunk = assert(loadfile(root .. '/' .. file))
    setfenv(chunk, env)()
    return env
end
local function noop() end
local function world(file)
    local state = {frame = 0, units = {}, rules = {}, shots = 0}
    local env = {gadget = {}, GG = {}, UnitDefs = {}, UnitDefNames = {spire = {id = 1},
        poisonmushroom = {id = 2}, bigmushroom = {id = 3}},
        WeaponDefNames = {poison = {id = 1}, flowershot = {id = 2},
            zap = {id = 3, reload = 0.7, projectiles = 1, sprayAngle = 0, projectilespeed = 60},
            upgradeshot = {id = 4}},
        gadgetHandler = {IsSyncedCode = function() return true end},
        Script = {SetWatchWeapon = noop}, Spring = {}}
    local s = env.Spring
    s.GetGameFrame = function() return state.frame end
    s.GetAllUnits = function() local ids = {}; for id in pairs(state.units) do ids[#ids+1] = id end; return ids end
    s.GetGameRulesParam = function(k) return state.rules[k] end
    s.SetGameRulesParam = function(k, v) state.rules[k] = v end
    s.GetUnitDefID = function(id) return state.units[id] and state.units[id].def end
    s.GetUnitPosition = function(id) if state.units[id] then return 4000, 100, 4000 end end
    s.GetUnitRulesParam = function(id, k) return assert(state.units[id]).params[k] end
    s.SetUnitRulesParam = function(id, k, v) assert(state.units[id]).params[k] = v end
    s.SpawnProjectile = function(_, params) assert(params.pos[1], 'dead mushroom fired'); state.shots = state.shots + 1; return state.shots end
    s.SpawnCEG, s.PlaySoundFile = noop, noop
    s.DestroyUnit = function(id) env.gadget:UnitDestroyed(id, state.units[id].def); state.units[id] = nil end
    s.GetGroundHeight = function() return 100 end
    s.GetUnitsInCylinder = function() return {} end
    env.GG.UpdateUnitAttributes = noop
    load(file, env)
    return env, state
end
check('destroyed poison mushrooms stop firing even when their ID is reused', function()
    local e,s = world('LuaRules/Gadgets/unit_poisoner.lua')
    s.units[5] = {def = 2, params = {}}
    e.gadget:UnitCreated(5, 2); e.gadget:GameFrame(30)
    assert(s.shots == 1)
    e.Spring.DestroyUnit(5)
    s.units[5] = {def = 3, params = {}}
    e.gadget:GameFrame(60)
    assert(s.shots == 1, 'poison roster retained a destroyed unit')
end)
local function flower_world()
    local e,s = world('LuaRules/Gadgets/unit_field_of_flowers.lua')
    e.Spring.GetProjectilePosition = function() return 4000, 100, 4000 end
    e.GG.SpawnFlowers = function() s.units[5] = {def = 3,params = {}}; s.units[6] = {def = 3,params = {}}; return {5,6} end
    e.gadget:ProjectileCreated(1, 1, 2); e.gadget:ProjectileDestroyed(1)
    return e,s
end
check('flower expiry cannot destroy an unrelated unit with a recycled ID', function()
    local e,s = flower_world()
    e.Spring.DestroyUnit(5); s.units[5] = {def = 2,params = {}}
    e.gadget:GameFrame(400)
    assert(s.units[5] and not s.units[6], 'expiry destroyed the recycled ID')
end)
check('flower expiry survives synchronous destruction callbacks', function()
    local e,s = flower_world()
    e.gadget:GameFrame(400)
    assert(not s.units[5] and not s.units[6])
    e.gadget:GameFrame(401)
end)
check('spire branch count grows and shrinks exactly, including zero power', function()
    local e,s = world('LuaRules/Gadgets/unit_spire_controller.lua')
    s.units[1] = {def = 1,params = {branches = 0}}
    local shown, hidden = 0,0
    e.Spring.UnitScript = {GetScriptEnv = function() return {
        ShowBranchNoThread = function() shown=shown+1; s.units[1].params.branches=s.units[1].params.branches+1 end,
        HideBranchNoThread = function() hidden=hidden+1; s.units[1].params.branches=s.units[1].params.branches-1 end}
    end, CallAsUnit = function(_, f, ...) return f(...) end}
    e.gadget:UnitCreated(1,1)
    s.rules.power = 0; e.gadget:GameFrame(1); assert(shown == 0 and hidden == 0)
    s.rules.power = 400; e.gadget:GameFrame(2); assert(shown == 3 and s.units[1].params.branches == 3)
    e.gadget:GameFrame(3); assert(shown == 3, 'stable power grew another branch')
    s.rules.power = 0; e.gadget:GameFrame(4); assert(hidden == 3 and s.units[1].params.branches == 0)
end)
check('tree initialization rebuilds power instead of doubling the prior total', function()
    local e,s = world('LuaRules/Gadgets/unit_tree.lua')
    e.UnitDefs[4] = {name = 'treelevel1'}
    s.units[4] = {def = 4,params = {}}; s.rules.power = 3
    e.gadget:Initialize(); assert(s.rules.power == 3)
end)
check('upgrade cursor ignores a unit destroyed between ray and def queries', function()
    local e = load('LuaUI/Widgets/ui_spire_controller.lua', {widget = {}, Game = {}, Spring = {
        GetModKeyState = function() return false,false,false,false end,
        IsAboveMiniMap = function() return false end,
        TraceScreenRay = function(_,_,ground) if ground then return 'ground',{4000,100,4000} end; return 'unit',99 end,
        GetUnitDefID = function() return nil end, SendLuaRulesMsg = noop}, UnitDefs = {}})
    assert(e.widget:MousePress(300,300,3))
end)
for _,file in ipairs({'1_tree_normalmapping.lua','1_mushroom_shader.lua'}) do
    check(file .. ' refreshes uniforms after shader replacement', function()
        local queries = 0
        local e = {GL = {BACK = 1}, Spring = {GetGameFrame = function() return 100 end,
            GetUnitHealth = function() return 100,100 end, GetUnitDefID = function() return 1 end,
            GetUnitHeight = function() return 100 end, GetUnitRulesParam = function() return 0 end},
            UnitDefs = {{customParams = {tree = true}}}, gl = {Uniform = noop,
                GetUniformLocation = function(shader) queries=queries+1; return shader end}, include = function() return {} end}
        setmetatable(e,{__index=_G})
        local chunk = assert(loadfile(root .. '/ModelMaterials/' .. file)); setfenv(chunk,e)
        local materials = chunk(); local mat = materials.tree or materials.mushroom
        mat.shader=10; mat.DrawUnit(1,mat); local first=queries
        mat.DrawUnit(1,mat); assert(queries==first)
        mat.shader=20; mat.DrawUnit(1,mat); assert(queries==first*2,'uniforms belong to deleted shader')
    end)
end
print(string.format('Flove Lua regressions: %d passed, %d failed',passed,failed))
os.exit(failed == 0 and 0 or 1)
