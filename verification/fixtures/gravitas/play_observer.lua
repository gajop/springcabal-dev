-- Verification: the Gravitas play suite (verification/games/gravitas.sh, modes
-- play and lua-play). The same checks run on the WASM port and the Lua game,
-- through real input: the suite's driver presses keys and mouse buttons with
-- xdotool, and this gadget says what to do next and checks the result.
--
-- The synced half walks through STEPS. For each it publishes the step and a
-- point to aim at as game rules params, and the unsynced half turns them into
-- one line for the driver:
--   [vf-play] go STEP key=KEY x=SX y=SY    (x/y: X11 window coordinates)
-- The synced half then logs "[vf-play] PASS STEP" or "[vf-play] FAIL STEP:
-- why", and "[vf-play] summary passed=N failed=M" after the last step.
--
-- Copied into a staged copy of the game; never part of a shipped archive.

function gadget:GetInfo()
	return {
		name = "Verification play observer",
		desc = "Checks the player's controls for the play suite",
		author = "springcabal verification",
		license = "GPL v2 or later",
		layer = 1000001,
		enabled = true,
	}
end

local STEP_PARAM = "vf_play_step"
local AIM_PARAMS = { "vf_play_aim_x", "vf_play_aim_y", "vf_play_aim_z" }

-- Each step: the key (or button) the driver uses, and how long the synced
-- half waits for the result.
local STEPS = {
	{ name = "move", key = "move", frames = 240 },
	{ name = "jump-space", key = "space", frames = 210 },
	{ name = "jump-space-again", key = "space", frames = 210 },
	{ name = "jump-e", key = "e", frames = 210 },
	{ name = "jump-middle-mouse", key = "mouse2", frames = 210 },
	{ name = "push", key = "mouse1", frames = 150 },
	{ name = "pull", key = "mouse3", frames = 150 },
	{ name = "push-beyond-range", key = "mouse1", frames = 150 },
	{ name = "quit", key = "ctrl+q", frames = 0 },
}

local function log(text)
	Spring.Echo("[vf-play] " .. text)
end

if gadgetHandler:IsSyncedCode() then

local GRAVIT = UnitDefNames.gravit.id
local CRATE = UnitDefNames.crate.id
local PLAYER_TEAM = 0

local JUMP_DISTANCE = 100
local AIRBORNE = 12           -- elmos above the ground
local LANE_AHEAD = 480        -- clear floor needed ahead of the player
local LANE_BEHIND = 60        -- and behind
local FLAT = 4                -- elmos of ground height the floor may vary

local DIRECTIONS = {
	{ x = 1, z = 0, key = "d" },
	{ x = -1, z = 0, key = "a" },
}

local stepIndex = 0
local step                    -- state of the running step
local passed, failed = 0, 0
local settledSince
local setupFailed
local dir
local origin                  -- where the player stood when the jumps began
local target                  -- a crate, the gun's target

local function player()
	return Spring.GetTeamUnitsByDefs(PLAYER_TEAM, GRAVIT)[1]
end

local function groundAt(x, z)
	return Spring.GetGroundHeight(x, z)
end

local function airborne(u)
	local x, y, z = Spring.GetUnitPosition(u)
	return y - groundAt(x, z) > AIRBORNE
end

-- Whether the floor from BEHIND to AHEAD elmos along direction d from x,z is
-- as high as the floor at x,z, with no unit on it but `except`.
local function laneClear(x, z, d, except)
	local floor = groundAt(x, z)
	for s = -LANE_BEHIND, LANE_AHEAD, 20 do
		local lx, lz = x + d.x * s, z + d.z * s
		if math.abs(groundAt(lx, lz) - floor) > FLAT then
			return false
		end
	end
	for s = -LANE_BEHIND, LANE_AHEAD, 20 do
		local lx, lz = x + d.x * s, z + d.z * s
		for _, other in ipairs(Spring.GetUnitsInCylinder(lx, lz, 300)) do
			local ox, _, oz = Spring.GetUnitPosition(other)
			-- walls are long: count a unit by its radius, not its centre
			local reach = 30 + Spring.GetUnitRadius(other)
			if other ~= except and (ox - lx) ^ 2 + (oz - lz) ^ 2 < reach * reach then
				return false
			end
		end
	end
	return true
end

