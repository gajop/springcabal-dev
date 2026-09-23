function gadget:GetInfo()
    return {
        name = "TTLD Lua render fixture",
        desc = "Deterministic boss/large-ork pair for Lua visual verification",
        author = "verification",
        layer = 10000,
        enabled = true,
    }
end

if not gadgetHandler:IsSyncedCode() then
    return
end

local spawned = false

function gadget:GameFrame(frame)
    if spawned or frame < 30 then
        return
    end

    local bloodmageDefID = UnitDefNames.bloodmage.id
    local playerID
    for _, unitID in ipairs(Spring.GetAllUnits()) do
        if Spring.GetUnitDefID(unitID) == bloodmageDefID then
            playerID = unitID
            break
        end
    end
    if not playerID then
        return
    end

    local x, y, z = Spring.GetUnitPosition(playerID)
    local bossID = Spring.CreateUnit("orkboss", x - 220, y, z - 140, 0, 0, false, true)
    local orkbigID = Spring.CreateUnit("orkbig", x + 220, y, z - 140, 0, 0, false, true)
    Spring.SetGameRulesParam("ttld_lua_boss", bossID)
    Spring.SetGameRulesParam("ttld_lua_orkbig", orkbigID)
    Spring.Echo(string.format(
        "[TTLD Lua E2E] fixture boss=%s orkbig=%s origin=(%.0f,%.0f)",
        tostring(bossID), tostring(orkbigID), x, z
    ))
    spawned = true
end
