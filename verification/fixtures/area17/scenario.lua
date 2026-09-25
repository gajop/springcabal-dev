-- Area 17's test-only gadget: the headless suite's Lua observer and the visual
-- suite's camera and screenshots. verification/games/area17.sh copies it into
-- the staged game; it never ships.

local options = Spring.GetModOptions() or {}
local integrationMode = options.test_mode == "1"
local visualMode = options.visual_test == "1"

function gadget:GetInfo()
	return {
		name = "Area 17 WASM integration scenario",
		desc = "Automated gameplay assertions",
		author = "SpringCabal",
		layer = 1000002,
		enabled = integrationMode or visualMode,
	}
end

if not gadgetHandler:IsSyncedCode() then
	local captureFrames = visualMode and {20, 80, 450} or {}
	local capturedFrames = {}
	local finished = false
	local exitFrame = visualMode and 500
	local cameraState
	local CAMERA_HEIGHT = 1050
	local CAMERA_ANGLE = 0.72
	-- A first-person camera parked where an overhead camera over the UFO's
	-- start would sit. The overhead camera takes its height from the ground
	-- under its target, so it would drop whenever something dug that spot.
	local function frameCrater()
		if not cameraState then
			local ufoDefID = UnitDefNames.ufo and UnitDefNames.ufo.id
			for _, unitID in ipairs(Spring.GetAllUnits()) do
				if Spring.GetUnitDefID(unitID) == ufoDefID then
					local x, _, z = Spring.GetUnitPosition(unitID)
					local ground = Spring.GetGroundHeight(x, z)
					local up, back = math.cos(CAMERA_ANGLE), math.sin(CAMERA_ANGLE)
					cameraState = {
						mode = 0,
						fov = 45,
						px = x,
						py = ground + CAMERA_HEIGHT * up,
						pz = z + CAMERA_HEIGHT * back,
						dx = 0,
						dy = -up,
						dz = -back,
						rx = math.pi - CAMERA_ANGLE,
						ry = 0,
						rz = 0,
					}
					break
				end
			end
		end
		if cameraState then
			Spring.SetCameraState(cameraState, 0)
		end
	end
	-- Each capture is taken with the game paused on its frame (pauseatframe),
	-- a few draws into the pause so the draw has settled, and the game
	-- resumes a few draws after it: every run captures the same frame.  The
	-- UI module's e2e driver pauses on its own, different frames.
	local SETTLE_DRAWS, PAUSED_DRAWS = 2, 10
	local pausesRequested, settledDraws, resumeIn = false, 0, nil
	local function paused()
		local _, _, isPaused = Spring.GetGameSpeed()
		return isPaused
	end
	function gadget:DrawScreen()
		local frame = Spring.GetGameFrame()
		frameCrater()
		if not pausesRequested and frame >= 0 then
			pausesRequested = true
			for _, captureFrame in ipairs(captureFrames) do
				Spring.SendCommands("pauseatframe " .. captureFrame)
			end
		end
		if resumeIn then
			resumeIn = resumeIn - 1
			if resumeIn <= 0 then
				resumeIn = nil
				Spring.SendCommands("pause 0")
			end
			return
		end
		for _, captureFrame in ipairs(captureFrames) do
			if frame >= captureFrame and not capturedFrames[captureFrame] then
				if frame == captureFrame then
					settledDraws = paused() and settledDraws + 1 or 0
					if settledDraws <= SETTLE_DRAWS then
						return
					end
					resumeIn = PAUSED_DRAWS
				else
					Spring.Echo("[Area17-Visual-Test] missed the pause at frame " .. captureFrame .. " (now " .. frame .. ")")
				end
				settledDraws = 0
				capturedFrames[captureFrame] = true
				Spring.Echo("[Area17-Visual-Test] Capturing crater frame " .. captureFrame)
				Spring.SendCommands("screenshot png")
			end
		end
		if exitFrame and frame >= exitFrame and not finished then
			finished = true
			Spring.Echo("[Area17-Visual-Test] Captured visual smoke-test screenshots")
			Spring.SendCommands("quitforce")
		end
	end
else

-- An observer independent of the Rust suite: it watches what the game
-- publishes (the UFO script's active_weapon_slot, the speed multiplier, the
-- beam state) and the engine's projectiles, and follows the suite whatever its
-- schedule.
local weaponStages = {
	{ name = "incendiaryBeamLaser", slot = 1 },
	{ name = "gravityBeam", slot = 5 },
	{ name = "pulseLaser", slot = 19 },
	{ name = "blackHoleGun", slot = 17 },
}
local CHECKS = #weaponStages + 2

local ufoID
local passCount = 0
local passed = {}

local function pass(key, description)
	if passed[key] then
		return
	end
	passed[key] = true
	passCount = passCount + 1
	Spring.Echo("[Area17-Lua-Test] ASSERTION PASSED (" .. passCount .. "): " .. description)
	if passCount == CHECKS then
		Spring.Echo("[Area17-Lua-Test] ALL AREA17 LUA INTEGRATION TESTS PASSED (" .. CHECKS .. " checks)")
	end
end

local function findUfo()
	local defID = UnitDefNames.ufo.id
	for _, unitID in ipairs(Spring.GetAllUnits()) do
		if Spring.GetUnitDefID(unitID) == defID then
			return unitID
		end
	end
end

-- The stage whose weapon the UFO script has selected, if any.
local function selectedStage()
	local slot = Spring.GetUnitRulesParam(ufoID, "active_weapon_slot")
	for index, stage in ipairs(weaponStages) do
		if stage.slot == slot then
			return index, stage
		end
	end
end

function gadget:Initialize()
	if visualMode then
		return
	end
	local ufoDef = UnitDefs[UnitDefNames.ufo.id]
	for _, stage in ipairs(weaponStages) do
		stage.weaponDefID = ufoDef.weapons[stage.slot].weaponDef
		Script.SetWatchWeapon(stage.weaponDefID, true)
	end
end

function gadget:ProjectileCreated(_, ownerID, weaponDefID)
	if visualMode or not ufoID or ownerID ~= ufoID then
		return
	end
	local index, stage = selectedStage()
	if stage and weaponDefID == stage.weaponDefID then
		pass(index, stage.name .. " produced its expected engine projectile")
	end
end

function gadget:GameFrame(frame)
	if visualMode then
		return
	end
	-- The Rust suite destroys the UFO once; follow the respawned one.
	if not ufoID or Spring.GetUnitIsDead(ufoID) ~= false then
		ufoID = findUfo()
		if not ufoID then
			return
		end
	end
	if (Spring.GetUnitRulesParam(ufoID, "selfMoveSpeedChange") or 0) > 1 then
		pass("haste", "haste changed the UFO movement multiplier")
	end
	if Spring.GetUnitRulesParam(ufoID, "beam_enabled") == -1 then
		pass("godGun", "God Gun activated the model-script beam")
	end
end

end
