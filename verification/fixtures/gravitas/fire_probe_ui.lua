-- Run the original particle classes and original EmitFlame without changing
-- their shaders or equations. Only math.random is replaced for reproducibility.
local randomState = 1
math.random = function()
    -- Spring's Lua numbers are float32: keep every integer operation below
    -- 2^24 so the fixture generates exactly the same samples as Rust.
    randomState = (randomState * 251 + 1) % 65521
    return randomState / 65521
end
VFS.Include("lups/headers/general.lua")
VFS.Include("lups/headers/vectors.lua")
VFS.Include("lups/headers/mathenv.lua")
PRIO_MAJOR = 0
LupsConfig = {distortions = true}
vsx, vsy, vpx, vpy = Spring.GetViewGeometry()
thisGameFrame = 0
local simple = VFS.Include("lups/ParticleClasses/SimpleParticles2.lua")
local jitter = VFS.Include("lups/ParticleClasses/JitterParticles2.lua")
local post = VFS.Include("lups/ParticleClasses/distortionFBO.lua")
simple:Initialize()
jitter:Initialize()
post.Initialize()
post.ViewResize()
local particles = {}
local seed = 1
local target = 0
local perf = tonumber((Spring.GetModOptions() or {}).fire_perf) == 1
local countParticles = tonumber((Spring.GetModOptions() or {}).fire_diagnostic_counts) == 1
local countedFrame = -1
if perf then Spring.SendCommands("hideinterface 1") end
GG = {Lups = {AddParticlesArray = function(list)
    for i = 1, #list do
        randomState = seed + i - 1
        local class = list[i].class == "JitterParticles2" and jitter or simple
        particles[#particles + 1] = {class = class, fx = class.Create(list[i])}
    end
end}}
gadget = {}
gadgetHandler = {IsSyncedCode = function() return false end}
VFS.Include("LuaRules/Gadgets/lups_flame_jitter.lua")
-- Invoke the original burning-unit emitter with a stationary test unit.
Spring.GetUnitPosition = function() return 4400, 144.25, 531 end
Spring.GetUnitRadius = function() return 25 end
Spring.GetUnitVelocity = function() return 0.5, 0, -0.25 end
local burnLayer = 0
WG = {Lups = {
    GetStats = function() return 0 end,
    AddParticles = function(_, options)
        burnLayer = burnLayer + 1
        randomState = seed + burnLayer
        particles[#particles+1] = {class=simple, fx=simple.Create(options)}
        return #particles
    end,
}}
widget = {}
VFS.Include("LuaUI/Widgets/gfx_lups_units_on_fire.lua")
widget:Update()
widget:Update()
widget:Update()

function FireProbe(message)
    local fields = {}
    for value in message:gmatch("[^|]+") do fields[#fields+1] = value end
    if perf then
        thisGameFrame = Spring.GetGameFrame()
        target = thisGameFrame
        seed = target * 20
        burnLayer = 0
        randomState = seed
        if fields[2] == "burn" then
            onFireUnit(1, 1.0)
        elseif fields[2] == "flame" then
            seed = target * 10
            EmitFlame(4288, 144.25, 531, 0, 0.5, 0, 0, 0, 0, 500)
            gadget:GameFrame()
        end
        return
    end
    if fields[2] == "probe" then
        for _, p in ipairs(particles) do p.fx:Destroy() end
        particles = {}
        target = tonumber(fields[3])
        for n = 30, target do
            thisGameFrame = n
            seed = n * 20
            burnLayer = 0
            randomState = seed
            onFireUnit(1, 1.0)
            if n % 15 == 0 then
                seed = n * 10
                EmitFlame(4288, 144.25, 531, 0, 0.5, 0, 0, 0, 0, 500)
                gadget:GameFrame()
            end
        end
    elseif fields[2] == "shot" then
        Spring.SendCommands("screenshot png")
    elseif fields[2] == "done" then
        Spring.SendCommands("quitforce")
    end
end

function Update()
    Spring.WarpMouse(1100, 500)
    Spring.SetCameraState({name="ta", mode=1, px=4288, py=0, pz=600,
        height=650, angle=0.464, fov=45}, 0)
    if perf then target = Spring.GetGameFrame() end
    local n = target
    -- Compact once. Removing every expired effect separately shifted the
    -- entire surviving list repeatedly at high emitter counts.
    local kept = 0
    for i = 1, #particles do
        local p = particles[i]
        local fx = p.fx
        fx.frame = n - fx.firstGameFrame
        if n > fx.dieGameFrame then fx:Destroy()
        else kept = kept + 1; particles[kept] = p end
    end
    for i = #particles, kept+1, -1 do particles[i] = nil end
    if countParticles and n ~= countedFrame and (n==300 or n==600 or n==899) then
        countedFrame = n
        local normal, distortion = 0,0
        for _,p in ipairs(particles) do
            local data = assert(p.fx.gpuParticles, "diagnostic particle records")
            for at=0,#data-1,28 do
                local age = p.fx.frame - data[at+12]
                if age>0 and age<=data[at+8] then
                    if p.class==jitter then distortion=distortion+1 else normal=normal+1 end
                end
            end
        end
        Spring.Echo("[FireCounts] frame="..n.." normal="..normal.." distortion="..distortion)
    end
end

function DrawWorld()
    gl.DepthTest(true)
    gl.DepthMask(false)
    gl.AlphaTest(GL.GREATER, 0)
    simple.BeginDraw()
    for _, p in ipairs(particles) do
        if p.class == simple and p.fx.layer == 0 then p.fx:Draw() end
    end
    simple.EndDraw()
    gl.AlphaTest(false)
    post.BeginDraw()
    gl.ActiveFBO(post.fbo, function()
        gl.Blending(GL.ONE, GL.ONE)
        local getFrame = Spring.GetGameFrame
        Spring.GetGameFrame = function() return target end
        jitter.BeginDrawDistortion()
        Spring.GetGameFrame = getFrame
        for _, p in ipairs(particles) do
            if p.class == jitter then p.fx:DrawDistortion() end
        end
        jitter.EndDrawDistortion()
    end)
    post.EndDraw()
    gl.AlphaTest(GL.GREATER, 0)
    simple.BeginDraw()
    for _, p in ipairs(particles) do
        if p.class == simple and p.fx.layer == 1 then p.fx:Draw() end
    end
    simple.EndDraw()
    gl.AlphaTest(false)
    gl.DepthTest(false)
end
