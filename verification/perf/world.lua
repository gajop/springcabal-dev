-- Opt-in observer, staged only into recording runs. Adapted from Ship Game's
-- world-recording observer: read-only snapshots in the unsynced LuaRules state.
-- This is a projection of real engine state, not a simulation in the browser.
local M, file, samples, lastFrame = {}, nil, 0, 0
local detailed = tonumber((Spring.GetModOptions() or {}).perf_record_details) == 1
local function quote(s)
    return '"' .. tostring(s):gsub('[%z\1-\31\\"]', function(c)
        return string.format('\\u%04x', c:byte())
    end) .. '"'
end
local function number(n) return string.format('%.2f', n or 0) end
local function object(value)
    local fields = {}
    for key, item in pairs(value or {}) do
        if type(item) == 'number' then
            fields[#fields+1] = quote(key) .. ':' .. string.format('%.9g', item)
        elseif type(item) == 'boolean' then
            fields[#fields+1] = quote(key) .. ':' .. tostring(item)
        end
    end
    table.sort(fields)
    return '{' .. table.concat(fields, ',') .. '}'
end
local function camera() return object(Spring.GetCameraState()) end

local function write(s)
    local ok, err = file:write(s, '\n')
    if not ok then error('world recording write failed: ' .. tostring(err)) end
end
local function snapshot(_, frame)
    if not file then return end
    local units, shots, details = {}, {}, {}
    for _, id in ipairs(Spring.GetAllUnits()) do
        local x, _, z = Spring.GetUnitPosition(id)
        if x then
            local hp, maxhp = Spring.GetUnitHealth(id)
            units[#units+1] = '[' .. table.concat({id, Spring.GetUnitDefID(id),
                Spring.GetUnitTeam(id), number(x), number(z), number(hp), number(maxhp)}, ',') .. ']'
            if detailed then
                local px, py, pz = Spring.GetUnitPosition(id)
                local vx, vy, vz = Spring.GetUnitVelocity(id)
                local commands = {}
                for _, cmd in ipairs(Spring.GetUnitCommands(id, 32)) do
                    local params = {}
                    for _, value in ipairs(cmd.params) do params[#params+1] = string.format('%.9g', value) end
                    commands[#commands+1] = '[' .. cmd.id .. ',' .. (cmd.options.coded or 0)
                        .. ',[' .. table.concat(params, ',') .. ']]'
                end
                local state = {px, py, pz, Spring.GetUnitHeading(id), vx, vy, vz}
                for i, value in ipairs(state) do state[i] = string.format('%.9g', value) end
                details[#details+1] = '[' .. id .. ',[' .. table.concat(state, ',')
                    .. '],[' .. table.concat(commands, ',') .. '],'
                    .. object(Spring.GetUnitMoveTypeData(id)) .. ',['
                    .. string.format('%.9g,%.9g', Spring.GetUnitRadius(id), Spring.GetUnitHeight(id)) .. ']]'
            end
        end
    end
    for _, id in ipairs(Spring.GetAllProjectiles(false, true)) do
        local x, _, z = Spring.GetProjectilePosition(id)
        if x then shots[#shots+1] = '[' .. table.concat({id, number(x), number(z)}, ',') .. ']' end
    end
    write('{"type":"sample","frame":' .. frame .. ',"camera":' .. camera() .. ',"units":[' .. table.concat(units, ',')
        .. '],"projectiles":[' .. table.concat(shots, ',') .. ']'
        .. (detailed and ',"details":[' .. table.concat(details, ',') .. ']' or '') .. '}')
    samples, lastFrame = samples + 1, frame
end
function M.start(every)
    local err
    file, err = io.open('perf-world.jsonl', 'w')
    if not file then error('world recording open failed: ' .. tostring(err)) end
    local defs, teams = {}, {}
    for id, def in pairs(UnitDefs) do
        defs[#defs+1] = quote(id) .. ':{"name":' .. quote(def.name)
            .. ',"title":' .. quote(def.humanName or def.name) .. '}'
    end
    for _, id in ipairs(Spring.GetTeamList()) do
        local r, g, b = Spring.GetTeamColor(id)
        teams[#teams+1] = quote(id) .. ':[' .. table.concat({number(r), number(g), number(b)}, ',') .. ']'
    end
    write('{"type":"header","format":"springcabal-world","version":1,"fps":30,"sample_frames":'
        .. every .. ',"map":[' .. Game.mapSizeX .. ',' .. Game.mapSizeZ .. '],"defs":{'
        .. table.concat(defs, ',') .. '},"teams":{' .. table.concat(teams, ',') .. '}}')
    if gadgetHandler.AddSyncAction then
        gadgetHandler:AddSyncAction('perf-world-tick', snapshot)
    else
        function RecvFromSynced(tag, frame)
            if tag == 'perf-world-tick' then snapshot(tag, frame) end
        end
    end
end
function M.finish()
    if not file then return end
    write('{"type":"end","samples":' .. samples .. ',"frame":' .. lastFrame .. '}')
    file:close(); file = nil
    if gadgetHandler.RemoveSyncAction then gadgetHandler:RemoveSyncAction('perf-world-tick') end
end
return M
