-- Run with: lua lua_regressions.lua /absolute/path/to/Hunted.sdd
-- Exercise gameplay callbacks directly; rendering is checked in-engine.
local root = assert(arg[1], "expected the Lua game directory")
local passed, failed = 0, 0
local function check(name, test)
    local ok, err = pcall(test)
    if ok then
        passed = passed + 1
        print("PASS " .. name)
    else
        failed = failed + 1
        print("FAIL " .. name .. ": " .. tostring(err))
    end
end

local function world(file)
    local state = {frame = 0, units = {}, rules = {}, starts = 0, stops = 0, pickups = 0}
    local env = setmetatable({
        gadget = {}, GG = {}, Spring = {},
        gadgetHandler = {IsSyncedCode = function() return true end},
        UnitDefNames = {rabbit = {id = 1}, carrot = {id = 2}, carrot_dropped = {id = 3},
            mine = {id = 4}, burrow = {id = 5}, carrot_carried = {id = 6}},
        Game = {mapSizeX = 6144, mapSizeZ = 6144}, CMD = {},
        Script = {GetSynced = function() return false end},
        VFS = {Include = function() end}, LOG = {ERROR = "error"},
    }, {__index = _G})
    local spring = env.Spring
    local function noop() end
    spring.SetConfigInt, spring.SendCommands = noop, noop
    spring.Log = function(_, _, message) error(message) end
    spring.GetGameFrame = function() return state.frame end
    spring.GetAllUnits = function() return {} end
    spring.GetGameRulesParam = function(key) return state.rules[key] or 0 end
    spring.SetGameRulesParam = function(key, value) state.rules[key] = value end
    spring.ValidUnitID = function(id)
        assert(id ~= nil, "unit id is missing")
        return state.units[id] ~= nil
    end
    spring.GetUnitIsDead = function(id) return not state.units[id] end
    spring.GetUnitDefID = function(id) return assert(state.units[id]).def end
    spring.GetUnitPosition = function(id)
        local unit = assert(state.units[id], "position of a dead unit")
        return unit.x, 0, unit.z, unit.x, 0, unit.z
    end
    spring.GetUnitVelocity = function() return 0, 0, 0, 0 end
    spring.GetHeadingFromVector = function() return 0 end
    spring.GetUnitRulesParam = function(id, key) return assert(state.units[id]).params[key] end
    spring.SetUnitRulesParam = function(id, key, value) assert(state.units[id]).params[key] = value end
    spring.SetUnitMoveGoal, spring.SetUnitBlocking, spring.SetUnitVelocity = noop, noop, noop
    spring.CreateUnit = function(def, x, _, z)
        local id = #state.units + 1
        while state.units[id] do id = id + 1 end
        state.units[id] = {def = def, x = x, z = z, params = {}}
        return id
    end
    spring.DestroyUnit = function(id)
        env.gadget:UnitDestroyed(id, state.units[id].def)
        state.units[id] = nil
    end
    spring.UnitScript = {
        GetScriptEnv = function(id)
            assert(state.units[id], "script of a dead unit")
            return {
                StartBeingStolen = function() state.starts = state.starts + 1 end,
                StopBeingStolen = function() state.stops = state.stops + 1 end,
            }
        end,
        CallAsUnit = function(_, fn, ...) return fn(...) end,
    }
    env.GG.UpdateUnitAttributes = noop
    env.GG.RabbitPickupCarrot = function() state.pickups = state.pickups + 1 end
    env.GG.RabbitDropCarrot = noop
    local chunk = assert(loadfile(root .. "/" .. file))
    setfenv(chunk, env)()
    env.gadget:Initialize()
    local function add(id, def, x, z)
        state.units[id] = {def = def, x = x, z = z, params = {}}
        if env.gadget.UnitCreated then env.gadget:UnitCreated(id, def) end
    end
    return env, state, add
end

check("stealing marks the rabbit and releases a destroyed carrot", function()
    local env, state, add = world("LuaRules/Gadgets/rabbit_ai.lua")
    add(1, 1, 100, 100)
    add(2, 2, 100, 100)
    env.gadget:GameFrame(0)
    assert(state.starts == 1 and state.units[1].params.stealing == 1)
    env.Spring.DestroyUnit(2)
    assert(state.stops == 1 and state.units[1].params.stealing == 0)
    state.frame = 150
    env.gadget:GameFrame(state.frame)
    assert(state.pickups == 0, "rabbit picked up the destroyed carrot")
end)

