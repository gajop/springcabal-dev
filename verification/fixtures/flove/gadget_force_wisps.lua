function gadget:GetInfo()
	return {
		name    = "force_wisps",
		desc    = "Verification helper: shoots the grove with natural wisps, then with pinned wisps",
		author  = "verification",
		layer   = 100,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local STAGE = __STAGE__
local FORCE_START = __FORCE_START__
local COUNT = __COUNT__
local SHOT_NATURAL = __SHOT_NATURAL__
local PIN_FROM = __PIN_FROM__
local SHOT_PINNED = __SHOT_PINNED__

local offsets = {}
for i = 1, COUNT do
	offsets[i] = (i - 1) * (0.25 / COUNT)
end

function gadget:Initialize()
	if FORCE_START == 1 then
		Spring.SendCommands("forcestart")
		Spring.SendCommands("pause 0")
	end
end

local function trees()
	local found = {}
	for _, unitID in ipairs(Spring.GetAllUnits()) do
		local defID = Spring.GetUnitDefID(unitID)
		local def = defID and UnitDefs[defID]
		if def and def.customParams and def.customParams.tree then
			found[#found + 1] = unitID
		end
	end
	return found
end

local function report(tag, frame)
	local list = trees()
	local total, stages = 0, { 0, 0, 0 }
	for _, unitID in ipairs(list) do
		local count = Spring.GetUnitRulesParam(unitID, "wispCount") or 0
		total = total + count
		for i = 1, count do
			local stage = Spring.GetUnitRulesParam(unitID, "wispStage" .. tostring(i))
			if stage and stage >= 1 and stage <= 3 then
				stages[stage] = stages[stage] + 1
			end
		end
	end
	Spring.Echo(string.format(
		"[Flove-Wisp-Test] %s f=%d trees=%d wisps=%d s1=%d s2=%d s3=%d",
		tag, frame, #list, total, stages[1], stages[2], stages[3]))

	for i = 1, math.min(#list, 4) do
		local ux, uy, uz = Spring.GetUnitPosition(list[i])
		if ux then
			Spring.Echo(string.format(
				"[Flove-Wisp-Pos] unit=%d unitY=%.1f groundY=%.1f delta=%.1f",
				list[i], uy, Spring.GetGroundHeight(ux, uz), uy - Spring.GetGroundHeight(ux, uz)))
		end
	end
end

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
	if frame == SHOT_NATURAL then
		report("natural", frame)
		Spring.SendCommands("screenshot png")
		return
	end

	if frame == SHOT_PINNED - 30 then
		closeCamera()
		return
	end

	if frame == SHOT_PINNED then
		report("pinned", frame)
		Spring.SendCommands("screenshot png")
		return
	end

	if STAGE < 0 or frame < PIN_FROM or frame % 15 ~= 0 then
		return
	end

	for _, unitID in ipairs(trees()) do
		Spring.SetUnitRulesParam(unitID, "wispCount", COUNT, { public = true })
		for i = 1, COUNT do
			Spring.SetUnitRulesParam(unitID, "wispStage" .. tostring(i), STAGE, { public = true })
			Spring.SetUnitRulesParam(unitID, "wispOffset" .. tostring(i), offsets[i], { public = true })
		end
	end
end
