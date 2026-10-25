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
check('tree growth survives a destroyed spire while waiting for restart', function()
    local e,s = world('LuaRules/Gadgets/unit_poisoner.lua')
    setmetatable(e.UnitDefNames, {__index = function(t,k) local def={id=100}; rawset(t,k,def); return def end})
    e.UnitDefs[1] = {customParams = {}}
    e.UnitDefs[4] = {customParams = {tree = true}}
    s.units[4] = {def = 4,params = {}}
    load('LuaRules/Gadgets/grove_spawner.lua', e)
    e.TryToSpawnANewTreeSomewhereNearToThisTree = function() return true,{x=4100,z=4100} end
    local spawned=0
    e.SpawnATreeHereNOW = function() spawned=spawned+1 end
    e.SpawnTree(); assert(spawned==0)
    s.units[1] = {def=1,params={}}
    e.RecordUnitCreatedFrame(1,1)
    e.SpawnTree(); assert(spawned==1,'live spire stopped tree growth')
    s.units[1]=nil
    e.SpawnTree(); assert(spawned==1,'dead spire grew a weighted tree')
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
check('mushroom target snapshots preserve weighted choices, allies and RNG', function()
    local e, state = world('LuaRules/Gadgets/unit_poisoner.lua')
    local nextDef = 100
    setmetatable(e.UnitDefNames, {__index = function(t, name)
        nextDef = nextDef + 1; local def = {id = nextDef}; rawset(t, name, def); return def
    end})
    setmetatable(e.UnitDefs, {__index = function(t, id)
        local def = {customParams = {}}; rawset(t, id, def); return def
    end})
    e.UnitDefs[4] = {customParams = {tree = true}}
    local positions = {[1] = 1000, [2] = 200, [3] = 50, [4] = 0, [100] = 0}
    for _, id in ipairs({1, 2, 3, 4, 100}) do
        state.units[id] = {def = id == 1 and 1 or 4, params = {}, team = id == 3 and 0 or 1}
    end
    state.units[100].team = 0
    local nearest, positionReads, listReads, randomCalls = 2, 0, 0, 0
    local randomValues = {}
    e.math = setmetatable({random = function()
        randomCalls = randomCalls + 1; return assert(table.remove(randomValues, 1))
    end}, {__index = math})
    e.Spring.GetAllUnits = function() listReads = listReads + 1; return {1, 2, 3, 4, 100} end
    e.Spring.GetUnitPosition = function(id) positionReads = positionReads + 1; return positions[id], 0, 0 end
    e.Spring.GetUnitTeam = function(id) return state.units[id].team end
    e.Spring.GetUnitNearestEnemy = function() return nearest end
    e.Spring.AreTeamsAllied = function(a, b) return a == b end
    load('LuaRules/Gadgets/mushroom_spawner.lua', e); e.gadget:UnitCreated(1, 1)
    randomValues = {0.25}; assert(e.SelectEnemy(100, {}) == 2)
    assert(listReads == 0 and positionReads == 0, 'nearest-only choice scanned targets')
    local snapshot = {}
    randomValues = {0.75, 0.5}; assert(e.SelectEnemy(100, snapshot) == 2,
        'weighted choice targeted an ally or a zero-distance tree')
    local firstReads = positionReads
    randomValues = {0.75, 0.01}; assert(e.SelectEnemy(100, snapshot) == 1)
    assert(listReads == 1 and positionReads == firstReads + 1, 'target snapshot was queried again')
    nearest = 1; randomValues = {0.25, 0.5}; assert(e.SelectEnemy(100, snapshot) == 2,
        'nearest-spire fallback skipped weighted choice')
    assert(randomCalls == 7 and #randomValues == 0, 'target selection changed the RNG sequence')
end)
-- The wisp renderer is Lua in both game variants. Check the three passes
-- against their original vertices and require one rules snapshot per draw.
local renderRoots = {root}
if arg[2] then renderRoots[#renderRoots + 1] = arg[2] end
for _, gameRoot in ipairs(renderRoots) do
    check('wisp stages share one snapshot and survive unit replacement: ' .. gameRoot, function()
        local frame, queries, draws = 1, 0, {}
        local units = {
            [11] = {wispCount = 3, wispStage1 = 1, wispOffset1 = 0.1,
                wispStage2 = 2, wispOffset2 = 0.2, wispStage3 = 3, wispOffset3 = 0.3},
            [12] = {wispCount = 1, wispStage1 = 0, wispOffset1 = 0}, [13] = {},
        }
        local gfx = setmetatable({
            CreateShader = function() return 1 end, CreateList = function() return 1 end,
            BeginEnd = function(_, fn) fn() end,
            Vertex = function(...) draws[#draws + 1] = {...} end,
        }, {__index = function() return noop end})
        local spring = {
            Echo = noop,
            GetAllUnits = function()
                local ids = {}; for _, id in ipairs({11, 12, 13}) do
                    if units[id] then ids[#ids + 1] = id end
                end; return ids
            end,
            GetUnitDefID = function(id) return id == 13 and 2 or 1 end,
            GetUnitPosition = function() return 4096, 8192, 12288 end,
            GetGroundHeight = function() return 8192 end,
            GetDrawFrame = function() return frame end,
            GetUnitRulesParam = function(id, key)
                queries = queries + 1; return assert(units[id])[key]
            end,
        }
        local e = setmetatable({gadget = {}, Spring = spring, gl = gfx, GL = {POINTS = 0},
            UnitDefs = {{customParams = {tree = true}}, {customParams = {}}},
            gadgetHandler = {IsSyncedCode = function() return false end,
                AddChatAction = noop, RemoveChatAction = noop}}, {__index = _G})
        local chunk = assert(loadfile(gameRoot .. '/LuaRules/Gadgets/wisp_animation.lua'))
        setfenv(chunk, e)(); e.gadget:Initialize()
        e.DrawParticles(1)
        local snapshotQueries = queries
        e.DrawParticles(2); e.DrawParticles(3)
        assert(queries == snapshotQueries, 'the stage passes repeated engine queries')
        assert(#draws == 3, 'a wisp stage disappeared or was duplicated')
        for stage, vertex in ipairs(draws) do
            assert(vertex[1] == 1 and vertex[2] == 2 and vertex[3] == 3)
            assert(math.abs(vertex[4] - (0.05 + stage * 0.1)) < 1e-12)
        end
        frame = frame + 1; draws = {}; units[11].wispStage1 = 3
        e.DrawParticles(3); assert(#draws == 2, 'a stage change stayed cached')
        units[11] = nil; e.gadget:UnitDestroyed(11); draws = {}
        e.DrawParticles(3); assert(#draws == 0, 'a destroyed tree stayed cached')
        units[11] = {wispCount = 1, wispStage1 = 3, wispOffset1 = 0.4}
        e.gadget:UnitCreated(11, 1); draws = {}; e.DrawParticles(3)
        assert(#draws == 1 and math.abs(draws[1][4] - 0.45) < 1e-12,
            'a replacement tree reused the old snapshot')
    end)
end
print(string.format('Flove Lua regressions: %d passed, %d failed',passed,failed))
os.exit(failed == 0 and 0 or 1)