-- The test lane: the clear spot nearest the player, on the floor the player
-- stands on, with a clear lane along x (the screen's long side, so points far
-- along it are still on screen). The jumps go back and forth along it and the
-- gun's target is placed on it.
local function findLane(u)
	local px, _, pz = Spring.GetUnitPosition(u)
	local floor = groundAt(px, pz)
	local best, bestDistance
	for x = 100, Game.mapSizeX - 100, 40 do
		for z = 100, Game.mapSizeZ - 100, 40 do
			local distance = (x - px) ^ 2 + (z - pz) ^ 2
			if (not best or distance < bestDistance) and math.abs(groundAt(x, z) - floor) <= FLAT then
				for _, d in ipairs(DIRECTIONS) do
					if laneClear(x, z, d, u) then
						best, bestDistance = { x = x, z = z, dir = d }, distance
						break
					end
				end
			end
		end
	end
	return best
end

local function publish(index, x, y, z)
	Spring.SetGameRulesParam(AIM_PARAMS[1], x or -1)
	Spring.SetGameRulesParam(AIM_PARAMS[2], y or -1)
	Spring.SetGameRulesParam(AIM_PARAMS[3], z or -1)
	Spring.SetGameRulesParam(STEP_PARAM, index)
end

local function placeTarget(u, along)
	local px, _, pz = Spring.GetUnitPosition(u)
	local x, z = px + dir.x * along, pz + dir.z * along
	Spring.SetUnitPosition(target, x, z)
	Spring.SetUnitVelocity(target, 0, 0, 0)
	return x, groundAt(x, z), z
end

local START = {}
local CHECK = {}

START["move"] = function(u, s)
	s.x, _, s.z = Spring.GetUnitPosition(u)
	return nil
end
CHECK["move"] = function(u, s)
	local x, _, z = Spring.GetUnitPosition(u)
	local moved = (x - s.x) * dir.x + (z - s.z) * dir.z
	if moved > 60 then
		return true
	end
	return nil, string.format("moved %.0f elmos, expected over 60", moved)
end

-- A jump step: one press must give exactly one jump. The target alternates
-- between the start point and JUMP_DISTANCE along the clear direction.
local jumpsDone = 0
local function startJump(u, s)
	local px, _, pz = Spring.GetUnitPosition(u)
	origin = origin or { px, pz }
	local along = (jumpsDone % 2 == 0) and JUMP_DISTANCE or 0
	jumpsDone = jumpsDone + 1
	local x, z = origin[1] + dir.x * along, origin[2] + dir.z * along
	s.jumps, s.wasAirborne = 0, false
	return x, groundAt(x, z), z
end
-- Counts take-offs for the whole step, so a second jump from the same press
-- (a repeated order) fails it; the step passes on its last frame with one
-- jump done and the player back on the ground.
local function checkJump(u, s, elapsed, last)
	local up = airborne(u)
	if up and not s.wasAirborne then
		s.jumps = s.jumps + 1
	end
	s.wasAirborne = up
	if s.jumps > 1 then
		return false, s.jumps .. " jumps from one press"
	end
	if not last then
		return nil
	end
	if s.jumps == 0 then
		return false, "no jump"
	end
	if up then
		return false, "still in the air"
	end
	return true
end
for _, name in ipairs({ "jump-space", "jump-space-again", "jump-e", "jump-middle-mouse" }) do
	START[name] = startJump
	CHECK[name] = checkJump
end

-- The gun steps check that the target is hit by the gun whose button is
-- down, and never by the other one (the game holds that one back). What a
-- hit then does to the crate (weapon_impulse.lua) is physics, not controls.
local GUN = { push = "gravity_pos", pull = "gravity_neg" }
local HITS = 3
local hits = {}               -- weapon name -> hits on the target this step

local function anyCrate()
	for _, other in ipairs(Spring.GetAllUnits()) do
		if Spring.GetUnitDefID(other) == CRATE and not Spring.GetUnitIsDead(other) then
			return other
		end
	end
end

local function stunRobots()
	for _, other in ipairs(Spring.GetAllUnits()) do
		if UnitDefs[Spring.GetUnitDefID(other)].customParams.robot then
			Spring.AddUnitDamage(other, 100000, 3600)
		end
	end
end

local function startGun(u, along)
	hits = {}
	-- A push can throw the crate off the map, which kills it.
	if not Spring.ValidUnitID(target) or Spring.GetUnitIsDead(target) then
		target = anyCrate()
	end
	local x, y, z = placeTarget(u, along)
	return x, y + 10, z
end

local function checkGun(want, other)
	return function(u, s, elapsed, last)
		local good, bad = hits[want] or 0, hits[other] or 0
		if bad > 0 then
			return false, string.format("%d hits by %s, whose button was up", bad, other)
		end
		if good >= HITS then
			return true
		end
		return nil, string.format("%d hits by %s, expected %d or more", good, want, HITS)
	end
end

