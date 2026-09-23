-- Runtime probe for Bob's engine weapon path.  This fixture is copied into
-- isolated test archives only; it is not part of the shipped game.

function gadget:GetInfo()
	return {
		name = "Gravitas Bob weapon probe",
		desc = "Confirms Bob aim, reload and damage behavior",
		author = "springcabal verification",
		license = "GPL v2 or later",
		layer = 1000000,
		 enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return
end

local bob
local target
local initialized = false
local doneFrame = 150

local function echo(frame, label, value)
	Spring.Echo(string.format("[BobWeaponProbe] frame=%d %s=%s", frame, label, tostring(value)))
end

function gadget:Initialize()
	-- Create after the first game frame so the Rust rules module has received
	-- the game-start callbacks before this fixture generates UnitCreated.
	return
end

local function create_probe_units()
	local y = Spring.GetGroundHeight(396, 3314)
	bob = Spring.CreateUnit("bob", 396, y, 3314, 0, 1)
	local targetY = Spring.GetGroundHeight(396, 3474)
	target = Spring.CreateUnit("gravit", 396, targetY, 3474, 0, 0)
	if not bob or not target then
		Spring.Echo("[BobWeaponProbe] ERROR failed to create units")
		return
	end
	local targetSet = Spring.SetUnitTarget(bob, target, false, true)
	Spring.GiveOrderToUnit(bob, CMD.FIRE_STATE, {2}, {})
	Spring.Echo("[BobWeaponProbe] initialTargetSet=" .. tostring(targetSet))
	Spring.Echo(string.format("[BobWeaponProbe] target bob=%d enemy=%d", bob, target))
	local bx, by, bz = Spring.GetUnitPosition(bob)
	local tx, ty, tz = Spring.GetUnitPosition(target)
	local tax, tay, taz = Spring.GetUnitPosition(target, false, true)
	local angleGood, reloadReady, reloadFrame = Spring.GetUnitWeaponState(bob, 1)
	local range = Spring.GetUnitWeaponState(bob, 1, "range")
	local los = Spring.GetUnitLosState(bob, 0)
	Spring.Echo(string.format("[BobWeaponProbe] initPos bob=%.1f,%.1f,%.1f target=%.1f,%.1f,%.1f targetAim=%.1f,%.1f,%.1f range=%.1f angleGood=%s los=%s radar=%s prev=%s", bx, by, bz, tx, ty, tz, tax, tay, taz, range, tostring(angleGood), tostring(los.los), tostring(los.radar), tostring(los.prevLos)))
end

function gadget:GameFrame(frame)
	if frame == 1 and not initialized then
		initialized = true
		create_probe_units()
	end
	if not bob or not target or not Spring.ValidUnitID(bob) or not Spring.ValidUnitID(target) then
		return
	end
	if frame == 5 or frame == 50 or frame == 100 then
		local targetSet = Spring.SetUnitTarget(bob, target, false, true)
		Spring.GiveOrderToUnit(bob, CMD.ATTACK, {target}, {})
		Spring.GiveOrderToUnit(bob, CMD.FIRE_STATE, {2}, {})
		Spring.Echo("[BobWeaponProbe] frame=" .. frame .. " unitTargetSet=" .. tostring(targetSet))
	end
	if frame <= 90 or frame % 10 == 0 then
		local reload = Spring.GetUnitWeaponState(bob, 1, "reloadFrame")
		local canFire = Spring.GetUnitWeaponCanFire(bob, 1)
		local targetType, targetID = Spring.GetUnitWeaponTarget(bob, 1)
		local health = Spring.GetUnitHealth(target)
		local tx, ty, tz = Spring.GetUnitPosition(target)
		local tvx, tvy, tvz = Spring.GetUnitVelocity(target)
		local matrix = {Spring.GetUnitPieceMatrix(bob, Spring.GetUnitPieceMap(bob).MG_B01)}
		local angleGood, reloadReady = Spring.GetUnitWeaponState(bob, 1)
		echo(frame, "reload", reload)
		echo(frame, "canFire", canFire)
		echo(frame, "weaponTarget", tostring(targetType) .. ":" .. tostring(targetID))
		echo(frame, "targetHealth", health)
		echo(frame, "targetPos", string.format("%.1f,%.1f,%.1f", tx or -1, ty or -1, tz or -1))
		echo(frame, "targetVelocity", string.format("%.3f,%.3f,%.3f", tvx or -1, tvy or -1, tvz or -1))
		echo(frame, "angleGood", angleGood)
		if #matrix == 16 then
			echo(frame, "mgB01", table.concat({matrix[6], matrix[7], matrix[10], matrix[11]}, ","))
		end
	end
	if frame >= doneFrame then
		Spring.Echo(string.format("[BobWeaponProbe] DONE frame=%d", frame))
		gadgetHandler:RemoveGadget(self)
	end
end
