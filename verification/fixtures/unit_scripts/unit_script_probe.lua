-- Runtime probe for Lua/CUS unit-script comparisons.
--
-- This file is copied into an isolated staged archive by the verification
-- suite. It is deliberately game-agnostic: the target unit and sample
-- frames come from modoptions, and it observes the engine's final piece
-- transforms rather than implementation-specific script internals.

function gadget:GetInfo()
	return {
		name = "Unit Script Conformance Probe",
		desc = "Samples unit piece transforms for Lua/WASM comparison",
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
local targetName = options.probe_unit or ""
local sampleFrames = {}
local sampleCount = 0
local requestedPieces = {}
local requestedInfoPieces = {}
local targetUnit
local infoEmitted = false
local doneFrame = 0

local function addListValues(value, destination)
	for item in string.gmatch(value or "", "[^,]+") do
		item = item:gsub("^%s+", ""):gsub("%s+$", "")
		if item ~= "" then
			destination[item] = true
		end
	end
end

for value in string.gmatch(options.probe_frames or "", "[^,]+") do
	local frame = tonumber(value)
	if frame and frame >= 0 then
		sampleFrames[frame] = true
		sampleCount = sampleCount + 1
		doneFrame = math.max(doneFrame, frame)
	end
end

addListValues(options.probe_pieces, requestedPieces)
addListValues(options.probe_info_pieces, requestedInfoPieces)

local function isTarget(unitID, unitDefID)
	local unitDef = UnitDefs[unitDefID or Spring.GetUnitDefID(unitID)]
	return unitDef and unitDef.name == targetName
end

local function findTarget()
	if targetUnit and Spring.ValidUnitID(targetUnit) then
		return
	end
	for _, unitID in ipairs(Spring.GetAllUnits()) do
		if isTarget(unitID) then
			targetUnit = unitID
			return
		end
	end
end

local function emitPiece(frame, name, piece)
	local matrix = {Spring.GetUnitPieceMatrix(targetUnit, piece)}
	if #matrix == 16 then
		Spring.Echo(string.format(
			"[UnitScriptProbe] frame=%d piece=%s m=" ..
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
		Spring.Echo(string.format("[UnitScriptProbe] ERROR frame=%d matrix-piece=%s", frame, name))
	end
end

local function emitPieceInfo(name, piece)
	local info = Spring.GetUnitPieceInfo(targetUnit, piece)
	if info and info.offset then
		Spring.Echo(string.format(
			"[UnitScriptProbe] info piece=%s offset=%.9f,%.9f,%.9f",
			name, info.offset[1], info.offset[2], info.offset[3]
		))
	end
end

local function sampleInfo()
	if infoEmitted then
		return
	end
	infoEmitted = true
	for name in pairs(requestedInfoPieces) do
		local piece = Spring.GetUnitPieceMap(targetUnit)[name]
		if piece then
			emitPieceInfo(name, piece)
		else
			Spring.Echo(string.format("[UnitScriptProbe] ERROR missing-info-piece=%s", name))
		end
	end
end

local function sample(frame)
	local pieceMap = Spring.GetUnitPieceMap(targetUnit)
	if not pieceMap then
		Spring.Echo(string.format("[UnitScriptProbe] ERROR frame=%d no-piece-map", frame))
		return
	end

	local names = {}
	if next(requestedPieces) == nil then
		for name in pairs(pieceMap) do
			names[#names + 1] = name
		end
		table.sort(names)
	else
		for name in pairs(requestedPieces) do
			names[#names + 1] = name
		end
		table.sort(names)
	end

	for _, name in ipairs(names) do
		local piece = pieceMap[name]
		if piece then
			emitPiece(frame, name, piece)
		else
			Spring.Echo(string.format(
				"[UnitScriptProbe] ERROR frame=%d missing-piece=%s",
				frame, name
			))
		end
	end
	Spring.Echo(string.format(
		"[UnitScriptProbe] SAMPLE_DONE frame=%d pieces=%d",
		frame, #names
	))
end

function gadget:Initialize()
	if targetName == "" or sampleCount == 0 then
		Spring.Echo("[UnitScriptProbe] ERROR probe_unit/probe_frames not configured")
		return
	end
	findTarget()
	if targetUnit and next(requestedInfoPieces) ~= nil then
		sampleInfo()
	end
end

function gadget:UnitCreated(unitID, unitDefID)
	if not targetUnit and isTarget(unitID, unitDefID) then
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
	if targetUnit and next(requestedInfoPieces) ~= nil then
		sampleInfo()
	end
	if targetUnit and sampleFrames[frame] then
		sample(frame)
	end
	if doneFrame > 0 and frame >= doneFrame then
		Spring.Echo(string.format(
			"[UnitScriptProbe] DONE unit=%d last_frame=%d",
			targetUnit or -1, doneFrame
		))
		gadgetHandler:RemoveGadget(self)
	end
end

-- Some comparisons observe ordinary gameplay rather than injecting commands
-- between gadget callins. Sample those after both runtimes and native physics
-- have finished the frame. The existing Parts Needed schedule stays unchanged.
if options.probe_phase == "post" then
	gadget.GameFramePost = gadget.GameFrame
	gadget.GameFrame = nil
end
