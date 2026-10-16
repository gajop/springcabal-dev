-- Golden gallery: spawns every CEG, or every unit type, one after another in a
-- single engine run and captures zoomed screenshots at exact frames.
--
-- Copied into a staged game archive by verification/games/gallery.sh.
-- Modoptions:
--   gallery          "ceg" or "anim"
--   gallery_out      write-dir relative output directory
--   gallery_only     optional comma-separated subset of CEG / unit def names
--   gallery_repeats  CEG spawns per zoom level (default 4)
--
-- Determinism: both halves of this gadget build the same schedule from the
-- same inputs (sorted names, map heights).  The synced half spawns, orders and
-- removes on fixed absolute frames; the unsynced half only moves the camera and
-- captures on those frames.  Nothing depends on when a message arrives, so with
-- FixedRNGSeed in the start script the simulation, and every game's own logic
-- acting on the gallery's units, repeats exactly.
--
-- Isolation (anim): the game's rules run as they ship, so they would spawn
-- their level, waves and respawns, and every one of those units' logic draws
-- from the synced RNG that the unit scripts share.  A change to one unit's
-- logic would then move every later unit's random start angles and idles.  So
-- the synced half removes every unit but the gallery's own, every frame, and
-- reseeds the synced RNG for every frame from the unit's name and the frame
-- within its job.  A unit's captures then depend only on its own script, the
-- rules' logic for it, and whatever global logic (spawn timers) the rules run
-- with no units around.  Units a gallery unit creates are removed too.
--
-- The reseed for frame N happens at the end of frame N-1 (GameFramePost), so
-- every draw of frame N comes from one stream, whatever order the game's code
-- runs in: Lua rules gadgets run before this gadget and a WASM rules module
-- after it, and a reseed inside GameFrame split them onto different streams.
--
-- Spring.SetVideoCapturingMode(true) makes the engine simulate exactly one
-- frame per drawn frame with interpolation pinned at 0, so a capture taken
-- while GetGameFrame() == N shows simulation frame N.
--
-- CEG particles use the engine's unsynced RNG, which nothing can seed, so CEG
-- captures still vary from run to run and are compared statistically.
--
-- The `gallery` modoption also tells the game's own UI module to run in gallery
-- mode: it keeps the widgets that draw world effects (glows, fire, lights,
-- post-processing) and drops the HUD, RmlUi documents, input and camera.  So a
-- capture is taken after every screen effect (DrawScreenPost), and shows what a
-- player would see of the unit or effect, minus the HUD.

function gadget:GetInfo()
	return {
		name = "Golden Gallery",
		desc = "Captures every CEG / unit animation for golden comparison",
		author = "springcabal verification",
		license = "GPL v2 or later",
		layer = 1000001,
		enabled = true,
	}
end

local options = Spring.GetModOptions() or {}
local MODE = options.gallery or ""
if MODE ~= "ceg" and MODE ~= "anim" then
	return
end

local PREFIX = "[Gallery] "
local SYNCED = gadgetHandler:IsSyncedCode()

--------------------------------------------------------------------------------
-- Schedule, identical in both halves
--------------------------------------------------------------------------------

local FIRST_FRAME = 30
local SPACING = tonumber(options.gallery_spacing) or 700
-- CEGs: background at +3, spawn at +4, captures 2 and 12 frames after the spawn.
local CEG_ZOOMS = {{"near", 180}, {"far", 520}}
local CEG_REPEATS = tonumber(options.gallery_repeats) or 4
local CEG_BACKGROUND, CEG_SPAWN, CEG_SHOTS, CEG_LENGTH = 3, 4, {2, 12}, 20
local CEG_RADIUS = tonumber(options.gallery_ceg_radius) or 64
local CEG_DAMAGE = tonumber(options.gallery_ceg_damage) or 100
-- Units: spawn at +0; each phase issues its order (if any) at its start and
-- captures 15 and 30 frames later (idle only at 30); removal at +98.
local ANIM_PHASES = {
	{name = "idle", start = 0, capture = {30}},
	{name = "move", start = 32, order = "move", capture = {15, 30}},
	{name = "attack", start = 64, order = "attack", capture = {15, 30}},
}
local ANIM_REMOVE, ANIM_LENGTH = 98, 100
local TEAM = tonumber(options.gallery_team) or 0

local UnitDefNames = UnitDefNames
if not UnitDefNames then
	UnitDefNames = {}
	for _, def in pairs(UnitDefs) do
		UnitDefNames[def.name] = def
	end
