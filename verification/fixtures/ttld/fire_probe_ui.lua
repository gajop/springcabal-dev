-- Isolated fixed-age images using the real TTLD LUPS configuration and class.
VFS.Include('lups/headers/general.lua')
VFS.Include('lups/headers/vectors.lua')
VFS.Include('lups/headers/mathenv.lua')
PRIO_MAJOR=0
LupsConfig={}
vsx,vsy,vpx,vpy=Spring.GetViewGeometry()
thisGameFrame=0
local simple=VFS.Include('lups/ParticleClasses/SimpleParticles2.lua')
simple:Initialize()
local options=VFS.Include('LuaUI/Configs/ttld_fire.lua')
local randomState=1
local function sample()
    randomState=(randomState*251+1)%65521
    return randomState/65521
end
options.random=sample
options.partpos='0,0,0'
options.pos={4400,144.25,531}
options.size=25*0.35
options.startRadius=25*0.6
options.force={0.5*0.09,3,-0.25*0.09}
local stage,shot=-1,-1
local particles={}
local function advance(n)
    thisGameFrame=n
    for at=#particles,1,-1 do
        local fx=particles[at];fx.frame=n-fx.firstGameFrame
        if n>=fx.dieGameFrame then fx:Destroy();table.remove(particles,at) end
    end
end
local function anchors()
    local anchor=MergeTable({count=1,life=100,lifeSpread=0,delaySpread=0,
        force={0,0,0},speed=0,size=0,sizeSpread=0,sizeGrowth=0,
        rotSpeed=0,rotSpeedSpread=0,rotSpread=0,startRadius=0,
        colormap={{0,0,0,0}},pos={9000,144.25,531},random=function() return 0.5 end},options)
    particles[#particles+1]=simple.Create(anchor)
    local marker=MergeTable({life=10,size=100,colormap={{1,1,1,1}},pos={4320,170,531}},anchor)
    particles[#particles+1]=simple.Create(marker)
end
function Update()
    Spring.WarpMouse(200,500)
    Spring.SetCameraState({name='ta',mode=1,px=4288,py=0,pz=600,height=650,angle=0.464,fov=45},0)
    local frame=Spring.GetGameFrame()
    if frame<30 then return end
    local nextStage=math.min(math.floor((frame-30)/30),4)
    if nextStage~=stage then
        local continuing=nextStage==1 and stage==0
        stage=nextStage
        local x,y,z=Spring.GetWind()
        Spring.Echo(string.format('[TTLDWind] stage=%d x=%.9g y=%.9g z=%.9g',stage,x,y,z))
        if continuing then advance(10)
        else
        for _,fx in ipairs(particles) do fx:Destroy() end
        particles={};randomState=1;thisGameFrame=0;anchors()
        local target=({9,10,45,60,90})[stage+1]
        for n=1,target do
            advance(n)
            if n%6==0 and math.floor(sample()*400)+1<399 then
                particles[#particles+1]=simple.Create(options)
            end
        end
        end
    end
    if frame>=45+30*stage and shot~=stage then
        shot=stage;Spring.SendCommands('screenshot png')
    end
    if frame>=190 then Spring.SendCommands('quitforce') end
end
function DrawWorld()
    gl.DepthTest(true);gl.DepthMask(false);gl.AlphaTest(GL.GREATER,0)
    simple.BeginDraw()
    for _,fx in ipairs(particles) do fx:Draw() end
    simple.EndDraw()
    gl.AlphaTest(false);gl.DepthMask(true);gl.DepthTest(false)
end
