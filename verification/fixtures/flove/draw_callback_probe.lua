function gadget:GetInfo()
    return {name = "Flove draw callback probe", desc = "Counts existing DrawUnit dispatch without changing drawing", author = "verification", layer = 100000, enabled = true}
end

if gadgetHandler:IsSyncedCode() then return false end

local counts = {}
local lastReport = Spring.GetTimer()

function gadget:DrawUnit(unitID)
    local def = UnitDefs[Spring.GetUnitDefID(unitID)]
    local name = def and def.name or "unknown"
    counts[name] = (counts[name] or 0) + 1
    return false
end

function gadget:DrawScreen()
    local now = Spring.GetTimer()
    if Spring.DiffTimers(now, lastReport) < 2 then return end
    local parts = {}
    for name, count in pairs(counts) do
        parts[#parts + 1] = name .. "=" .. count
    end
    table.sort(parts)
    Spring.Echo("[Draw-Probe] frame=" .. Spring.GetGameFrame() .. " " .. table.concat(parts, " "))
    counts = {}
    lastReport = now
end
