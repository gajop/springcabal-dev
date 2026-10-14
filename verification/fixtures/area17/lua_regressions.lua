-- Run with: lua lua_regressions.lua /absolute/path/to/Area-17.sdd
local root = assert(arg[1], 'expected Lua game directory')
local passed, failed = 0, 0
local function check(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print('PASS ' .. name)
    else failed = failed + 1; print('FAIL ' .. name .. ': ' .. tostring(err)) end
end
local function load(file, env)
    setmetatable(env, {__index = _G})
    local fn = assert(loadfile(root .. '/' .. file))
    if setfenv then setfenv(fn, env) else fn = assert(loadfile(root .. '/' .. file, 't', env)) end
    fn()
    return env
end
local function near(actual, expected)
    assert(math.abs(actual - expected) < 0.00001, tostring(actual) .. ' ~= ' .. tostring(expected))
end
check('command colors restore through Shutdown', function()
    local original, stored = 'custom user colors\n', 'custom user colors\n'
    local e = {widget = {}, Spring = {SendCommands = function() end}, os = {remove = function() stored = nil end}}
    e.io = {open = function(_, mode)
        if mode == 'r' and not stored then return nil end
        if mode ~= 'r' then stored = '' end
        return {read = function() return stored end, close = function() end,
            write = function(_, text) stored = stored .. text end}
    end}
    load('LuaUI/Widgets/cmd_handle_cmd_colors.lua', e)
    e.widget:Initialize(); assert(stored ~= original)
    assert(e.widget.Shutdown, 'Shutdown callin missing'); e.widget:Shutdown(); assert(stored == original)
    stored = nil; e.widget:Initialize(); e.widget:Shutdown(); assert(stored == nil)
end)
check('human screams and restarts float animation on later lifts', function()
    local sounds, starts = 0, 0
    local e = {script = {}, unitID = 1, UnitDefNames = {alien = {id = 2}}, VFS = {Include = function() return {} end},
        Spring = {GetUnitDefID = function() return 1 end, GetUnitPosition = function() return 0,0,0 end,
            PlaySoundFile = function() sounds = sounds + 1 end},
        piece = function(name) return name end, Signal = function() end,
        StartThread = function() starts = starts + 1 end, x_axis = 1, y_axis = 2, z_axis = 3}
    load('Scripts/human.lua', e)
    e.Abduction_float(); e.Abduction_float(); assert(sounds == 1 and starts == 1, 'one lift restarted or screamed twice')
    e.script.StartMoving(); e.Abduction_float(); assert(sounds == 2 and starts == 3, 'walking human could not float again')
    e.script.StopMoving(); e.Abduction_float(); assert(sounds == 3 and starts == 5, 'standing human could not float again')
end)
check('tank waits for its turret rotation before firing', function()
    local turns, waits = {}, {}
    local e = {script = {}, include = function() end, piece = function(name) return name end,
        x_axis = 1, y_axis = 2, z_axis = 3, Signal = function() end, SetSignalMask = function() end,
        Turn = function(piece, axis) turns[piece] = axis end,
        WaitForTurn = function(piece, axis) waits[piece] = axis end}
    load('Scripts/tank.lua', e); e.script.AimWeapon(1, 1, 1)
    assert(turns.turret == waits.turret, 'waiting on an axis that never turns')
end)
local function fall(normal, velocity)
    local bounced
    local e = {gadget = {}, GG = {}, CMD = {WAIT = 5}, gadgetHandler = {IsSyncedCode = function() return true end},
        Game = {mapX = 1, mapY = 1, gravity = 130},
        UnitDefs = {{id = 1, customParams = {}, health = 1000, mass = 100, speed = 10}}, WeaponDefs = {},
        Spring = {GetGameFrame = function() return 0 end, GetUnitAllyTeam = function() return 0 end,
            AddUnitDamage = function() end, ValidUnitID = function() return true end,
            GetUnitVelocity = function() return unpack(velocity) end,
            GetUnitPosition = function() return 100,0,100 end,
            GetGroundNormal = function() return unpack(normal) end,
            GetUnitArmored = function() return false,1 end, SetUnitVelocity = function() end,
            AddUnitImpulse = function(_, x,y,z) bounced = {x,y,z} end, GiveOrderToUnit = function() end}}
    load('LuaRules/Gadgets/unit_fall_damage.lua', e)
    local damage = e.gadget:UnitPreDamaged(1,1,0,1,false,-2)
    return bounced, damage
end
check('flat impact bounces upward with restitution', function()
    local bounce, damage = fall({0,1,0}, {0,-10,0})
    near(bounce[2],5); near(damage,420)
end)
check('slope impact preserves tangent friction and normal restitution', function()
    local k = math.sqrt(0.5)
    local bounce, damage = fall({k,k,0}, {0,-10,0})
    near(bounce[1],6.5); near(bounce[2],-1.5); near(bounce[3],0)
    near(damage,(math.sqrt(62.5)-3)*60)
end)
check('haste preserves upgraded weapon reloads and handles acceleration alone', function()
    local reloadWrites, moves = 0, 0
    local params = {selfMoveSpeedChange = 1.6, selfMaxAccelerationChange = 1.6}
    local noop = function() end
    local e = {gadget = {}, GG = {}, gadgetHandler = {IsSyncedCode = function() return true end},
        UnitDefs = {{id = 1, canFly = true, isHoveringAirUnit = true, speed = 200, turnRate = 100,
            maxAcc = 1, maxDec = 1, weapons = {{weaponDef = 1}}}},
        WeaponDefs = {{reload = 20, salvoDelay = 0, type = 'MissileLauncher'}},
        Spring = {ValidUnitID = function() return true end, GetUnitDefID = function() return 1 end,
            GetGameFrame = function() return 10 end, GetUnitRulesParam = function(_,key) return params[key] end,
            SetUnitRulesParam = noop, SetUnitBuildSpeed = noop, GiveOrderToUnit = noop,
            GetUnitWeaponState = function(_,_,key) return key == 'reloadTime' and 10 or 50 end,
            SetUnitWeaponState = function() reloadWrites = reloadWrites + 1 end,
            GetUnitMoveTypeData = function() return {name = 'gunship'} end,
            MoveCtrl = {GetTag = function() end, SetAirMoveTypeData = noop, SetGroundMoveTypeData = noop,
                SetGunshipMoveTypeData = function() moves = moves + 1 end}}}
    load('LuaRules/Gadgets/unit_attributes.lua', e)
    e.UpdateUnitAttributes(1); assert(reloadWrites == 0, 'haste overwrote weapon reloads')
    params = {selfMaxAccelerationChange = 2}; e.UpdateUnitAttributes(1)
    assert(moves == 2, 'acceleration-only change was ignored')
end)
check('Escape closes the technology panel', function()
    local disposed = 0
    local element = {New = function(_, properties) return properties end}
    local window = {New = function() return {Dispose = function() disposed = disposed + 1 end} end}
    local e = {widget = {}, UnitDefNames = {ufo = {id = 1}}, KEYSYMS = {T = 116, ESCAPE = 27},
        require = function() end, Spring = {PlaySoundFile = function() end},
        Chili = {Button = element, Label = element, Image = element, Window = window},
        Tech = {GetTechTree = function() return {} end}}
    load('LuaUI/Widgets/gui_upgrade.lua', e)
    -- Chili is assigned through Initialize, as it is in the engine.
    e.WG = {Chili = e.Chili}; e.Spring.GetViewGeometry = function() return 1000,700 end
    e.Spring.GetAllUnits = function() return {} end; e.VFS = {Include = function() end}
    e.widget:Initialize(); e.ToggleUpgradeUI()
    assert(e.widget:KeyPress(27,{},false) == true and disposed == 1)
end)
check('point-defense reload follows each weapon definition', function()
    local writes = {}
    local weapons = {}
    for slot=1,16 do weapons[slot] = {weaponDef = slot} end
    local defs = {}
    for slot=1,16 do defs[slot] = {reload = slot} end
    local e = {gadget = {}, GG = {}, gadgetHandler = {IsSyncedCode = function() return true end},
        UnitDefNames = {ufo = {id = 1}}, UnitDefs = {{weapons = weapons}}, WeaponDefs = defs,
        Spring = {SetUnitWeaponState = function(_,slot,state) writes[slot] = state.reloadTime end}}
    load('LuaRules/Gadgets/weapon_multshot.lua',e)
    e.gadget:Initialize(); e.gadget:UnitCreated(1,1,0); e.GG.SetPDReload(1.75)
    for slot=13,16 do near(writes[slot],slot/1.75) end
end)
check('RTS commands are blocked while development orders remain usable', function()
    local dev = 0
    local e = {widget = {}, Spring = {GetGameRulesParam = function() return dev end}}
    load('LuaUI/Widgets/ui_hide_default_layout.lua',e)
    assert(e.widget:CommandNotify() == true)
    assert(e.widget:UnitCommandNotify(1, 10, {}, {}) == true)
    dev = 1; assert(e.widget:CommandNotify() == false)
    assert(e.widget:UnitCommandNotify(1, 10, {}, {}) == false)
end)
check('alien callbacks tolerate failed creation and missing scripts', function()
    local e = {gadget = {}, GG = {}, CMD = {IDLEMODE = 0}, UnitDefNames = {ufo = {id = 1}, alien = {id = 2}},
        gadgetHandler = {IsSyncedCode = function() return true end},
        Spring = {Utilities = {Vector = {}}, GiveOrderToUnit = function() end, SetGameRulesParam = function() end,
            GetUnitPosition = function() return 0,0,0 end, GetGameFrame = function() return 0 end,
            CreateUnit = function() end, UnitScript = {GetScriptEnv = function() end}}}
    load('LuaRules/Gadgets/unit_ufo_controller.lua',e)
    e.gadget:UnitCreated(1,1); e.gadget:UnitDestroyed(1,1)
    e.gadget:GameFrame(10); e.gadget:GameFrame(20)
    e.Spring.CreateUnit = function() return 2 end
    e.gadget:UnitCreated(3,1); e.gadget:UnitDestroyed(3,1)
    e.gadget:GameFrame(10); e.gadget:GameFrame(20)
end)
check('rejected purchases do not apply gameplay effects', function()
    local e = {gadget = {}, UnitDefNames = {ufo = {id = 1}, alien = {id = 2}},
        gadgetHandler = {IsSyncedCode = function() return true end},
        GG = {Tech = {UnlockTech = function() return false end, UpgradeTech = function() return false end,
            GetTech = function() error('rejected purchase applied effects') end}},
        LOG = {ERROR = 1}, Spring = {Log = function() end,
            SetUnitRulesParam = function() error('rejected unlock applied effects') end}}
    load('LuaRules/Gadgets/upgrades.lua',e)
    e.gadget:RecvLuaMsg('unlock|antiMissilePointDefense')
    e.gadget:RecvLuaMsg('upgrade|armor')
end)
print(string.format('%d passed; %d failed', passed, failed))
if failed > 0 then os.exit(1) end
