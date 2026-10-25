function gadget:GetInfo()
	return {
		name    = "force_wisps",
		desc    = "Verification helper: shoots the grove with natural wisps, then with pinned wisps",
		author  = "verification",
		layer   = 100,
		enabled = true,
	}
end

local STAGE = __STAGE__
local FORCE_START = __FORCE_START__
local COUNT = __COUNT__
local SHOT_NATURAL = __SHOT_NATURAL__
local PIN_FROM = __PIN_FROM__
local SHOT_PINNED = __SHOT_PINNED__

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

-- Camera access and screenshot commands belong to unsynced rules. The synced
-- half pins gameplay state and sends the requests at the original frames.
if not gadgetHandler:IsSyncedCode() then
    local quitAfterDraw
    function gadget:Initialize()
        if FORCE_START == 1 then Spring.SendCommands({"forcestart", "pause 0"}) end
        gadgetHandler:AddSyncAction("flove_wisp_camera", closeCamera)
        gadgetHandler:AddSyncAction("flove_wisp_capture", function(_, final)
            Spring.SendCommands("screenshot png")
            if final then quitAfterDraw = Spring.GetDrawFrame() + 3 end
        end)
    end
    function gadget:Shutdown()
        gadgetHandler:RemoveSyncAction("flove_wisp_camera")
        gadgetHandler:RemoveSyncAction("flove_wisp_capture")
    end
    function gadget:Update()
        if quitAfterDraw and Spring.GetDrawFrame() >= quitAfterDraw then
            quitAfterDraw = nil
            Spring.Echo("FLOVE WISP CAPTURE DONE")
            Spring.SendCommands("quitforce")
        end
    end
    return
end

local offsets = {}
for i = 1, COUNT do
	offsets[i] = (i - 1) * (0.25 / COUNT)
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


function gadget:GameFrame(frame)
	if frame == SHOT_NATURAL then
		report("natural", frame)
		SendToUnsynced("flove_wisp_capture", false)
		return
	end

	if frame == SHOT_PINNED - 30 then
		SendToUnsynced("flove_wisp_camera")
		return
	end

	if frame == SHOT_PINNED then
		report("pinned", frame)
		SendToUnsynced("flove_wisp_capture", true)
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
