function gadget:GetInfo()
	return {
		name = "Verification controls observer",
		desc = "Reports bindings and frame state for native Pause/F12 checks",
		author = "springcabal verification",
		license = "GPL v2 or later",
		layer = 1000001,
		enabled = true,
	}
end

if gadgetHandler:IsSyncedCode() then
	return
end

local forbidden = {
	attack = true, areaattack = true, manualfire = true, selfd = true,
	reclaim = true, fight = true, guard = true, cloak = true, loadunits = true,
	move = true, patrol = true, repair = true, resurrect = true, restore = true,
	unloadunits = true, wait = true, stop = true, ["repeat"] = true, onoff = true,
	firestate = true, movestate = true, trajectory = true, stockpile = true,
	controlunit = true, sharedialog = true, deselect = true, aiselect = true,
}

local function log(text)
	Spring.Echo("[controls] " .. text)
end

local function hasKey(action, symbol)
	for _, key in ipairs(Spring.GetActionHotKeys(action) or {}) do
		key = string.lower(key)
		if key == symbol or key:match("%+" .. symbol .. "$") then
			return true
		end
	end
	return false
end

local function checkBindings()
	local ok = true
	local rts = Spring.GetModOptions().controls_rts_test == "1"
	for _, binding in ipairs(Spring.GetKeyBindings()) do
		local command = string.lower(binding.command)
		if not rts and (forbidden[command] or command:match("^select") or command:match("^group")
			or command:match("^build") or command == "specteam") then
			log("FAIL RTS binding " .. binding.boundWith .. " -> " .. binding.command .. " " .. binding.extra)
			ok = false
		end
	end
	for _, required in ipairs({ { "pause", "pause" }, { "screenshot", "f12" }, { "chat", "enter" },
		{ "edit_return", "enter" }, { "edit_backspace", "backspace" }, { "speedup", "=" }, { "slowdown", "-" } }) do
		if not hasKey(required[1], required[2]) then
			log("FAIL missing " .. required[2] .. " -> " .. required[1])
			ok = false
		end
	end
	if rts and (not hasKey("move", "m") or not hasKey("attack", "a") or not hasKey("stop", "s")
		or not hasKey("group1", "1")) then
		log("FAIL missing RTS command or selection bindings")
		ok = false
	end
	log("bindings " .. (ok and "PASS" or "FAIL"))
	return ok
end

local started, sampled
local ready, finished = false, false
local movementTest = Spring.GetModOptions().controls_movement_test == "1"
local movementStart
local movementReleased
local lastWriting
local rtsUnit, groupChecked, moveChecked

local function checkRtsControls()
	if Spring.GetModOptions().controls_rts_test ~= "1" then
		return
	end
	if not rtsUnit then
		for _, unit in ipairs(Spring.GetAllUnits()) do
			if Spring.GetUnitTeam(unit) == Spring.GetMyTeamID() then
				for _, command in ipairs(Spring.GetUnitCmdDescs(unit) or {}) do
					if command.id == CMD.MOVE then
						rtsUnit = unit
						Spring.SelectUnitArray({unit})
						log("RTS unit selected")
						return
					end
				end
			end
		end
		return
	end
	if not groupChecked and Spring.GetUnitGroup(rtsUnit) == 1 then
		groupChecked = true
		log("RTS control group PASS")
	end
	local _, command = Spring.GetActiveCommand()
	if not moveChecked and command == CMD.MOVE then
		moveChecked = true
		log("RTS move command PASS")
	end
end

local function checkMovement()
	if not movementTest then
		return
	end
	local ufo
	for _, unit in ipairs(Spring.GetAllUnits()) do
		if Spring.GetUnitDefID(unit) == UnitDefNames.ufo.id then
			ufo = unit
			break
		end
	end
	if not ufo then
		return
	end
	local x, _, z = Spring.GetUnitPosition(ufo)
	if Spring.GetKeyState(Spring.GetKeyCode("w")) or Spring.GetKeyState(Spring.GetKeyCode("s")) then
		movementStart = movementStart or {x, z}
	elseif movementStart then
		movementReleased = movementReleased or Spring.GetGameFrame()
		if Spring.GetGameFrame() < movementReleased + 30 then
			return
		end
		local dx, dz = x - movementStart[1], z - movementStart[2]
		local distance = math.sqrt(dx * dx + dz * dz)
		log(string.format("movement %s distance=%.1f", distance > 5 and "PASS" or "FAIL", distance))
		movementStart = nil
		movementReleased = nil
	end
end

function gadget:Update()
	local now = Spring.GetTimer()
	started = started or now
	if Spring.GetGameFrame() < 0 or Spring.DiffTimers(now, started) < 0.5 then
		return
	end
	if not ready then
		ready = true
		checkBindings()
	end
	if finished then
		return
	end
	local writing = Spring.IsUserWriting()
	if Spring.GetModOptions().controls_chili_test ~= "1" and writing ~= lastWriting then
		lastWriting = writing
		log("chat writing=" .. (writing and "1" or "0"))
	end
	if not writing then
		checkMovement()
		checkRtsControls()
	end
	if not sampled or Spring.DiffTimers(now, sampled) >= 0.1 then
		sampled = now
		local wanted, _, paused = Spring.GetGameSpeed()
		log("state frame=" .. Spring.GetGameFrame() .. " paused=" .. (paused and "1" or "0"))
		log("speed wanted=" .. wanted)
	end
	if #(VFS.DirList("screenshots", "screen_*.png", VFS.RAW_ONLY) or {}) > 0 then
		finished = true
		checkBindings()
		log("screenshot observed; quitting")
		Spring.SendCommands("quitforce")
	end
end
