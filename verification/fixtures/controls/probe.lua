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
	for _, binding in ipairs(Spring.GetKeyBindings()) do
		local command = string.lower(binding.command)
		if forbidden[command] or command:match("^select") or command:match("^group")
			or command:match("^build") or command:match("^chat") or command == "specteam" then
			log("FAIL RTS binding " .. binding.boundWith .. " -> " .. binding.command .. " " .. binding.extra)
			ok = false
		end
	end
	for _, required in ipairs({ { "pause", "pause" }, { "screenshot", "f12" } }) do
		if not hasKey(required[1], required[2]) then
			log("FAIL missing " .. required[2] .. " -> " .. required[1])
			ok = false
		end
	end
	log("bindings " .. (ok and "PASS" or "FAIL"))
	return ok
end

local started, sampled
local ready, finished = false, false

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
	if not sampled or Spring.DiffTimers(now, sampled) >= 0.1 then
		sampled = now
		local _, _, paused = Spring.GetGameSpeed()
		log("state frame=" .. Spring.GetGameFrame() .. " paused=" .. (paused and "1" or "0"))
	end
	if #(VFS.DirList("screenshots", "screen_*.png", VFS.RAW_ONLY) or {}) > 0 then
		finished = true
		checkBindings()
		log("screenshot observed; quitting")
		Spring.SendCommands("quitforce")
	end
end
