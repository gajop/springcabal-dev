-- Controlled Lua/WASM drone weapon comparison.
-- A stationary small turret is attacked by one drone at close range.

local options = Spring.GetModOptions() or {}
local enabled = options.drone_hit_test == "1"
local directAttack = options.drone_hit_direct == "1"
local targetDef = options.drone_target or "static_aa"

function gadget:GetInfo()
	return {
		name = "Area 17 drone hit comparison",
		desc = "One drone attacks one held small turret",
		author = "SpringCabal",
		layer = 1000003,
		enabled = enabled,
	}
end

if not enabled or not gadgetHandler:IsSyncedCode() then
	return
end

local SETUP_FRAME = 30
local TIMEOUT_FRAMES = 300
local ufoID
local droneID
local turretID
local startFrame
local initialHealth
local finished
local setupDone

local function findUnit(defName)
	local defID = UnitDefNames[defName] and UnitDefNames[defName].id
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
	local health = turretID and Spring.GetUnitHealth(turretID) or nil
	Spring.Echo(string.format(
		"[Area17-Drone-Hit-Test] RESULT=%s frame=%d elapsed=%d seconds=%.3f health=%s initial_health=%s drone=%s turret=%s",
		result,
		frame,
		elapsed,
		elapsed / 30,
		tostring(health or ""),
		tostring(initialHealth or ""),
		tostring(droneID),
		tostring(turretID)
	))
	Spring.SendCommands("quitforce")
	Spring.SendCommands("quit")
end

local function setup(frame)
	ufoID = findUnit("ufo")
	if not ufoID then
		return false
	end

	local x, y, z = Spring.GetUnitPosition(ufoID)
	if not x then
		return false
	end

	for _, unitID in ipairs(Spring.GetAllUnits()) do
		if unitID ~= ufoID then
			Spring.DestroyUnit(unitID, false, true)
		end
	end
	Spring.SetUnitUseWeapons(ufoID, false, false)

	local ground = Spring.GetGroundHeight(x + 160, z)
	turretID = Spring.CreateUnit(targetDef, x + 160, ground, z, 0, 1, false, false)
	droneID = Spring.CreateUnit("drone", x, y, z, 0, 0, false, false)
	if not turretID or not droneID then
		Spring.Echo("[Area17-Drone-Hit-Test] RESULT=CREATE_FAILED")
		return false
	end

	Spring.GiveOrderToUnit(turretID, CMD.MOVE_STATE, {0}, {})
	initialHealth = Spring.GetUnitHealth(turretID)
	startFrame = frame
	setupDone = true
	Spring.Echo(string.format(
		"[Area17-Drone-Hit-Test] START frame=%d ufo=%d drone=%d turret=%d ufo_pos=%.2f,%.2f,%.2f turret_pos=%.2f,%.2f,%.2f health=%.2f",
		frame,
		ufoID,
		droneID,
		turretID,
		x,
		y,
		z,
		x + 160,
		ground,
		z,
		initialHealth or -1
	))
	return true
end

function gadget:UnitPreDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID, attackerDefID, attackerTeam)
	if unitID == turretID then
		Spring.Echo(string.format(
			"[Area17-Drone-Hit-Test] DAMAGE frame=%d damage=%.2f weapon=%s attacker=%s",
			Spring.GetGameFrame(),
			damage or -1,
			tostring(WeaponDefs[weaponDefID] and WeaponDefs[weaponDefID].name or weaponDefID),
			tostring(attackerID)
		))
	end
	return damage
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

	if not Spring.ValidUnitID(droneID) or not Spring.ValidUnitID(turretID) then
		finish(frame, "UNIT_LOST")
		return
	end

	-- The direct mode isolates the beam itself. Without it, the native drone
	-- gadget's FIGHT command is allowed to acquire targets as in gameplay.
	if directAttack then
		Spring.GiveOrderToUnit(droneID, CMD.ATTACK, {turretID}, {})
	end

	local health = Spring.GetUnitHealth(turretID)
	if frame == startFrame or frame % 30 == 0 then
		local dx, dy, dz = Spring.GetUnitPosition(droneID, true)
		local tx, ty, tz = Spring.GetUnitPosition(turretID, true)
		local command = Spring.GetUnitCurrentCommand(droneID)
		Spring.Echo(string.format(
			"[Area17-Drone-Hit-Test] SAMPLE frame=%d health=%.2f drone_pos=%.2f,%.2f,%.2f turret_pos=%.2f,%.2f,%.2f command=%s",
			frame,
			health or -1,
			dx or -1,
			dy or -1,
			dz or -1,
			tx or -1,
			ty or -1,
			tz or -1,
			tostring(command or "")
		))
	end

	if health and initialHealth and health < initialHealth then
		finish(frame, "HIT")
	elseif frame >= startFrame + TIMEOUT_FRAMES then
		finish(frame, "TIMEOUT")
	end
end
