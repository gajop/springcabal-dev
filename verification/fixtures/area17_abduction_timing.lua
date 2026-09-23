-- Controlled Lua/WASM abduction comparison.
-- The civilian receives CMD.MOVE_STATE=0 (hold position); this test never uses
-- MoveCtrl to anchor it.

local options = Spring.GetModOptions() or {}
local enabled = options.abduction_timing == "1"

function gadget:GetInfo()
	return {
		name = "Area 17 abduction timing comparison",
		desc = "One held civilian directly below one stationary UFO",
		author = "SpringCabal",
		layer = 1000003,
		enabled = enabled,
	}
end

if not enabled or not gadgetHandler:IsSyncedCode() then
	return
end

local SETUP_FRAME = 30
local TIMEOUT_FRAMES = 600
local ufoID
local civilianID
local startFrame
local finished
local setupDone

local function findUfo()
	local defID = UnitDefNames.ufo and UnitDefNames.ufo.id
	if not defID then
		return nil
	end
	for _, unitID in ipairs(Spring.GetAllUnits()) do
		if Spring.GetUnitDefID(unitID) == defID then
			return unitID
		end
	end
	return nil
end

local function finish(frame, result)
	if finished then
		return
	end
	finished = true
	local elapsed = startFrame and (frame - startFrame) or -1
	Spring.Echo(string.format(
		"[Area17-Abduction-Test] RESULT=%s frame=%d elapsed=%d seconds=%.3f ufo=%s civilian=%s",
		result,
		frame,
		elapsed,
		elapsed / 30,
		tostring(ufoID),
		tostring(civilianID)
	))
	Spring.SendCommands("quitforce")
	Spring.SendCommands("quit")
end

local function setup(frame)
	ufoID = findUfo()
	if not ufoID then
		return false
	end

	local x, y, z = Spring.GetUnitPosition(ufoID)
	if not x then
		return false
	end

	-- Keep the existing scenario UFO, but remove every other unit so no other
	-- target can affect the measured capture time.
	for _, unitID in ipairs(Spring.GetAllUnits()) do
		if unitID ~= ufoID then
			Spring.DestroyUnit(unitID, false, true)
		end
	end

	Spring.GiveOrderToUnit(ufoID, CMD.MOVE_STATE, {0}, {})
	Spring.SetUnitRulesParam(ufoID, "beam_enabled", 0)

	local ground = Spring.GetGroundHeight(x, z)
	civilianID = Spring.CreateUnit("civilian", x, ground, z, 0, 1)
	if not civilianID then
		Spring.Echo("[Area17-Abduction-Test] RESULT=CREATE_FAILED")
		return false
	end

	-- This is the only civilian movement command in the test. No MoveCtrl API
	-- is called, so the engine must simulate the held unit normally.
	Spring.GiveOrderToUnit(civilianID, CMD.MOVE_STATE, {0}, {})
	startFrame = frame
	setupDone = true
	Spring.Echo(string.format(
		"[Area17-Abduction-Test] START frame=%d ufo=%d civilian=%d ufo_pos=%.2f,%.2f,%.2f ground=%.2f civilian_move_state=0",
		frame,
		ufoID,
		civilianID,
		x,
		y,
		z,
		ground
	))
	return true
end

function gadget:GameFrame(frame)
	if finished then
		return
	end
	if not setupDone then
		if frame < SETUP_FRAME then
			return
		end
		if not setup(frame) then
			finish(frame, "SETUP_FAILED")
		end
		return
	end

	if not Spring.ValidUnitID(civilianID) then
		finish(frame, "CAPTURED")
		return
	end

	if (frame - startFrame) % 30 == 0 then
		local ux, uy, uz = Spring.GetUnitPosition(ufoID)
		local x, y, z = Spring.GetUnitPosition(civilianID, true)
		local vx, vy, vz = Spring.GetUnitVelocity(civilianID)
		local candidates = Spring.GetUnitsInCylinder(ux, uz, 70) or {}
		local found = false
		for _, unitID in ipairs(candidates) do
			if unitID == civilianID then
				found = true
				break
			end
		end
		local states = Spring.GetUnitStates(civilianID) or {}
		Spring.Echo(string.format(
			"[Area17-Abduction-Test] SAMPLE frame=%d pos=%.2f,%.2f,%.2f velocity=%.4f,%.4f,%.4f in_cylinder=%s candidates=%d floating=%s game_beam=%s ufo_beam=%s move_state=%s",
			frame,
			x or -1,
			y or -1,
			z or -1,
			vx or 0,
			vy or 0,
			vz or 0,
			tostring(found),
			#candidates,
			tostring(Spring.GetGameRulesParam("ufo_floating_units") or ""),
			tostring(Spring.GetGameRulesParam("beam_enabled") or ""),
			tostring(Spring.GetUnitRulesParam(ufoID, "beam_enabled") or ""),
			tostring(states.movestate or "")
		))
	end

	if frame == startFrame + TIMEOUT_FRAMES then
		local x, y, z = Spring.GetUnitPosition(civilianID, true)
		local vx, vy, vz = Spring.GetUnitVelocity(civilianID)
		Spring.Echo(string.format(
			"[Area17-Abduction-Test] TIMEOUT_POS frame=%d pos=%.2f,%.2f,%.2f velocity=%.4f,%.4f,%.4f",
			frame,
			x or -1,
			y or -1,
			z or -1,
			vx or 0,
			vy or 0,
			vz or 0
		))
		finish(frame, "TIMEOUT")
	end
end