START["push"] = function(u, s) return startGun(u, 150) end
CHECK["push"] = checkGun(GUN.push, GUN.pull)
START["pull"] = function(u, s) return startGun(u, 280) end
CHECK["pull"] = checkGun(GUN.pull, GUN.push)
-- A target just beyond the gun's range (420): the gun must still fire at it,
-- and the tip of the beam reaches the near side of the crate.
START["push-beyond-range"] = function(u, s) return startGun(u, 430) end
CHECK["push-beyond-range"] = CHECK["push"]

function gadget:UnitPreDamaged_GetWantedWeaponDef()
	return { WeaponDefNames[GUN.push].id, WeaponDefNames[GUN.pull].id }
end

function gadget:UnitPreDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID)
	if unitID == target then
		local name = WeaponDefs[weaponDefID].name
		hits[name] = (hits[name] or 0) + 1
	end
	return damage, 1.0
end

local function nextStep(u, frame)
	stepIndex = stepIndex + 1
	local def = STEPS[stepIndex]
	if not def then
		return
	end
	step = { def = def, started = frame }
	if def.name == "quit" then
		log(string.format("summary passed=%d failed=%d", passed, failed))
		publish(stepIndex)
		return
	end
	publish(stepIndex, START[def.name](u, step))
end

local function finish(ok, why)
	if ok then
		passed = passed + 1
		log("PASS " .. step.def.name)
	else
		failed = failed + 1
		log("FAIL " .. step.def.name .. ": " .. (why or "no result"))
	end
	step = nil
	settledSince = nil
end

function gadget:GameFrame(frame)
	local u = player()
	if not u then
		return
	end
	if setupFailed then
		return
	end
	if not dir then
		if frame < 60 then
			return
		end
		local lane = findLane(u)
		if lane then
			dir = lane.dir
			-- The lane can be in a room with robots or hazards, and the steps
			-- check the controls: the player must not die or be stunned there
			-- (both versions read these rules params), and robots must not walk
			-- into the lane or the beam, so they stay stunned.
			Spring.SetUnitRulesParam(u, "invulnerable", 1)
			Spring.SetUnitRulesParam(u, "nonparalyzable", 1)
			stunRobots()
			Spring.SetUnitPosition(u, lane.x, lane.z)
			Spring.SetUnitVelocity(u, 0, 0, 0)
			Spring.GiveOrderToUnit(u, CMD.STOP, {}, {})
		end
		target = anyCrate()
		if not (dir and target) then
			setupFailed = true
			log("FAIL setup: " .. (dir and "no crate in the level" or "no clear lane on the player's floor"))
			log("summary passed=0 failed=1")
			-- Still let the driver leave.
			stepIndex = #STEPS
			publish(stepIndex)
			return
		end
		Spring.SetGameRulesParam("vf_play_move_key", dir.key)
		local x, _, z = Spring.GetUnitPosition(u)
		log(string.format("setup: lane from %.0f,%.0f along %d,%d, crate %d", x, z, dir.x, dir.z, target))
	end

	if step then
		if step.def.name == "quit" then
			return
		end
		local elapsed = frame - step.started
		local last = elapsed >= step.def.frames
		local ok, why = CHECK[step.def.name](u, step, elapsed, last)
		if ok ~= nil then
			finish(ok, why)
		elseif last then
			finish(false, why)
		end
		return
	end

	-- Between steps: wait until the player stands still on the ground.
	local _, _, _, speed = Spring.GetUnitVelocity(u)
	if airborne(u) or speed > 0.1 then
		settledSince = nil
		return
	end
	settledSince = settledSince or frame
	if frame - settledSince >= 15 then
		nextStep(u, frame)
	end
end

else -- unsynced: tell the driver what to do, in window coordinates

local shown = 0

function gadget:GameFrame()
	local index = Spring.GetGameRulesParam(STEP_PARAM) or 0
	if index == shown or not STEPS[index] then
		return
	end
	shown = index
	local def = STEPS[index]
	local key = def.key
	if def.name == "move" then
		key = Spring.GetGameRulesParam("vf_play_move_key") or "d"
	end
	local x, y, z = Spring.GetGameRulesParam(AIM_PARAMS[1]), Spring.GetGameRulesParam(AIM_PARAMS[2]), Spring.GetGameRulesParam(AIM_PARAMS[3])
	local where = "x=- y=-"
	if x and x >= 0 then
		local sx, sy = Spring.WorldToScreenCoords(x, y, z)
		local _, vsy = Spring.GetViewGeometry()
		where = string.format("x=%d y=%d", sx, vsy - sy)
	end
	log(string.format("go %s key=%s %s", def.name, key, where))
end

end
