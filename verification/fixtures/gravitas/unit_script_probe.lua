-- Deterministic Gravitas unit-script probe.
--
-- This fixture is copied into isolated Lua and WASM game archives.  It drives
-- the same engine call-ins in both runs and records the final model-relative
-- piece matrices, not implementation-specific script state.

function gadget:GetInfo()
	return {
		name = "Gravitas Unit Script Probe",
		desc = "Samples Gravitas unit-script poses and skeletons",
		author = "springcabal verification",
		license = "GPL v2 or later",
		layer = 1000000,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return
end

local options = Spring.GetModOptions() or {}
local targetName = options.probe_unit or "gravit"
local scenario = options.probe_scenario or targetName
local sampleFrames = {}
local sampleCount = 0
local targetUnit
local enemyUnit
local infoEmitted = false
local started = false
local doneFrame = tonumber(options.probe_done_frame) or 300
local spawnIfMissing = options.probe_spawn_if_missing ~= "0"
local spawnTeam = tonumber(options.probe_team) or Spring.GetGaiaTeamID()
local spawnEnemy = options.probe_enemy == "1"
local enemyName = options.probe_enemy_unit or "gravit"
local enemyTeam = tonumber(options.probe_enemy_team) or 1
local enemyX = tonumber(options.probe_enemy_x) or 516
local enemyZ = tonumber(options.probe_enemy_z) or 3474
local doAim = options.probe_aim ~= "0"
local skipStop = options.probe_skip_stop == "1"

for value in string.gmatch(options.probe_frames or "", "[^,]+") do
	local frame = tonumber(value)
	if frame and frame >= 0 then
		sampleFrames[frame] = true
		sampleCount = sampleCount + 1
		doneFrame = math.max(doneFrame, frame)
	end
end

local function isTarget(unitID)
	local defID = Spring.GetUnitDefID(unitID)
	return defID and UnitDefs[defID] and UnitDefs[defID].name == targetName
end

local function findTarget()
	if targetUnit and Spring.ValidUnitID(targetUnit) then
		return true
	end
	for _, unitID in ipairs(Spring.GetAllUnits()) do
		if isTarget(unitID) then
			targetUnit = unitID
			Spring.Echo(string.format(
				"[GravitasProbe] target unit=%d name=%s scenario=%s",
				targetUnit, targetName, scenario
			))
			return true
		end
	end
	return false
end

local function spawnProbeTarget(frame)
	if targetUnit or not spawnIfMissing or frame ~= 0 then
		return
	end
	local x, z = 396, 3314
	local y = Spring.GetGroundHeight(x, z)
	targetUnit = Spring.CreateUnit(targetName, x, y, z, 0, spawnTeam)
	if targetUnit then
		Spring.Echo(string.format(
			"[GravitasProbe] spawned target unit=%d name=%s frame=%d",
			targetUnit, targetName, frame
		))
		if spawnEnemy then
			local x, z = enemyX, enemyZ
			local y = Spring.GetGroundHeight(x, z)
			enemyUnit = Spring.CreateUnit(enemyName, x, y, z, 0, enemyTeam)
			if enemyUnit then
				Spring.Echo(string.format(
					"[GravitasProbe] spawned enemy unit=%d name=%s frame=%d",
					enemyUnit, enemyName, frame
				))
			end
		end
	end
end

local function emitSkeleton()
	if infoEmitted or not targetUnit then
		return
	end
	infoEmitted = true
	local pieceMap = Spring.GetUnitPieceMap(targetUnit)
	for name, piece in pairs(pieceMap or {}) do
		local info = Spring.GetUnitPieceInfo(targetUnit, piece)
		if info and info.offset then
			local children = info.children or {}
			Spring.Echo(string.format(
				"[GravitasProbe] skeleton piece=%s parent=%s offset=%.6f,%.6f,%.6f children=%s",
				name,
				tostring(info.parent or -1),
				info.offset[1], info.offset[2], info.offset[3],
				table.concat(children, ",")
			))
		end
	end
end

local function emitPose(frame)
	local pieceMap = Spring.GetUnitPieceMap(targetUnit)
	if not pieceMap then
		Spring.Echo(string.format("[GravitasProbe] ERROR frame=%d no-piece-map", frame))
		return
	end
	local names = {}
	for name in pairs(pieceMap) do
		names[#names + 1] = name
	end
	table.sort(names)
	for _, name in ipairs(names) do
		local piece = pieceMap[name]
		local matrix = {Spring.GetUnitPieceMatrix(targetUnit, piece)}
		if #matrix == 16 then
			Spring.Echo(string.format(
				"[GravitasProbe] frame=%d piece=%s m=" ..
					"%.6f,%.6f,%.6f,%.6f," ..
					"%.6f,%.6f,%.6f,%.6f," ..
					"%.6f,%.6f,%.6f,%.6f," ..
					"%.6f,%.6f,%.6f,%.6f",
				frame, name,
				matrix[1], matrix[2], matrix[3], matrix[4],
				matrix[5], matrix[6], matrix[7], matrix[8],
				matrix[9], matrix[10], matrix[11], matrix[12],
				matrix[13], matrix[14], matrix[15], matrix[16]
			))
		else
			Spring.Echo(string.format(
				"[GravitasProbe] ERROR frame=%d matrix-piece=%s",
				frame, name
			))
		end
	end
	Spring.Echo(string.format(
		"[GravitasProbe] SAMPLE_DONE frame=%d pieces=%d",
		frame, #names
	))
end

local function issueMove(frame)
	local x, y, z = Spring.GetUnitPosition(targetUnit)
	if not x then return end
	Spring.GiveOrderToUnit(targetUnit, CMD.MOVE, {x + 240, y, z + 80}, {})
	Spring.Echo(string.format("[GravitasProbe] action=move frame=%d", frame))
end

local function issueAim(frame)
	local x, y, z = Spring.GetUnitPosition(targetUnit)
	if not x then return end
	if enemyUnit and Spring.ValidUnitID(enemyUnit) then
		Spring.SetUnitTarget(targetUnit, enemyUnit, false, true)
		Spring.SetUnitRulesParam(targetUnit, "targetID", enemyUnit)
		Spring.SetUnitRulesParam(targetUnit, "targetCoordX", -1)
		Spring.SetUnitRulesParam(targetUnit, "targetCoordY", -1)
		Spring.SetUnitRulesParam(targetUnit, "targetCoordZ", -1)
	else
		local tx, tz = x + 120, z + 160
		Spring.SetUnitTarget(targetUnit, tx, Spring.GetGroundHeight(tx, tz), tz, false, true)
	end
	Spring.GiveOrderToUnit(targetUnit, CMD.FIRE_STATE, {2}, {})
	Spring.Echo(string.format("[GravitasProbe] action=aim-fire frame=%d", frame))
end

local function issueJump(frame)
	local x, y, z = Spring.GetUnitPosition(targetUnit)
	if not x or not GG.CustomCommands then return end
	local jump = GG.CustomCommands.GetCmdID("CMD_JUMP")
	if not jump then return end
	Spring.GiveOrderToUnit(targetUnit, jump, {x + 120, Spring.GetGroundHeight(x + 120, z + 80), z + 80}, {})
	Spring.Echo(string.format("[GravitasProbe] action=jump frame=%d", frame))
end

local function clearAim(frame)
	Spring.SetUnitTarget(targetUnit, nil)
	Spring.SetUnitRulesParam(targetUnit, "targetID", -1)
	Spring.SetUnitRulesParam(targetUnit, "targetCoordX", -1)
	Spring.SetUnitRulesParam(targetUnit, "targetCoordY", -1)
	Spring.SetUnitRulesParam(targetUnit, "targetCoordZ", -1)
	Spring.GiveOrderToUnit(targetUnit, CMD.STOP, {}, {})
	Spring.Echo(string.format("[GravitasProbe] action=stop frame=%d", frame))
end

local function issueToggle(frame, value)
	Spring.GiveOrderToUnit(targetUnit, CMD.ONOFF, {value}, {})
	Spring.Echo(string.format("[GravitasProbe] action=onoff value=%d frame=%d", value, frame))
end

function gadget:Initialize()
	if sampleCount == 0 then
		Spring.Echo("[GravitasProbe] ERROR probe_frames is empty")
	end
	findTarget()
	if targetUnit then
		emitSkeleton()
	end
end

function gadget:UnitCreated(unitID)
	if not targetUnit and isTarget(unitID) then
		targetUnit = unitID
	end
end

function gadget:UnitDestroyed(unitID)
	if targetUnit == unitID then
		targetUnit = nil
	end
end

function gadget:GameFrame(frame)
	if not targetUnit then
		findTarget()
	end
	spawnProbeTarget(frame)
	if not targetUnit then
		return
	end
	if not infoEmitted then
		emitSkeleton()
	end
	-- The same actions are sent through the engine in both implementations.
	-- Different unit classes use the relevant subset of these transitions.
	if frame == 20 then
		started = true
		if scenario == "gate" or scenario == "plate" then
			issueToggle(frame, 1)
		else
			issueMove(frame)
		end
	elseif frame == 100 then
		if skipStop then
			Spring.Echo(string.format("[GravitasProbe] action=skip-stop frame=%d", frame))
		elseif scenario == "gate" or scenario == "plate" then
			issueToggle(frame, 0)
		else
			clearAim(frame)
		end
	elseif frame == 130 and doAim and scenario ~= "gate" and scenario ~= "plate" then
		issueAim(frame)
	elseif frame == 170 and scenario == "gravit" then
		issueJump(frame)
		if Spring.SendLuaRulesMsg then
			local x, z = 516, 3394
			local y = Spring.GetGroundHeight(x, z)
			Spring.SendLuaRulesMsg(string.format(
				"gravitas|0|0|%f|%f|%f|-1|0|0|1", x, y, z
			))
			Spring.Echo("[GravitasProbe] synced action=jump-message frame=170")
		end
	elseif frame == 230 and scenario ~= "gate" and scenario ~= "plate" then
		clearAim(frame)
	end

	if sampleFrames[frame] then
		emitPose(frame)
	end
	if frame >= doneFrame then
		Spring.Echo(string.format(
			"[GravitasProbe] DONE unit=%d last_frame=%d started=%s",
			targetUnit or -1, doneFrame, tostring(started)
		))
		gadgetHandler:RemoveGadget(self)
	end
end
