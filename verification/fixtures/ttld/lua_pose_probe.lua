function gadget:GetInfo()
    return {
        name = "TTLD Lua pose probe",
        desc = "Deterministic Lua/CUS animation conformance probe",
        author = "springcabal verification",
        layer = 1000000,
        enabled = true,
    }
end

if not gadgetHandler:IsSyncedCode() then
    return
end

local target
local skeletonEmitted = false
local sampleFrames = {
    [20] = true, [29] = true, [31] = true,
    [33] = true, [35] = true, [39] = true, [42] = true,
    [45] = true, [50] = true, [55] = true, [60] = true,
    [70] = true, [80] = true, [91] = true, [93] = true,
    [95] = true, [98] = true, [100] = true, [103] = true,
    [106] = true, [110] = true, [115] = true, [120] = true,
    [130] = true, [146] = true, [148] = true, [150] = true,
    [155] = true, [160] = true, [163] = true, [168] = true,
    [173] = true, [180] = true, [190] = true, [195] = true,
}
local posePieces = {"Torso", "Hand_Right", "Hand_Left"}

local function findTarget()
    local targetDef = UnitDefNames.bloodmage.id
    for _, unitID in ipairs(Spring.GetAllUnits()) do
        if Spring.GetUnitDefID(unitID) == targetDef then
            target = unitID
            return
        end
    end
end

local function emitSkeleton()
    if skeletonEmitted or not target then
        return
    end
    skeletonEmitted = true
    local pieceMap = Spring.GetUnitPieceMap(target)
    if not pieceMap then
        Spring.Echo("[UnitScriptProbe] ERROR no-piece-map")
        return
    end
    for name, piece in pairs(pieceMap) do
        Spring.Echo(string.format("[UnitScriptProbe] map piece=%s num=%d", name, piece))
        local info = Spring.GetUnitPieceInfo(target, piece)
        if info and info.offset then
            Spring.Echo(string.format(
                "[UnitScriptProbe] info piece=%s offset=%.9f,%.9f,%.9f",
                name, info.offset[1], info.offset[2], info.offset[3]
            ))
        end
    end
end

local function emitMatrix(frame, name, piece)
    local matrix = {Spring.GetUnitPieceMatrix(target, piece)}
    if #matrix ~= 16 then
        Spring.Echo(string.format(
            "[UnitScriptProbe] ERROR frame=%d matrix-piece=%s", frame, name
        ))
        return
    end
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
end

local function sample(frame)
    local pieceMap = Spring.GetUnitPieceMap(target)
    if not pieceMap then
        Spring.Echo(string.format("[UnitScriptProbe] ERROR frame=%d no-piece-map", frame))
        return
    end
    local count = 0
    for _, name in ipairs(posePieces) do
        local piece = pieceMap[name]
        if piece then
            emitMatrix(frame, name, piece)
            count = count + 1
        else
            Spring.Echo(string.format(
                "[UnitScriptProbe] ERROR frame=%d missing-piece=%s", frame, name
            ))
        end
    end
    Spring.Echo(string.format(
        "[UnitScriptProbe] SAMPLE_DONE frame=%d pieces=%d", frame, count
    ))
end

local function trigger(level, tx, tz)
    local env = Spring.UnitScript.GetScriptEnv(target)
    if not env or not env.script then
        Spring.Echo("[UnitScriptProbe] ERROR no-script-env")
        return
    end
    Spring.UnitScript.CallAsUnit(target, env.script.CastAnimation, nil, level, tx, tz)
    Spring.Echo(string.format(
        "[UnitScriptProbe] trigger frame=%d cast=true", Spring.GetGameFrame()
    ))
end

function gadget:Initialize()
    -- The normal intro pauses a fresh original-game launch. This isolated
    -- fixture is already in gameplay, matching the WASM headless run.
    findTarget()
    emitSkeleton()
end

function gadget:GameFrame(frame)
    if not target or not Spring.ValidUnitID(target) then
        findTarget()
    end
    if not target then
        return
    end
    emitSkeleton()
    if frame == 30 then
        trigger(1)
    elseif frame == 90 then
        trigger(2, 6000, 6000)
    elseif frame == 145 then
        trigger(3, 6000, 6000)
    end
    if sampleFrames[frame] then
        sample(frame)
    end
    if frame >= 195 then
        Spring.Echo(string.format(
            "[UnitScriptProbe] DONE unit=%d last_frame=195", target
        ))
        gadgetHandler:RemoveGadget(self)
    end
end
