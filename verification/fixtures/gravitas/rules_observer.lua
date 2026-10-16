-- Verification: the Gravitas rules suite (verification/games/gravitas.sh,
-- modes rules and lua-rules). The same cases run headless on the WASM port
-- and the Lua game. Each case sets a scene up in the level, waits for the
-- game to react, and logs "[vf-rules] PASS CASE" or "[vf-rules] FAIL CASE:
-- why"; "[vf-rules] summary passed=N failed=M" ends the run.
--
-- Copied into a staged copy of the game; never part of a shipped archive.

function gadget:GetInfo()
	return {
		name = "Verification rules observer",
		desc = "Checks plates, collisions and B.O.B for the rules suite",
		author = "springcabal verification",
		license = "GPL v2 or later",
		layer = 1000001,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return
end

local GRAVIT = UnitDefNames.gravit.id
local PLAYER_TEAM = 0
local START_FRAME = 60
local FLAT = 4

local function log(text)
	Spring.Echo("[vf-rules] " .. text)
end

local function unitsOf(name)
	local found = {}
	for _, u in ipairs(Spring.GetAllUnits()) do
		if UnitDefs[Spring.GetUnitDefID(u)].name == name and not Spring.GetUnitIsDead(u) then
			found[#found + 1] = u
		end
	end
	return found
end

local function player()
	return Spring.GetTeamUnitsByDefs(PLAYER_TEAM, GRAVIT)[1]
end

local function groundAt(x, z)
	return Spring.GetGroundHeight(x, z)
end

-- A spot with flat floor and no unit within `radius`, nearest x,z.
local function clearSpot(x0, z0, radius)
	local floor = groundAt(x0, z0)
	local best, bestDistance
	for x = 100, Game.mapSizeX - 100, 40 do
		for z = 100, Game.mapSizeZ - 100, 40 do
			local distance = (x - x0) ^ 2 + (z - z0) ^ 2
			if (not best or distance < bestDistance) and math.abs(groundAt(x, z) - floor) <= FLAT then
				local clear = true
				for dx = -radius, radius, 40 do
					for dz = -radius, radius, 40 do
						if math.abs(groundAt(x + dx, z + dz) - floor) > FLAT then
							clear = false
						end
					end
				end
				if clear then
					for _, other in ipairs(Spring.GetUnitsInCylinder(x, z, radius + 200)) do
						local ox, _, oz = Spring.GetUnitPosition(other)
						local reach = radius + Spring.GetUnitRadius(other)
						if (ox - x) ^ 2 + (oz - z) ^ 2 < reach * reach then
							clear = false
						end
					end
				end
				if clear then
					best, bestDistance = { x = x, z = z }, distance
				end
			end
		end
	end
	return best
end

local function place(u, x, z)
	Spring.SetUnitPosition(u, x, z)
	Spring.SetUnitVelocity(u, 0, 0, 0)
end

-- The robots the cases use; the others are stunned at the start, so none
-- wanders into a scene.
local thrown, bob

local function stunOtherRobots()
	for _, u in ipairs(Spring.GetAllUnits()) do
		if UnitDefs[Spring.GetUnitDefID(u)].customParams.robot and u ~= thrown and u ~= bob then
			Spring.AddUnitDamage(u, 100000, 3600)
		end
	end
end

local CASES = {}
local damage = {}             -- unit -> collision damage taken this case
local shots = 0               -- B.O.B shots this case

-- A crate put on a plate presses its button down; taken off, it comes back.
CASES[#CASES + 1] = {
	name = "plate",
	frames = 150,
	start = function(s)
		s.plate = unitsOf("plate")[1]
		s.crate = unitsOf("crate")[1]
		if not (s.plate and s.crate) then
			return "no plate or crate in the level"
		end
		for name, piece in pairs(Spring.GetUnitPieceMap(s.plate)) do
			if name == "button" then
				s.button = piece
			end
		end
		local _, y = Spring.GetUnitPiecePosition(s.plate, s.button)
		s.up = y
		s.x, _, s.z = Spring.GetUnitPosition(s.plate)
		place(s.crate, s.x, s.z)
	end,
	check = function(s, elapsed)
		local _, y = Spring.GetUnitPiecePosition(s.plate, s.button)
		if not s.pressed then
			if y < s.up - 10 then
				s.pressed = elapsed
				place(s.crate, s.x + 200, s.z)
			end
			return nil, string.format("button at %.1f with a crate on the plate, up at %.1f", y, s.up)
		end
		if y > s.up - 1 then
			return true
		end
		return nil, string.format("button at %.1f after the crate left, up at %.1f", y, s.up)
	end,
}

-- A robot thrown into a crate at speed 10 takes collision damage computed
-- by the game from the speed and the masses (game_fall_damage.lua): about
-- 270 of its 300 health. The engine's own collision damage is about 7.
CASES[#CASES + 1] = {
	name = "collision",
	frames = 90,
	start = function(s)
		s.robot = thrown
		s.crate = unitsOf("crate")[1]
		local x, _, z = Spring.GetUnitPosition(player())
		local spot = clearSpot(x, z, 120)
		if not (s.robot and s.crate and spot) then
			return "no robot, crate or clear floor"
		end
		damage = {}
		place(s.crate, spot.x + 60, spot.z)
		place(s.robot, spot.x - 60, spot.z)
		Spring.AddUnitImpulse(s.robot, 10, 2, 0)
	end,
	check = function(s, elapsed, last)
		local taken = damage[s.robot] or 0
		if last then
			local result = string.format("the robot took %.0f collision damage, expected 150 or more", taken)
			return taken >= 150, result
		end
	end,
}

-- B.O.B keeps firing while its target remains in range.
CASES[#CASES + 1] = {
	name = "bob-continuous",
	frames = 330,
	start = function(s)
		s.bob = bob
		local u = player()
		local x, _, z = Spring.GetUnitPosition(u)
		local spot = clearSpot(x, z, 200)
		if not (s.bob and spot) then
			return "no B.O.B or clear floor"
		end
		place(u, spot.x - 100, spot.z)
		place(s.bob, spot.x + 100, spot.z)
		Spring.GiveOrderToUnit(s.bob, CMD.STOP, {}, {})
		shots = 0
	end,
	check = function(s, elapsed, last)
		if not last then
			return nil
		end
		return shots >= 50,
			string.format("%d shots in 11 s, expected at least 50", shots)
	end,
}

function gadget:Initialize()
	Script.SetWatchProjectile(WeaponDefNames.bobgun.id, true)
end

function gadget:ProjectileCreated(projectileID, ownerID, weaponDefID)
	if weaponDefID == WeaponDefNames.bobgun.id then
		shots = shots + 1
	end
end

function gadget:UnitDamaged(unitID, unitDefID, unitTeam, amount, paralyzer, weaponDefID)
	-- -3: an engine collision; -7: the collision damage game_fall_damage.lua
	-- deals (the WASM port may deal it under either).
	if (weaponDefID == -3 or weaponDefID == -7) and not paralyzer then
		damage[unitID] = (damage[unitID] or 0) + amount
	end
end

local index = 0
local case
local passed, failed = 0, 0

local function finish(ok, why)
	if ok then
		passed = passed + 1
		log("PASS " .. case.def.name .. (why and (": " .. why) or ""))
	else
		failed = failed + 1
		log("FAIL " .. case.def.name .. ": " .. (why or "no result"))
	end
	case = nil
end

function gadget:GameFrame(frame)
	local u = player()
	if frame < START_FRAME or not u or index > #CASES then
		return
	end
	if frame == START_FRAME then
		Spring.SetUnitRulesParam(u, "invulnerable", 1)
		Spring.SetUnitRulesParam(u, "nonparalyzable", 1)
		thrown, bob = unitsOf("projector")[1], unitsOf("bob")[1]
		stunOtherRobots()
	end
	if not case then
		index = index + 1
		local def = CASES[index]
		if not def then
			log(string.format("summary passed=%d failed=%d", passed, failed))
			return
		end
		case = { def = def, state = {}, started = frame }
		local problem = def.start(case.state)
		if problem then
			finish(false, problem)
		end
		return
	end
	local elapsed = frame - case.started
	local last = elapsed >= case.def.frames
	local ok, why = case.def.check(case.state, elapsed, last)
	if ok ~= nil then
		finish(ok, why)
	elseif last then
		finish(false, why)
	end
end