end

local function sorted(set)
	local list = {}
	for key in pairs(set) do
		list[#list + 1] = key
	end
	table.sort(list)
	return list
end

local function parseList(value)
	local set = {}
	for item in string.gmatch(value or "", "[^,]+") do
		set[item:gsub("^%s+", ""):gsub("%s+$", "")] = true
	end
	return next(set) and set or nil
end

-- CEG names, found the way the engine's gamedata/explosions.lua finds them.
local function cegNames()
	local names = {}
	for _, file in ipairs(VFS.DirList("effects", "*.lua", VFS.MOD)) do
		local ok, defs = pcall(VFS.Include, file, nil, VFS.MOD)
		if ok and type(defs) == "table" then
			for name, def in pairs(defs) do
				if type(def) == "table" then
					names[name] = true
				end
			end
		elseif not SYNCED then
			Spring.Echo(PREFIX .. "ERROR effects-file=" .. file .. " " .. tostring(defs))
		end
	end
	return sorted(names)
end

local function unitNames()
	local names = {}
	for _, def in pairs(UnitDefs) do
		if def.modelname and def.modelname ~= "" then
			names[def.name] = true
		end
	end
	return sorted(names)
end

-- Land spots on a grid; reused in order once the map runs out, by which time
-- whatever was captured there has long finished.
local function spots(count)
	local list = {}
	local x, z = SPACING, SPACING
	while #list < count and z < Game.mapSizeZ - SPACING do
		if Spring.GetGroundHeight(x, z) > 5 then
			list[#list + 1] = {x, z}
		end
		x = x + SPACING
		if x > Game.mapSizeX - SPACING then
			x, z = SPACING, z + SPACING
		end
	end
	local unique = #list
	if unique >= 8 then
		for i = unique + 1, count do
			list[i] = list[(i - 1) % unique + 1]
		end
	end
	return list
end

local function buildSchedule()
	local names = MODE == "ceg" and cegNames() or unitNames()
	local only = parseList(options.gallery_only)
	if only then
		local filtered = {}
		for _, name in ipairs(names) do
			if only[name] then
				filtered[#filtered + 1] = name
			end
		end
		names = filtered
	end
	local jobs = {}
	local wanted = MODE == "ceg" and #names * #CEG_ZOOMS * CEG_REPEATS or #names
	local places = spots(wanted)
	local frame = FIRST_FRAME
	local function add(job, length)
		local place = places[#jobs + 1]
		if not place then
			return
		end
		job.x, job.z, job.start = place[1], place[2], frame
		jobs[#jobs + 1] = job
		frame = frame + length
	end
	for _, name in ipairs(names) do
		if MODE == "ceg" then
			for _, zoom in ipairs(CEG_ZOOMS) do
				for r = 1, CEG_REPEATS do
					add({name = name, zoom = zoom[1], dist = zoom[2], rep = r}, CEG_LENGTH)
				end
			end
		else
			local def = UnitDefNames[name]
			add({
				name = name,
				radius = math.max(def.radius or 20, 12),
				canMove = (def.speed or 0) > 0,
				hasWeapon = def.weapons ~= nil and #def.weapons > 0,
			}, ANIM_LENGTH)
		end
	end
	return jobs, frame, #places
end

local JOBS, END_FRAME, SPOTS = buildSchedule()

-- The job running on `frame`, the frame relative to its start, and its index.
local function jobAt(frame)
	if frame < FIRST_FRAME then
		return nil
	end
	local length = MODE == "ceg" and CEG_LENGTH or ANIM_LENGTH
	local index = math.floor((frame - FIRST_FRAME) / length) + 1
	local job = JOBS[index]
	if job then
		return job, frame - job.start, index
	end
end

local function phaseEnabled(job, phase)
	return not ((phase.order == "move" and not job.canMove) or (phase.order == "attack" and not job.hasWeapon))
end

--------------------------------------------------------------------------------
-- Synced: spawn, order and remove on schedule
--------------------------------------------------------------------------------

if SYNCED then
	local unitID

	-- Projectiles (and so CEG particles) outside line of sight are not drawn.
	function gadget:Initialize()
		for _, allyTeam in ipairs(Spring.GetAllyTeamList()) do
			Spring.SetGlobalLos(allyTeam, true)
		end
	end

	local function order(cmd, x, z)
		if unitID and Spring.ValidUnitID(unitID) then
			Spring.GiveOrderToUnit(unitID, cmd, {x, Spring.GetGroundHeight(x, z), z}, 0)
		end
	end

	-- A seed from the unit's name (not its place in the schedule), so adding or
	-- removing a unit type leaves the others' random numbers alone.  Lua numbers
	-- are 32-bit floats here, exact only below 2^24: the hash stays below
	-- 65521 * 33 + 255 and the seed below 65521 * 256, so every frame of a job
	-- (ANIM_LENGTH < 256) gets its own seed.
	local function frameSeed(name, t)
		local hash = 5381
		for i = 1, #name do
			hash = (hash * 33 + name:byte(i)) % 65521
		end
		return hash * 256 + t
	end

	-- Removes every unit but the gallery's (reclaimed: no explosion, no wreck).
	local function clearWorld()
		for _, other in ipairs(Spring.GetAllUnits()) do
			if other ~= unitID then
				Spring.DestroyUnit(other, false, true)
			end
		end
	end

	-- Seeds the next frame's stream, after all of this frame's game code.
	function gadget:GameFramePost(frame)
		if MODE ~= "anim" then
			return
		end
		local job, t = jobAt(frame + 1)
		if job then
			math.randomseed(frameSeed(job.name, t))
		end
	end

	function gadget:GameFrame(frame)
		if MODE == "anim" then
			clearWorld()
		end
		local job, t, index = jobAt(frame)
		if not job then
			return
		end
		if MODE == "ceg" then
			if t == CEG_SPAWN then
				if not Spring.SpawnCEG(job.name, job.x, Spring.GetGroundHeight(job.x, job.z), job.z,
						0, 1, 0, CEG_RADIUS, CEG_DAMAGE) then
					Spring.Echo(PREFIX .. "ERROR spawn-ceg name=" .. job.name)
				end
			end
			return
		end
		if t == 0 then
			unitID = Spring.CreateUnit(job.name, job.x, Spring.GetGroundHeight(job.x, job.z), job.z, "south", TEAM)
			if not unitID then
				Spring.Echo(PREFIX .. "ERROR create-unit name=" .. job.name)
			end
			Spring.SetGameRulesParam("gallery_unit", unitID or -1)
			Spring.SetGameRulesParam("gallery_unit_job", index)
		end
		for _, phase in ipairs(ANIM_PHASES) do
			if phase.order and t == phase.start and phaseEnabled(job, phase)
					and unitID and Spring.ValidUnitID(unitID) then
				local ux, _, uz = Spring.GetUnitPosition(unitID)
				if phase.order == "move" then
					order(CMD.MOVE, ux + 300, uz)
				else
					order(CMD.ATTACK, ux + 250, uz)
				end
			end
		end
		if t == ANIM_REMOVE and unitID and Spring.ValidUnitID(unitID) then
			Spring.DestroyUnit(unitID, false, true)
			unitID = nil
		end
	end

	return
end

--------------------------------------------------------------------------------
-- Unsynced: camera and captures on schedule
--------------------------------------------------------------------------------

local OUT = options.gallery_out or "gallery"
local CROP = tonumber(options.gallery_crop) or 512
-- Every capture is box-filtered on the GPU (mipmaps) and saved as raw RGB at
-- these sizes: 64 for comparison, 128 for contact sheets.  gallery_full=1 also
-- keeps the full-size crop as JPEG for inspection.
local SIZES = {64, 128}
local FULL = options.gallery_full == "1"
-- CEGs are viewed from high above, units from a low angle so limbs and weapons
-- stay visible.
local PITCH = tonumber(options.gallery_pitch) or (MODE == "ceg" and 2.45 or 2.15)
local pendingShot = nil
local finished = false

local function log(fmt, ...)
	Spring.Echo(PREFIX .. string.format(fmt, ...))
end

-- The capture runs after the mouse cursor is drawn, so the cursor is parked in
-- a corner, outside the centred crop and clear of the edge-scroll band.
local CURSOR_PARK = 48

local function parkCursor()
	Spring.WarpMouse(CURSOR_PARK, CURSOR_PARK)
end

local function setCamera(x, y, z, dist)
	Spring.SetCameraState({
		name = "spring", mode = 2,
		px = x, py = y, pz = z,
		dist = dist, rx = PITCH, ry = 0.0, rz = 0.0, fov = 45,
	}, 0)
end

local function shoot(frame, file, pose)
	pendingShot = {frame = frame, file = file, pose = pose}
end

local function logPose(unitID, label)
	local map = Spring.GetUnitPieceMap(unitID)
	if not map then
		log("ERROR pose-no-piece-map %s", label)
		return
	end
	for _, name in ipairs(sorted(map)) do
		local m = {Spring.GetUnitPieceMatrix(unitID, map[name])}
		if #m == 16 then
			local out = {}
			for i = 1, 16 do
				out[i] = string.format("%.4f", m[i])
			end
			log("pose %s piece=%s m=%s", label, name, table.concat(out, ","))
		end
	end
end

-- Unset rules params return nothing, and values may come back as strings.
local function rulesNumber(key)
	local value = Spring.GetGameRulesParam(key)
	return tonumber(value)
end

local function galleryUnit(index)
	if rulesNumber("gallery_unit_job") ~= index then
		return nil
	end
	local unitID = rulesNumber("gallery_unit")
	if unitID and unitID >= 0 and Spring.ValidUnitID(unitID) then
		return unitID
	end
end

local function cegFrame(job, t, frame)
	local base = string.format("%s/%s/%s/r%d", OUT, job.name, job.zoom, job.rep)
	setCamera(job.x, Spring.GetGroundHeight(job.x, job.z) + job.dist * 0.1, job.z, job.dist)
	if t == CEG_BACKGROUND then
		shoot(frame, base .. "/bg")
	end
	for _, offset in ipairs(CEG_SHOTS) do
		if t == CEG_SPAWN + offset then
			shoot(frame, string.format("%s/f%02d", base, offset))
		end
	end
end

-- How far the camera stands from a unit: six times its def radius, at least
-- 170.  Some defs declare a radius far below their model's size (MyCube's iglu:
-- radius 20, about 430 elmos across), which put the camera inside the model.
-- When the model's half-extent reaches past half that distance, the camera is
-- framed on the model instead.  Models are not reframed for merely exceeding
-- their radius: many games draw units scaled (TTLD) or keep far-off helper
-- pieces, and their radius framing is right.
local REFRAME = 2
local distances = {}
local function cameraDistance(job)
	local dist = distances[job.name]
	if dist then
		return dist
	end
	dist = math.max(170, job.radius * 6)
	local def = UnitDefNames[job.name]
	local model = def and def.model
	if model and model.maxx then
		local half = 0.5 * math.max(model.maxx - model.minx, model.maxy - model.miny, model.maxz - model.minz)
		if half * REFRAME > dist then
			log("note model-bounds unit=%s radius=%.1f half-extent=%.1f: camera distance %.0f -> %.0f",
				job.name, job.radius, half, dist, half * 6)
			dist = half * 6
		elseif half > job.radius then
			log("note model-bounds unit=%s radius=%.1f half-extent=%.1f: camera distance %.0f kept",
				job.name, job.radius, half, dist)
		end
	end
	distances[job.name] = dist
	return dist
end

local function animFrame(job, t, frame, index)
	local dist = cameraDistance(job)
	local unitID = galleryUnit(index)
	if unitID then
		local _, _, _, mx, my, mz = Spring.GetUnitPosition(unitID, true)
		-- The spring camera always focuses on the ground, so an aircraft
		-- (Area 17's drone cruises 200 elmos up) would be above the view.  Focus
		-- where the view ray through the unit meets the ground instead (marched
		-- in steps: the ground there can be far lower), and back off by as
		-- much, so the unit sits in the centre at the usual distance.
		if my - Spring.GetGroundHeight(mx, mz) > job.radius then
			local down, back = -math.cos(PITCH), math.sin(PITCH)
			local along = 0
			while along < 4000 and my - down * along > Spring.GetGroundHeight(mx, mz - back * along) do
				along = along + 4
			end
			mz = mz - back * along
			dist = dist + along
		end
		setCamera(mx, my, mz, dist)
	else
		setCamera(job.x, Spring.GetGroundHeight(job.x, job.z) + job.radius, job.z, dist)
	end
	for _, phase in ipairs(ANIM_PHASES) do
		if phaseEnabled(job, phase) then
			for _, offset in ipairs(phase.capture) do
				if t == phase.start + offset then
					local label = string.format("unit=%s phase=%s frame=%d", job.name, phase.name, offset)
					if unitID then
						shoot(frame, string.format("%s/%s/%s-f%02d", OUT, job.name, phase.name, offset),
							{unitID, label})
					else
						log("note unit-gone %s", label)
					end
				end
			end
		end
	end
end

function gadget:Initialize()
	Spring.SendCommands("hideinterface 1")
	Spring.SetVideoCapturingMode(true)
	Spring.SetVideoCapturingTimeOffset(0)
	parkCursor()
	log("start mode=%s items=%d frames=%d-%d out=%s", MODE, #JOBS, FIRST_FRAME, END_FRAME, OUT)
	if SPOTS < math.min(8, #JOBS) then
		log("ERROR only %d land spots on this map", SPOTS)
	end
	-- Record what this run actually rendered with.
	local settings = {}
	for _, key in ipairs({"AllowDeferredMapRendering", "AllowDeferredModelRendering", "AdvMapShading",
			"AdvUnitShading", "Shadows", "Water", "MaxParticles", "SoftParticles", "GroundDetail",
			"GrassDetail", "MaxMapDetail", "LODScale"}) do
		settings[#settings + 1] = key .. "=" .. tostring(Spring.GetConfigString(key, "?"))
	end
	log("graphics gpu=%s %s", tostring(Platform and Platform.gpu or "?"), table.concat(settings, " "))
end

function gadget:GameFrame(frame)
	if finished then
		return
	end
	if frame >= END_FRAME then
		finished = true
		log("COMPLETE items=%d", #JOBS)
		Spring.SendCommands("quitforce")
		return
	end
	parkCursor()
	local job, t, index = jobAt(frame)
	if not job then
		return
	end
	if MODE == "ceg" then
		cegFrame(job, t, frame)
	else
		animFrame(job, t, frame, index)
	end
end

-- GPU downscaling: the crop is copied into a mipmapped texture and drawn into
-- small FBO textures, so each saved pixel is the exact box average of its block.
local cropTexture, smallTextures = nil, {}

local function ensureTextures(size)
	if cropTexture then
		return true
	end
	cropTexture = gl.CreateTexture(size, size, {
		min_filter = GL.LINEAR_MIPMAP_LINEAR, mag_filter = GL.LINEAR,
		wrap_s = GL.CLAMP_TO_EDGE, wrap_t = GL.CLAMP_TO_EDGE,
	})
	for _, small in ipairs(SIZES) do
		smallTextures[small] = gl.CreateTexture(small, small, {
			min_filter = GL.LINEAR, mag_filter = GL.LINEAR, fbo = true,
		})
	end
	return cropTexture ~= nil
end

local function saveCapture(x0, y0, size, file)
	if not ensureTextures(size) then
		log("ERROR save-failed file=%s (textures)", file)
		return
	end
	gl.CopyToTexture(cropTexture, 0, 0, x0, y0, size, size)
	gl.GenerateMipmap(cropTexture)
	for _, small in ipairs(SIZES) do
		local target = string.format("%s-%d.raw", file, small)
		local ok = false
		gl.RenderToTexture(smallTextures[small], function()
			gl.Blending(false)
			gl.DepthTest(false)
			gl.Color(1, 1, 1, 1)
			gl.Texture(cropTexture)
			gl.TexRect(-1, -1, 1, 1, 0, 0, 1, 1)
			gl.Texture(false)
			-- The FBO copy is already in screen orientation.
			ok = gl.SaveImage(0, 0, small, small, target, {yflip = false})
		end)
		if not ok then
			log("ERROR save-failed file=%s", target)
		end
	end
	if FULL and not gl.SaveImage(x0, y0, size, size, file .. ".jpg") then
		log("ERROR save-failed file=%s.jpg", file)
	end
end

function gadget:Shutdown()
	if cropTexture then
		gl.DeleteTexture(cropTexture)
	end
	for _, tex in pairs(smallTextures) do
		gl.DeleteTexture(tex)
	end
end

-- DrawScreenPost runs after every client's DrawScreenEffects, so the capture
-- includes the UI module's screen passes (Parts Needed's bloom and wisp
-- sprites, TTLD's deferred lights), which run after this gadget's own
-- DrawScreenEffects.  With the interface hidden and no RmlUi document in
-- gallery mode, nothing else is drawn in between.
function gadget:DrawScreenPost(vsx, vsy)
	if not pendingShot or Spring.GetGameFrame() ~= pendingShot.frame then
		return
	end
	local size = math.min(CROP, vsx, vsy)
	local x0, y0 = math.floor((vsx - size) / 2), math.floor((vsy - size) / 2)
	Spring.CreateDir(pendingShot.file:match("^(.*)/[^/]+$"))
	saveCapture(x0, y0, size, pendingShot.file)
	log("shot file=%s frame=%d", pendingShot.file, pendingShot.frame)
	if pendingShot.pose then
		logPose(pendingShot.pose[1], pendingShot.pose[2])
	end
	pendingShot = nil
end
