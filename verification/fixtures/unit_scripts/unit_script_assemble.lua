-- Assemble every Parts Needed pickup at the player for a deterministic
-- fully-assembled corporal-form unit-script comparison.

function gadget:GetInfo()
	return {
		name = "Unit Script Conformance Assembly",
		desc = "Places all six body parts on the player for verification",
		author = "springcabal verification",
		license = "GPL v2 or later",
		layer = -1000000,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return
end

local wisp
local assembled = false
local started = false
local hideAfterPickup = false

local function findUnits()
	local parts = {}
	for _, unitID in ipairs(Spring.GetAllUnits()) do
		local unitDef = UnitDefs[Spring.GetUnitDefID(unitID)]
			if unitDef then
				if unitDef.customParams.wisp and unitDef.customParams.player and not wisp then
					wisp = unitID
					Spring.Echo(string.format("[UnitScriptProbeAssembly] PLAYER_WISP unit=%d", wisp))
			elseif unitDef.customParams.bodypart then
				parts[#parts + 1] = unitID
			end
		end
	end
	return parts
end

local function assemble(frame)
	if assembled then
		return
	end

	local count = 0
	for _, name in ipairs({ "eyes", "ears", "arms", "legs", "nose", "mouth" }) do
		if Spring.GetGameRulesParam("has_" .. name) == 1 then
			count = count + 1
		end
	end
	if count == 6 then
		assembled = true
		hideAfterPickup = true
		Spring.Echo(string.format(
			"[UnitScriptProbeAssembly] COLLECTED frame=%d parts=%d",
			frame, count
		))
	else
		Spring.Echo(string.format(
			"[UnitScriptProbeAssembly] ERROR frame=%d expected=6 found=%d",
			frame, count
		))
	end
end

function gadget:RecvLuaMsg(message)
	if message == "probe_begin" then
		started = true
	end
end

function gadget:GameFrame(frame)
	if not wisp then
		findUnits()
	end
	if not started or not wisp then
		return
	end
	-- Keep the UI as the test entry point, but make the scenario itself
	-- simulation-frame deterministic in both the Lua and WASM rules paths.
	if frame == 43 then
		-- Let the original power-up gadget perform the pickup.  It is the code
		-- that updates pieceStatus and invokes SetPieceVisibleNoThread, which is
		-- important because the Lua unit script chooses the walk/float path from
		-- those statuses.
		Spring.SetGameRulesParam("spiritMode", 0)
		local x, y, z = Spring.GetUnitPosition(wisp)
		for _, unitID in ipairs(findUnits()) do
			Spring.SetUnitPosition(unitID, x, y, z)
		end
	elseif frame >= 45 and frame <= 46 and not assembled then
		assemble(frame)
	elseif frame == 46 and hideAfterPickup then
		hideAfterPickup = false
		Spring.SetGameRulesParam("spiritMode", 1)
	elseif frame == 89 and assembled then
		Spring.SetGameRulesParam("spiritMode", 0)
	elseif frame >= 105 and frame <= 170 then
		local x, y, z = Spring.GetUnitPosition(wisp)
		Spring.SetUnitMoveGoal(wisp, x + 120, y, z, 16, nil, true)
	end
end
