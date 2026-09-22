function widget:GetInfo()
    return {name = "Flove CEG probe", desc = "Isolated rendering regression probe", author = "verification", layer = -100, enabled = true, handler = true}
end

local started, skipped, cameraSet, fired, paused
local elapsed, capture = 0, 0
local spire, tree
local disableAlphaTest = false
local reportedAlpha = false

function widget:DrawWorldPreParticles(above, below, reflection, refraction)
    if reflection or refraction then return end
    if paused and not reportedAlpha then
        Spring.Echo("[CEG-Probe] pre-particles alpha-test=" .. tostring(gl.GetNumber(0x0BC0)) .. " func=" .. tostring(gl.GetNumber(0x0BC1)) .. " ref=" .. tostring(gl.GetNumber(0x0BC2)))
        reportedAlpha = true
    end
    if disableAlphaTest then gl.AlphaTest(false) end
end

function widget:Update(dt)
    local f = Spring.GetGameFrame()
    if f < 1 then return end
    if not paused then
        local _,_,isPaused = Spring.GetGameSpeed()
        if isPaused then Spring.SendCommands("pause 0") end
    end
    if not started then
        local story = widgetHandler:FindByName("Story Display")
        if not story then return end
        story.StartGame(1)
        started = true
        Spring.Echo("[CEG-Probe] started through Story Display.StartGame")
    end
    if not skipped and f >= 10 then
        local story = widgetHandler:FindByName("Story Display")
        story.SkipTutorial()
        if story.window then story.window:Hide() end
        skipped = true
        Spring.Echo("[CEG-Probe] tutorial skipped")
    end
    if not cameraSet and f >= 40 then
        for _, u in ipairs(Spring.GetAllUnits()) do
            local def = UnitDefs[Spring.GetUnitDefID(u)]
            if def.name == "spire" then spire = u end
            if def.customParams.tree then tree = tree or u end
        end
        if not spire then return end
        local x,y,z = Spring.GetUnitPosition(spire)
        local ex,ey,ez = Spring.GetUnitPiecePosDir(spire, Spring.GetUnitPieceMap(spire).Eye)
        Spring.Echo(string.format("[CEG-Probe] spire=%d pos=%.2f,%.2f,%.2f eye=%.2f,%.2f,%.2f ground=%.2f", spire,x,y,z,ex,ey,ez,Spring.GetGroundHeight(x,z)))
        WG.ResetCamera()
        local camera = Spring.GetCameraState()
        camera.dist = camera.dist * 1.35
        Spring.SetCameraState(camera, 0)
        Spring.SendCommands("softparticles 1")
        cameraSet = true
    end
    if cameraSet and not fired and f >= 150 then
        local x,y,z = Spring.GetUnitPosition(spire)
        Spring.SendLuaRulesMsg(string.format("zap|%f|%f|%f", x+250,Spring.GetGroundHeight(x+250,z+200),z+200))
        if tree then Spring.SendLuaRulesMsg("upgrade|" .. tree) end
        Spring.Echo("[CEG-Probe] requested zap and upgrade, mana=" .. tostring(Spring.GetGameRulesParam("mana")))
        fired = true
    end
    if fired and not paused and f >= 158 then
        Spring.SendCommands("pause 1")
        paused = true
        Spring.Echo("[CEG-Probe] paused for identical-scene settings comparison, frame=" .. f)
    end
    if not paused then return end
    elapsed = elapsed + dt
    if capture == 0 and elapsed >= 1 then
        Spring.SendCommands("screenshot png")
        Spring.Echo("[CEG-Probe] capture soft=1")
        capture = 1
    elseif capture == 1 and elapsed >= 2 then
        Spring.SendCommands("softparticles 0")
        capture = 2
    elseif capture == 2 and elapsed >= 3 then
        Spring.SendCommands("screenshot png")
        Spring.Echo("[CEG-Probe] capture soft=0")
        capture = 3
    elseif capture == 3 and elapsed >= 4 then
        disableAlphaTest = true
        capture = 4
    elseif capture == 4 and elapsed >= 5 then
        Spring.SendCommands("screenshot png")
        Spring.Echo("[CEG-Probe] capture alpha-test disabled")
        capture = 5
    elseif capture == 5 and elapsed >= 6 then
        disableAlphaTest = false
        if Spring.GetModOptions().ceg_force_legacy == "1" then
            Spring.SendCommands("unitdrawer 0")
            Spring.Echo("[CEG-Probe] forced legacy unit drawer")
        end
        reportedAlpha = false
        capture = 6
    elseif capture == 6 and elapsed >= 7 then
        Spring.SendCommands("screenshot png")
        Spring.Echo("[CEG-Probe] capture without alpha-test override")
        capture = 7
    elseif capture == 7 and elapsed >= 8 then
        Spring.Echo("[CEG-Probe] COMPLETE")
        Spring.SendCommands("quitforce")
    end
end
