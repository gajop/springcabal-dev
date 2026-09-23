-- Replaces game_end.lua only in the isolated unit-script probe archive. The
-- probe needs to keep simulating after collecting all six parts so it can
-- compare corporal-form walking poses instead of entering the ending.

function gadget:GetInfo()
	return {
		name = "Game End",
		desc = "Disabled for the unit-script conformance probe",
		author = "springcabal verification",
		license = "GPL v2 or later",
		layer = 0,
		enabled = true,
	}
end

if gadgetHandler:IsSyncedCode() then
	function gadget:Initialize()
		Spring.SetGameRulesParam("game_over", 0)
		Spring.SetGameRulesParam("game_over_sequence", 0)
	end

	function gadget:GameFrame()
		if Spring.GetGameRulesParam("game_over") ~= 0 then
			Spring.SetGameRulesParam("game_over", 0)
		end
	end
end
