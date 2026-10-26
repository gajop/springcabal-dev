-- Exercise the shipped widget, including registration and removal.
-- These reference masks are shared with ttld-shared's host test.
local root = assert(arg[1], "expected the Lua game directory")
local masks = {[0] = 4, [1] = 2, [11652] = 11, [65520] = 5}
for id, expected in pairs(masks) do
    local render
    local env = setmetatable({
        widget = {}, UnitDefNames = {house = {id = 1}},
        Spring = {
            GetAllUnits = function() return {id} end,
            GetUnitDefID = function() return 1 end,
            GetUnitPosition = function() return 100, 20, 200 end,
            GetViewGeometry = function() return 1024, 736 end,
        },
        WG = {
            DeferredLighting_RegisterFunction = function(fn) render = fn end,
            DeferredLighting_UnregisterFunction = function(fn) assert(fn == render) end,
        },
    }, {__index = _G})
    setfenv(assert(loadfile(root .. "/LuaUI/Widgets/ui_house_light.lua")), env)()
    env.widget:Initialize()
    local function mask()
        local _, _, lights, count = render({}, 0, {}, 0)
        local result = 0
        for i = 1, count do
            local light = lights[i]
            assert(light.py == 70 and light.param.radius == 500)
            local corner = (light.px > 100 and 2 or 0) + (light.pz > 200 and 1 or 0)
            result = result + 2 ^ corner
        end
        return result
    end
    assert(mask() == expected, "wrong lamp positions for house " .. id)
    env.widget:UnitDestroyed(id)
    assert(mask() == 0, "destroyed house retained a light")
    env.widget:Shutdown()
end
print("TTLD Lua house lighting: 4 reference masks and removal passed")
