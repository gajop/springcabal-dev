-- Staged only by verification/perf/run.py. The normal game handlers stay
-- active: copies get their regular creation, AI and unit-script callbacks.
function gadget:GetInfo()
    return {name="PerfWorkload", desc="Initial-scene load and frame stepping",
        author="SpringCabal", license="GPL v2 or later", layer=1000002, enabled=true}
end

local options = Spring.GetModOptions() or {}
if not gadgetHandler:IsSyncedCode() then
    function gadget:Initialize()
        if tonumber(options.perf_frame_step) == 1 then
            -- Same engine mechanism used by the existing golden galleries.
            Spring.SetVideoCapturingMode(true)
        end
    end
    return
end

local multiplier = tonumber(options.perf_unit_multiplier) or 1
local scaleFrame = tonumber(options.perf_scale_frame) or 60

local function counts()
    local result = {}
    for _, id in ipairs(Spring.GetAllUnits()) do
        local name = UnitDefs[Spring.GetUnitDefID(id)].name
        local key = name .. ":" .. Spring.GetUnitTeam(id)
        result[key] = (result[key] or 0) + 1
    end
    local keys, parts = {}, {}
    for key in pairs(result) do keys[#keys+1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do parts[#parts+1] = key .. "=" .. result[key] end
    return table.concat(parts, ",")
end

function gadget:GameFrame(frame)
    if frame == tonumber(options.perf_sample_frame) then
        Spring.Echo("[PerfWorkload] measured " .. counts())
    end
    if frame ~= scaleFrame then return end
    local units = Spring.GetAllUnits()
    local initial = #units
    Spring.Echo("[PerfWorkload] initial " .. counts())
    local created, failed = 0, 0
    for _, id in ipairs(units) do
        local def = UnitDefs[Spring.GetUnitDefID(id)]
        local team = Spring.GetUnitTeam(id)
        local x, y, z = Spring.GetUnitPosition(id)
        local health = Spring.GetUnitHealth(id)
        local facing = Spring.GetUnitBuildFacing(id)
        local commands = Spring.GetUnitCommands(id, 32)
        for copy = 1, multiplier - 1 do
            -- Nearby positions on the same map keep the scene recognizable.
            -- This is a stress test; it does not promise identical AI paths.
            local dx = ((copy - 1) % 3 + 1) * 12
            local dz = (math.floor((copy - 1) / 3) + 1) * 12
            local clone = Spring.CreateUnit(def.name,
                math.min(x+dx, Game.mapSizeX-16), y,
                math.min(z+dz, Game.mapSizeZ-16), facing, team)
            if clone then
                created = created + 1
                Spring.SetUnitHealth(clone, health)
                for i, command in ipairs(commands) do
                    Spring.GiveOrderToUnit(clone, command.id, command.params,
                        i == 1 and 0 or {"shift"})
                end
            else
                failed = failed + 1
            end
        end
    end
    local total = #Spring.GetAllUnits()
    local expected = initial * multiplier
    if failed > 0 or total ~= expected then
        Spring.Echo("[PerfWorkload] FAIL initial=" .. initial .. " created=" .. created
            .. " failed=" .. failed .. " expected=" .. expected .. " actual=" .. total)
    else
        Spring.Echo("[PerfWorkload] scaled initial=" .. initial .. " multiplier=" .. multiplier
            .. " created=" .. created .. " total=" .. total)
    end
    Spring.Echo("[PerfWorkload] after " .. counts())
end
