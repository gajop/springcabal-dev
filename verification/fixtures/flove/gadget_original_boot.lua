function gadget:GetInfo()
	return {
		name    = "original_boot",
		desc    = "Verification helper: skips the difficulty menu and samples wisps",
		author  = "verification",
		layer   = 100,
		enabled = true,
	}
end

if gadgetHandler:IsSyncedCode() then
	return false
end

local SHOT_FRAME = __SHOT_FRAME__
local sent = false

local function closeCamera()
	for _, unitID in ipairs(Spring.GetAllUnits()) do
		local defID = Spring.GetUnitDefID(unitID)
		local def = defID and UnitDefs[defID]
		if def and def.customParams and def.customParams.tree then
			local x, y, z = Spring.GetUnitPosition(unitID)
			if x then
				local cs = Spring.GetCameraState()
				cs.px, cs.py, cs.pz = x, y + 700, z + 700
				cs.dx, cs.dy, cs.dz = 0, -0.7, -0.7
				cs.height = 700
				Spring.SetCameraState(cs, 0)
				Spring.Echo(string.format("[Flove-Wisp-Cam] CLOSE_CAMERA at %.0f,%.0f,%.0f", x, y, z))
				return
			end
		end
	end
end

function gadget:GameFrame(frame)
	if not sent and frame >= 1 then
		sent = true
		Spring.SendLuaRulesMsg("difficulty|1")
	end

	if frame == SHOT_FRAME - 30 then
		closeCamera()
		return
	end

	if frame ~= SHOT_FRAME then
		return
	end

	local trees, wisps = 0, 0
	local stages = { 0, 0, 0 }
	for _, unitID in ipairs(Spring.GetAllUnits()) do
		local defID = Spring.GetUnitDefID(unitID)
		local def = defID and UnitDefs[defID]
		if def and def.customParams and def.customParams.tree then
			trees = trees + 1
			for i = 1, 32 do
				local stage = Spring.GetUnitRulesParam(unitID, "wispStage" .. tostring(i))
				if stage == nil then
					break
				end
				wisps = wisps + 1
				if stage >= 1 and stage <= 3 then
					stages[stage] = stages[stage] + 1
				end
			end
		end
	end
	Spring.Echo(string.format(
		"[Flove-Wisp-Test] original f=%d trees=%d wisps=%d s1=%d s2=%d s3=%d",
		frame, trees, wisps, stages[1], stages[2], stages[3]))
	for _, unitID in ipairs(Spring.GetAllUnits()) do
		local defID = Spring.GetUnitDefID(unitID)
		local def = defID and UnitDefs[defID]
		if def and def.customParams and def.customParams.tree then
			local parts = {}
			for i = 1, 32 do
				local stage = Spring.GetUnitRulesParam(unitID, "wispStage" .. tostring(i))
				if stage == nil then
					break
				end
				local off = Spring.GetUnitRulesParam(unitID, "wispOffset" .. tostring(i))
				parts[#parts + 1] = string.format("s%d/o%s", stage, tostring(off))
			end
			if #parts > 0 then
				Spring.Echo("[Flove-Wisp-Off] unit=" .. unitID .. " " .. table.concat(parts, " "))
			end
		end
	end

	local x, y, z = Spring.GetCameraPosition()
	Spring.Echo(string.format("[Flove-Wisp-Cam] pos=%.0f,%.0f,%.0f", x, y, z))
	Spring.SendCommands("screenshot png")
end
