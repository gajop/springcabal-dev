function gadget:GetInfo()
    return {name = "Spire world-coordinate probe", desc = "Observe real spire shots", author = "verification", layer = -100000, enabled = true}
end

local spire
local function findSpire()
    if spire and Spring.ValidUnitID(spire) then return spire end
    for _, unit in ipairs(Spring.GetAllUnits()) do
        if UnitDefs[Spring.GetUnitDefID(unit)].name == "spire" then spire = unit; return unit end
    end
end

if gadgetHandler:IsSyncedCode() then
    function gadget:Initialize()
        for _, name in ipairs({"zap", "upgradeshot", "flowershot"}) do
            if WeaponDefNames[name] then Script.SetWatchProjectile(WeaponDefNames[name].id, true) end
        end
    end

    function gadget:RecvLuaMsg(msg)
        if msg:match("^zap|") or msg:match("^rmb|") or msg:match("^upgrade|") then
            Spring.Echo("[Spire-Probe] received " .. msg)
        end
        return false
    end

    function gadget:ProjectileCreated(projectile, owner, weapon)
        if owner ~= findSpire() then return end
        local x,y,z = Spring.GetProjectilePosition(projectile)
        local eye = Spring.GetUnitPieceMap(spire).Eye
        local ex,ey,ez = Spring.GetUnitPiecePosDir(spire, eye)
        local lx,ly,lz = Spring.GetUnitPiecePosition(spire, eye)
        local distance = math.sqrt((x-ex)^2 + (y-ey)^2 + (z-ez)^2)
        Spring.Echo(string.format("[Spire-Probe] weapon=%s projectile=%d origin=(%.2f,%.2f,%.2f) eye_world=(%.2f,%.2f,%.2f) eye_local=(%.2f,%.2f,%.2f) distance=%.3f %s",
            WeaponDefs[weapon].name, projectile,x,y,z,ex,ey,ez,lx,ly,lz,distance,
            distance < 1 and "PASS" or "FAIL"))
    end
else
    local fired = false
    function gadget:Update()
        if Spring.GetGameFrame() < 60 or fired or not findSpire() then return end
        fired = true
        local x,y,z = Spring.GetUnitPosition(spire)
        if Spring.GetModOptions().spire_probe_manual ~= "1" then
            Spring.SendLuaRulesMsg(string.format("zap|%f|%f|%f", x+300,Spring.GetGroundHeight(x+300,z+300),z+300))
            Spring.SendLuaRulesMsg("add_mana|100")
            for _, unit in ipairs(Spring.GetAllUnits()) do
                if UnitDefs[Spring.GetUnitDefID(unit)].name == "treelevel1" then
                    Spring.SendLuaRulesMsg("upgrade|" .. unit)
                    break
                end
            end
        end
    end

    local reportedFrame = -1
    function gadget:DrawScreen()
        local frame = Spring.GetGameFrame()
        if frame < 60 or frame % 60 ~= 0 or frame == reportedFrame or not findSpire() then return end
        reportedFrame = frame
        local x,y,z = Spring.GetUnitPosition(spire)
        local sx,sy = Spring.WorldToScreenCoords(x+300,Spring.GetGroundHeight(x+300,z+300),z+300)
        local _,height = Spring.GetViewGeometry()
        Spring.Echo(string.format("[Spire-Probe] terrain click=(%.0f,%.0f)",sx,height-sy))
    end
end
