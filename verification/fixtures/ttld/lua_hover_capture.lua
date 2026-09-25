function widget:GetInfo()
    return {
        name = "TTLD Lua hover capture",
        desc = "Captures the Lua boss/large-ork hover rendering",
        author = "verification",
        layer = 10000,
        enabled = true,
    }
end

local function fixtureUnit(name)
    local unitID = Spring.GetGameRulesParam(name)
    if unitID and Spring.ValidUnitID(unitID) then
        return unitID
    end
    return nil
end

local function hoverUnit(label, unitID)
    local x, y, z = Spring.GetUnitPosition(unitID)
    local sx, sy = Spring.WorldToScreenCoords(x, y, z)
    if not sx or not sy then
        Spring.Echo("[TTLD Lua E2E] hover " .. label .. " skipped: no screen position")
        return
    end

    local traceType, tracedID = Spring.TraceScreenRay(sx, sy)
    Spring.WarpMouse(math.floor(sx), math.floor(sy))
    Spring.Echo(string.format(
        "[TTLD Lua E2E] hover %s unit=%d screen=(%.0f,%.0f) trace=%s:%s",
        label, unitID, sx, sy, tostring(traceType), tostring(tracedID)
    ))
end

local phase = 0

function widget:Update()
    local frame = Spring.GetGameFrame()
    if phase == 0 and frame >= 60 then
        Spring.SendCommands("screenshot")
        phase = 1
    elseif phase == 1 and frame >= 80 then
        local unitID = fixtureUnit("ttld_lua_boss")
        if unitID then
            hoverUnit("orkboss", unitID)
            phase = 2
        end
    elseif phase == 2 and frame >= 95 then
        Spring.SendCommands("screenshot")
        phase = 3
    elseif phase == 3 and frame >= 115 then
        local unitID = fixtureUnit("ttld_lua_orkbig")
        if unitID then
            hoverUnit("orkbig", unitID)
            phase = 4
        end
    elseif phase == 4 and frame >= 130 then
        Spring.SendCommands("screenshot")
        phase = 5
    elseif phase == 5 and frame >= 135 then
        -- The suite quits on this (vf_quit_when).
        Spring.Echo("[TTLD Lua E2E] done")
        phase = 6
    end
end
