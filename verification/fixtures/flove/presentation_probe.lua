function gadget:GetInfo()
    return {name = "Flove presentation probe", desc = "Isolated hover and sway fixture", author = "verification", layer = -100000, enabled = true}
end

if gadgetHandler:IsSyncedCode() then
    function gadget:GameFrame(frame)
        if frame ~= 90 then return end
        for level = 1,3 do
            local x,z = 4300 + (level-1)*300, 6100
            local unit = Spring.CreateUnit("treelevel"..level, x,Spring.GetGroundHeight(x,z),z,0,0)
            Spring.SetUnitRulesParam(unit, "presentationProbe", level, {public=true})
            Spring.SetUnitRulesParam(unit, "createdFrame", 0, {public=true})
        end
    end
else
    local paused = false
    local reportFrame = -1
    function gadget:Update()
        if not paused and Spring.GetGameFrame() >= 180 then
            paused = true
            Spring.SendCommands("pause 1")
            Spring.Echo("[Presentation-Probe] paused for hover comparisons")
        end
    end
    function gadget:DrawScreen()
        local frame = Spring.GetGameFrame()
        if frame < 120 or frame == reportFrame then return end
        reportFrame = frame
        if frame % 30 ~= 0 then return end
        local _,height = Spring.GetViewGeometry()
        for _,unit in ipairs(Spring.GetAllUnits()) do
            local level = Spring.GetUnitRulesParam(unit, "presentationProbe")
            if level then
                local x,y,z = Spring.GetUnitPosition(unit)
                local sx,sy = Spring.WorldToScreenCoords(x,y+60,z)
                Spring.Echo(string.format("[Presentation-Probe] level=%d unit=%d screen=(%.0f,%.0f)",level,unit,sx,height-sy))
            end
        end
    end
end
