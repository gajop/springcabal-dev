-- Deterministic Flove Lua/CUS unit-script conformance probe.
--
-- The harness stages either Flove.sdd or Flove-wasm.sdd, removes the normal
-- gameplay gadgets, and copies this gadget into the staged archive.  Both
-- runtimes therefore receive the same units and the same frame-scheduled
-- movement/attack actions.  The trace contains the model skeleton and the
-- engine's final per-piece matrices for every sampled frame.

function gadget:GetInfo()
	return {
		name = "Flove animation conformance probe",
		desc = "Exports deterministic Flove unit-script skeletons and poses",
		author = "springcabal verification",
		license = "GPL v2 or later",
		layer = 1000000,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return
end

local CASES = {
	{ name = "normal", def = "normalmushroom", x = 5000, z = 4250 },
	{ name = "small", def = "smallmushroom", x = 5250, z = 4250 },
	{ name = "big", def = "bigmushroom", x = 5500, z = 4250 },
	{ name = "cluster", def = "mushroomcluster", x = 5750, z = 4250 },
	{ name = "poison", def = "poisonmushroom", x = 5000, z = 4750 },
	{ name = "bomb", def = "bombmushroom", x = 5250, z = 4750 },
	{ name = "king", def = "kingshroom", x = 5500, z = 4750 },
}

local units = {}
local deadCases = {}
local target
local created = false
local traceDone = false

local function echo(format, ...)
	Spring.Echo(string.format("[FloveAnimTrace] " .. format, ...))
end

local function sortedKeys(map)
	local keys = {}
	for key in pairs(map) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	return keys
end

local function emitSkeleton(case, unitID)
	local pieceMap = Spring.GetUnitPieceMap(unitID) or {}
	for _, name in ipairs(sortedKeys(pieceMap)) do
		local info = Spring.GetUnitPieceInfo(unitID, pieceMap[name])
		if not info then
			echo("ERROR skeleton case=%s piece=%s", case.name, name)
		else
			local offset = info.offset or { 0, 0, 0 }
			echo(
				"SKELETON case=%s piece=%s parent=%s offset=%.9f,%.9f,%.9f",
				case.name,
				name,
				info.parent or "",
				offset[1] or 0,
				offset[2] or 0,
				offset[3] or 0
			)
		end
	end
end

local function emitPose(frame, case, unitID)
	local pieceMap = Spring.GetUnitPieceMap(unitID) or {}
	local rootPiece = Spring.GetUnitRootPiece(unitID)
	local rootMatrix = rootPiece and { Spring.GetUnitPieceMatrix(unitID, rootPiece) } or {}
	local rootX = rootMatrix[13] or 0
	local rootY = rootMatrix[14] or 0
	local rootZ = rootMatrix[15] or 0
	local count = 0
	for _, name in ipairs(sortedKeys(pieceMap)) do
		local matrix = { Spring.GetUnitPieceMatrix(unitID, pieceMap[name]) }
		if #matrix ~= 16 then
			echo("ERROR pose frame=%d case=%s piece=%s", frame, case.name, name)
		else
			-- Remove the common unit/world translation. The remaining matrix is
			-- the animated model pose, so locomotion's physical position cannot
			-- hide a script animation mismatch at an order boundary.
			matrix[13] = matrix[13] - rootX
			matrix[14] = matrix[14] - rootY
			matrix[15] = matrix[15] - rootZ
			count = count + 1
			echo(
				"POSE frame=%d case=%s piece=%s m=" ..
					"%.6f,%.6f,%.6f,%.6f," ..
					"%.6f,%.6f,%.6f,%.6f," ..
					"%.6f,%.6f,%.6f,%.6f," ..
					"%.6f,%.6f,%.6f,%.6f",
				frame,
				case.name,
				name,
				matrix[1], matrix[2], matrix[3], matrix[4],
				matrix[5], matrix[6], matrix[7], matrix[8],
				matrix[9], matrix[10], matrix[11], matrix[12],
				matrix[13], matrix[14], matrix[15], matrix[16]
			)
		end
	end
	echo("SAMPLE_DONE frame=%d case=%s pieces=%d", frame, case.name, count)
end

local function emitAllPoses(frame)
	for _, case in ipairs(CASES) do
		local unitID = units[case.name]
		if deadCases[case.name] then
			-- The death callback owns the terminal sample for intentionally
			-- self-destructing units such as the bomb mushroom.
		elseif unitID and Spring.ValidUnitID(unitID) then
			emitPose(frame, case, unitID)
		else
			echo("ERROR pose frame=%d case=%s missing-unit", frame, case.name)
		end
	end
end

local function createUnits()
	if created then
		return
	end
	created = true

	for _, case in ipairs(CASES) do
		local def = UnitDefNames[case.def]
		if not def then
			echo("ERROR missing definition case=%s def=%s", case.name, case.def)
		else
			local unitID = Spring.CreateUnit(def.id, case.x, 0, case.z, 0, 1, false, false)
			units[case.name] = unitID
			if unitID then
				echo("CREATE case=%s unit=%d def=%s", case.name, unitID, case.def)
			else
				echo("ERROR failed-create case=%s def=%s", case.name, case.def)
			end
		end
	end
end

local function issueMove(frame)
	echo("EVENT frame=%d name=movement_begin", frame)
	for _, case in ipairs(CASES) do
		local unitID = units[case.name]
		if unitID then
			local x, y, z = Spring.GetUnitPosition(unitID)
			Spring.SetUnitMoveGoal(unitID, x + 400, y, z, 16, nil, true)
		end
	end
end

local function issueStop(frame)
	echo("EVENT frame=%d name=movement_stop", frame)
	for _, case in ipairs(CASES) do
		local unitID = units[case.name]
		if unitID then
			Spring.GiveOrderToUnit(unitID, CMD.STOP, {}, {})
		end
	end
end

local function issueAttack(frame)
	if not UnitDefNames.treelevel3 then
		echo("ERROR missing treelevel3 definition")
		return
	end
	for _, case in ipairs(CASES) do
		local unitID = units[case.name]
		if unitID then
			-- Spring fire states: 0 = hold fire, 2 = fire at will.
			Spring.GiveOrderToUnit(unitID, CMD.FIRE_STATE, { case.name == "normal" and 2 or 0 }, {})
		end
	end
	target = Spring.CreateUnit(UnitDefNames.treelevel3.id, 5250, 0, 4500, 0, 0, false, false)
	if not target then
		echo("ERROR failed to create attack target")
		return
	end
	Spring.SetUnitNeutral(target, false)
	echo("TARGET unit=%d def=treelevel3", target)
	echo("EVENT frame=%d name=aim_begin target=%d", frame, target)
	for _, case in ipairs(CASES) do
		local unitID = units[case.name]
		if unitID and case.name == "normal" then
			Spring.GiveOrderToUnit(unitID, CMD.ATTACK, { target }, {})
		end
	end
end

function gadget:Initialize()
	echo("BEGIN")
end

function gadget:GameFrame(frame)
	if frame == 1 then
		createUnits()
	elseif frame == 3 then
		echo("EVENT frame=%d name=skeleton_export", frame)
		for _, case in ipairs(CASES) do
			if units[case.name] then
				emitSkeleton(case, units[case.name])
			end
		end
	elseif frame == 12 then
		issueMove(frame)
	elseif frame == 72 then
		issueStop(frame)
	elseif frame == 105 then
		issueAttack(frame)
	end

	if frame == 105 or frame == 106 or frame == 120 or frame == 160 or frame == 200 then
		local aimReady, reloadReady, reloadState = units.normal and Spring.GetUnitWeaponState(units.normal, 1)
		if aimReady ~= nil then
			echo(
				"WEAPON frame=%d aimReady=%s reloadReady=%s reloadState=%.3f",
				frame,
				tostring(aimReady),
				tostring(reloadReady),
				reloadState or -1
			)
		else
			echo("ERROR weapon-state frame=%d", frame)
		end
	end

	if frame == 210 and not traceDone then
		traceDone = true
		echo("DONE")
		Spring.SendCommands("quitforce")
	end
end

-- Lua unit-script sleepers run before this probe's GameFrame callback, while
-- CUS tasks run during the engine's script tick.  Export after that tick and
-- after native animation integration so both runtimes are compared at the
-- same end-of-frame boundary.
function gadget:GameFramePost(frame)
	if frame >= 3 and frame <= 210 then
		emitAllPoses(frame)
	end
end

function gadget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID)
	if unitID ~= target or not attackerID then
		return
	end
	for _, case in ipairs(CASES) do
		if units[case.name] == attackerID then
			echo("SHOT frame=%d case=%s damage=%.3f", Spring.GetGameFrame(), case.name, damage or 0)
			return
		end
	end
end

function gadget:UnitDestroyed(unitID)
	for _, case in ipairs(CASES) do
		if units[case.name] == unitID then
			deadCases[case.name] = true
			echo("DEATH frame=%d case=%s", Spring.GetGameFrame(), case.name)
			return
		end
	end
end
