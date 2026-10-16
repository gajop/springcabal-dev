function gadget:GetInfo()
	return {
		name = "Verification B.O.B sustained fire",
		layer = 1000001,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return
end

local START_FRAME = 60
local WARMUP_FRAMES = 60
local WINDOW_FRAMES = 300
local MAX_GAP_FRAMES = 15
local MIN_WINDOW_SHOTS = 50
local bob, started, finished
local shots = { 0, 0 }
local lastShot, maxGap = 0, 0

local function log(text)
	Spring.Echo("[vf-bob] " .. text)
end

local function finish(ok, detail)
	log((ok and "PASS " or "FAIL ") .. "bob-continuous: " .. detail)
	log("summary passed=" .. (ok and "1 failed=0" or "0 failed=1"))
	finished = true
end

local function clearSpot(px, pz)
	local best, nearest
	for x = 220, Game.mapSizeX - 220, 40 do
		for z = 220, Game.mapSizeZ - 220, 40 do
			local distance = (x - px) ^ 2 + (z - pz) ^ 2
			if not nearest or distance < nearest then
				local floor = Spring.GetGroundHeight(x, z)
				local clear = #Spring.GetUnitsInCylinder(x, z, 220) == 0
				for dx = -120, 120, 40 do
					for dz = -40, 40, 40 do
						if math.abs(Spring.GetGroundHeight(x + dx, z + dz) - floor) > 4 then
							clear = false
						end
					end
				end
				if clear then
					best, nearest = { x = x, z = z }, distance
				end
			end
		end
	end
	return best
end

function gadget:Initialize()
	Script.SetWatchProjectile(WeaponDefNames.bobgun.id, true)
end

function gadget:ProjectileCreated(projectileID, ownerID, weaponDefID)
	if ownerID ~= bob or weaponDefID ~= WeaponDefNames.bobgun.id or not started or finished then
		return
	end
	local elapsed = Spring.GetGameFrame() - started - WARMUP_FRAMES
	if elapsed < 0 or elapsed >= 2 * WINDOW_FRAMES then
		return
	end
	local window = elapsed < WINDOW_FRAMES and 1 or 2
	shots[window] = shots[window] + 1
	maxGap = math.max(maxGap, elapsed - lastShot)
	lastShot = elapsed
end

function gadget:GameFrame(frame)
	if frame < START_FRAME or finished then
		return
	end
	if not started then
		local player = Spring.GetTeamUnitsByDefs(0, UnitDefNames.gravit.id)[1]
		if not player then
			return
		end
		local px, _, pz = Spring.GetUnitPosition(player)
		local spot = clearSpot(px, pz)
		if not spot then
			finish(false, "no clear firing lane")
			return
		end
		for _, unit in ipairs(Spring.GetAllUnits()) do
			if UnitDefs[Spring.GetUnitDefID(unit)].customParams.robot then
				Spring.AddUnitDamage(unit, 100000, 3600)
			end
		end
		Spring.SetUnitRulesParam(player, "invulnerable", 1)
		Spring.SetUnitRulesParam(player, "nonparalyzable", 1)
		Spring.SetUnitPosition(player, spot.x - 100, spot.z)
		Spring.SetUnitVelocity(player, 0, 0, 0)
		bob = Spring.CreateUnit("bob", spot.x + 100, Spring.GetGroundHeight(spot.x + 100, spot.z), spot.z, 3, 1)
		if not bob then
			finish(false, "could not create B.O.B")
			return
		end
		Spring.GiveOrderToUnit(bob, CMD.MOVE_STATE, { 0 }, {})
		started = frame
	end
	if frame - started >= WARMUP_FRAMES + 2 * WINDOW_FRAMES then
		maxGap = math.max(maxGap, 2 * WINDOW_FRAMES - lastShot)
		finish(shots[1] >= MIN_WINDOW_SHOTS and shots[2] >= MIN_WINDOW_SHOTS and maxGap <= MAX_GAP_FRAMES,
			string.format("first10s=%d next10s=%d maxGap=%d frames (limit %d)", shots[1], shots[2], maxGap, MAX_GAP_FRAMES))
	end
end
