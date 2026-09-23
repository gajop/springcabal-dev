-- The legacy Lua archive can remain at the pre-game boundary under the
-- headless engine.  Make the probe's simulation start explicit in both runs.

function widget:GetInfo()
	return {
		name = "Gravitas Probe Start",
		desc = "Starts the deterministic unit-script probe",
		author = "springcabal verification",
		license = "GPL v2 or later",
		enabled = true,
	}
end

function widget:Initialize()
	self.elapsed = 0
	self.nextRetry = 0.5
	local options = Spring.GetModOptions() or {}
	self.scenario = options.probe_scenario or options.probe_unit
	self.doneFrame = tonumber(options.probe_done_frame) or 300
	self.quitSent = false
	self.jumpSent = false
	Spring.SendCommands({ "forcestart", "pause 0", "setminspeed 100", "setmaxspeed 100" })
	Spring.Echo("[GravitasProbe] start widget issued forcestart")
end

function widget:Update(dt)
	self.elapsed = self.elapsed + dt
	if not self.quitSent and Spring.GetGameFrame() >= self.doneFrame then
		self.quitSent = true
		Spring.SendCommands("quit")
		return
	end
	if not self.jumpSent and self.scenario == "gravit" and Spring.GetGameFrame() >= 170 then
		self.jumpSent = true
		local x, z = 516, 3394
		local y = Spring.GetGroundHeight(x, z)
		Spring.SendLuaRulesMsg(string.format(
			"gravitas|0|0|%f|%f|%f|-1|0|0|1", x, y, z
		))
		Spring.Echo("[GravitasProbe] widget action=jump-message frame=170")
	end
	if self.elapsed >= self.nextRetry and self.elapsed < 4.0 then
		self.nextRetry = self.nextRetry + 0.5
		Spring.SendCommands({ "forcestart", "pause 0" })
		Spring.Echo("[GravitasProbe] start widget retried forcestart")
	end
end
