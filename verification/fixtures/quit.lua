-- Verification: end the run with quitforce once the suite is done, so the
-- engine exits normally. A clean exit is what makes spring-headless flush its
-- infolog and lets an ASAN engine run LeakSanitizer; a run killed by the
-- suite's timeout does neither.
--
-- Copied into a staged game archive by vf_quit_when (verification/lib/common.sh).
-- Mod options:
--   vf_quit_markers  markers separated by "||": quit once each has appeared in
--                    the log (plain text; a marker listed N times must appear
--                    N times)
--   vf_quit_fail     plain text that ends the run early (default "ASSERTION FAILED")
--   vf_quit_frame    quit at this game frame at the latest
--   vf_quit_grace    frames to keep running after the last marker (default 30)

function gadget:GetInfo()
	return {
		name = "Verification quit",
		desc = "Quits cleanly when the verification suite is done",
		author = "springcabal verification",
		license = "GPL v2 or later",
		layer = 1000002,
		enabled = true,
	}
end

if gadgetHandler:IsSyncedCode() then
	return
end

local options = Spring.GetModOptions() or {}
local FAIL = options.vf_quit_fail or "ASSERTION FAILED"
local LAST_FRAME = tonumber(options.vf_quit_frame)
local GRACE = tonumber(options.vf_quit_grace) or 30

-- marker text -> occurrences still to see
local pending, remaining = {}, 0
for marker in string.gmatch(options.vf_quit_markers or "", "([^|]+)") do
	pending[marker] = (pending[marker] or 0) + 1
	remaining = remaining + 1
end

local frame = 0
local quitAt, quitting

local function scheduleQuit(reason)
	if not quitAt then
		quitAt = frame + GRACE
		Spring.Echo("[verify-quit] " .. reason .. ", quitting at frame " .. quitAt)
	end
end

local function onConsoleLine(msg)
	if quitAt or string.find(msg, "[verify-quit]", 1, true) then
		return
	end
	if FAIL ~= "" and string.find(msg, FAIL, 1, true) then
		scheduleQuit("failure marker seen")
		return
	end
	for marker, count in pairs(pending) do
		if count > 0 and string.find(msg, marker, 1, true) then
			pending[marker] = count - 1
			remaining = remaining - 1
		end
	end
	if remaining == 0 and next(pending) then
		scheduleQuit("every marker seen")
	end
end

-- The base gadget handler has no AddConsoleLine dispatcher, and it resets the
-- global callins after loading gadgets, so install the engine callin in the
-- real global table (a gadget's own globals live in its environment) and put
-- it back whenever something replaces it. A game's own global is kept.
local installed
local function installConsoleHook()
	if installed and _G.AddConsoleLine == installed then
		return
	end
	local previous = _G.AddConsoleLine
	installed = function(msg, ...)
		onConsoleLine(msg)
		if previous then
			return previous(msg, ...)
		end
	end
	_G.AddConsoleLine = installed
	Script.UpdateCallIn("AddConsoleLine")
end

function gadget:Initialize()
	installConsoleHook()
end

function gadget:GameFrame(n)
	frame = n
	installConsoleHook()
	if LAST_FRAME and n >= LAST_FRAME then
		scheduleQuit("frame limit reached")
	end
	if quitAt and n >= quitAt and not quitting then
		quitting = true
		Spring.SendCommands("quitforce")
	end
end
