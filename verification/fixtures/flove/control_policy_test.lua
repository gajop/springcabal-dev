-- Run from springcabal-games with lua; no engine or input simulation needed.
local luaGame = "spring-linux/games/Flove.sdd/"
local wasmGame = "spring-linux/games/Flove-wasm.sdd/"
local selections = 0
Spring = {
    GetKeyCode = function(key) return string.byte(key) end,
    SelectUnitArray = function(units) assert(#units == 0); selections = selections + 1 end,
    GetSelectedUnitsCount = function() return 3 end,
}
widget = {}
dofile(luaGame .. "LuaUI/Widgets/gui_no_rts_selection.lua")
assert(widget:KeyPress(97, {ctrl=true}))
assert(widget:KeyPress(100, {ctrl=true}))
assert(not widget:KeyPress(113, {ctrl=true})) -- keep Ctrl+Q
assert(not widget:KeyPress(97, {ctrl=false})) -- keep camera keys
widget:Update()
assert(selections == 3)
assert(widget:CommandNotify())

gadget = {}
gadgetHandler = {IsSyncedCode = function() return true end}
CMD = {SELFD=65}
dofile(luaGame .. "LuaRules/Gadgets/game_command_policy.lua")
for _, command in ipairs({0, 1, 10, 16, 20, 65}) do
    assert(not gadget:AllowCommand(1, 1, 1, command, {}, {}, 0, 0, false))
end
for _, command in ipairs({0, 10, 16, 20}) do
    assert(gadget:AllowCommand(1, 1, 0, command, {}, {}, 0, -1, true))
end
assert(not gadget:AllowCommand(1, 1, 0, CMD.SELFD, {}, {}, 0, -1, true))

dofile(wasmGame .. "LuaUI/main.lua")
local layout = {LayoutButtons(4, 3, 10, {})}
assert(#layout == 11 and layout[1] == "" and layout[2] == 4 and layout[3] == 3)
for i = 4,11 do assert(next(layout[i]) == nil) end

local function equal(a, b)
    assert(type(a) == type(b))
    if type(a) ~= "table" then assert(a == b); return end
    for key,value in pairs(a) do equal(value, b[key]) end
    for key in pairs(b) do assert(a[key] ~= nil) end
end
equal(dofile(luaGame .. "effects/greymuzzle.lua").greymuzzle,
      dofile(wasmGame .. "effects/barf.lua").greymuzzle)

for _,path in ipairs({"wasm-test/flove-start.txt", "verification/fixtures/flove/start.txt"}) do
    local file = assert(io.open(path))
    local script = file:read("*a"):lower()
    file:close()
    assert(script:match("%[player0%]%s*{(.-)}"):match("team=1;"))
    assert(script:match("%[ai0%]%s*{(.-)}"):match("team=0;"))
    assert(script:match("%[team1%]") and script:match("%[allyteam1%]"))
end
print("PASS: Lua input/command guards, empty command layout, matching greymuzzle, and direct/test teams")