check("finishing a theft survives synchronous UnitDestroyed", function()
    local env, state, add = world("LuaRules/Gadgets/rabbit_ai.lua")
    add(1, 1, 100, 100)
    add(2, 2, 100, 100)
    env.gadget:GameFrame(0)
    state.frame = 101
    env.gadget:GameFrame(state.frame)
    assert(state.pickups == 1 and not state.units[2])
    assert(state.stops == 1 and state.units[1].params.stealing == 0)
end)

check("a dropped carrot no longer belongs to its old rabbit", function()
    local env, state, add = world("LuaRules/Gadgets/rabbit_carrying.lua")
    add(1, 1, 100, 100)
    local notifications = 0
    env.GG.RabbitFoodDestroyed = function() notifications = notifications + 1 end
    env.GG.RabbitPickupCarrot(1) -- carried carrot 2
    env.GG.RabbitDropCarrot(1)
    env.GG.RabbitPickupCarrot(1) -- carried carrot 3
    env.Spring.DestroyUnit(2)
    assert(notifications == 0, "destroying old dropped food cleared new food")
    env.Spring.DestroyUnit(3)
    assert(notifications == 1, "destroying current food did not notify its rabbit")
end)

check("leaving the widget restores the player's command colors", function()
    local contents, commands = "original colors\n", 0
    local env = setmetatable({widget = {}, Spring = {SendCommands = function() commands = commands + 1 end}}, {__index = _G})
    env.io = {open = function(_, mode)
        if mode == "r" then
            return {read = function() return contents end, close = function() end}
        end
        contents = ""
        return {write = function(_, value) contents = contents .. value end, close = function() end}
    end}
    local chunk = assert(loadfile(root .. "/LuaUI/Widgets/cmd_handle_cmd_colors.lua"))
    setfenv(chunk, env)()
    env.widget:Initialize()
    assert(contents ~= "original colors\n")
    env.widget:Shutdown()
    assert(contents == "original colors\n" and commands == 2)
end)

check("destroyed lighthouses are not updated again", function()
    local env, state, add = world("LuaRules/Gadgets/ui_flashlight.lua")
    add(1, 7, 100, 100)
    state.units[1].params = {lighthouse_x = 100, lighthouse_z = 120}
    env.gadget:UnitCreated(1)
    assert(next(env.GG.flashlights))
    env.Spring.DestroyUnit(1)
    env.gadget:GameFrame()
    assert(not next(env.GG.flashlights))
end)

check("the initial lighthouse scare area matches its published beam", function()
    local area, params = nil, {}
    local env = setmetatable({script = {}, unitID = 1,
        piece = function(name) return name end,
        Turn = function() end, StartThread = function() end,
        GG = {AddScaryArea = function(data) area = data; return data end},
        Spring = {
            GetUnitPosition = function() return 200, 0, 500 end,
            SetUnitRulesParam = function(_, key, value) params[key] = value end,
        }}, {__index = _G})
    local chunk = assert(loadfile(root .. "/Scripts/lighthouse.lua"))
    setfenv(chunk, env)()
    env.script.Create()
    assert(area.x == params.lighthouse_x and area.z == params.lighthouse_z)
end)

for _, initiallyEnabled in ipairs({false, true}) do
    check("restart preserves cheats=" .. tostring(initiallyEnabled), function()
        local cheats, reloads, restart = initiallyEnabled, 0, nil
        local control = {}
        function control:New(options)
            options.Dispose = function() end
            if options.caption == "Restart" then restart = options end
            return options
        end
        local chili = {Screen0 = {AddChild = function() end}}
        for _, kind in ipairs({"Image", "Button", "Checkbox", "Window", "Panel", "ScrollPanel", "StackPanel", "Label", "EditBox"}) do
            chili[kind] = control
        end
        local env = setmetatable({widget = {}, WG = {Chili = chili}, KEYSYMS = {RETURN = 13},
            require = function() end,
            Spring = {
                GetWindowGeometry = function() return 1280, 720 end,
                GetGameRulesParam = function() return 0 end,
                GetGameFrame = function() return 1000 end,
                GetMyAllyTeamID = function() return 0 end,
                IsCheatingEnabled = function() return cheats end,
                SendCommands = function(...)
                    for _, command in ipairs({...}) do
                        if command == "cheat" then cheats = not cheats end
                        if command == "luarules reload" then
                            assert(cheats, "restart attempted with cheats disabled")
                            reloads = reloads + 1
                        end
                    end
                end,
            }}, {__index = _G})
        local chunk = assert(loadfile(root .. "/LuaUI/Widgets/ui_endgame.lua"))
        setfenv(chunk, env)()
        env.widget:Initialize()
        env.widget:GameOver({})
        assert(restart, "restart button missing").OnClick[1]()
        assert(reloads == 1 and cheats == initiallyEnabled)
    end)
end

print(string.format("Hunted Lua regressions: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
