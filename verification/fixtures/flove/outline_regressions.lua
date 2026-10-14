-- Exercise the real material and silhouette callbacks, without writing the game.
local root = assert(arg[1], 'expected the Lua game directory')
local function noop() end
local state = {frame = 120, hover = 11, above = false, offscreen = false, units = {
    [11] = {def = 1, created = 110}, [12] = {def = 2, created = 0},
    [13] = {def = 3, created = 0}, [14] = {def = 4, created = 0}, [15] = {def = 5}}}
local defs = {
    {name='treelevel1',customParams={tree=true}}, {name='treelevel2',customParams={tree=true}},
    {name='treelevel3',customParams={tree=true}}, {name='spire',customParams={}},
    {name='base',customParams={effect=true}}}
local gl = setmetatable({}, {__index=function() return noop end})
local shaderIDs, shaders, uniforms, draws = 0, {}, {}, {}
local colour
function gl.GetUniformLocation(_,name) return name end
function gl.Uniform(name,...) uniforms[name]={...} end
function gl.Color(...) colour={...} end
function gl.Unit(id,_,_,noLuaCall)
    assert(noLuaCall, 'raw silhouette invoked material callback')
    draws[id]={colour=colour,deformation=uniforms.treeDeformation}
end
function gl.CreateList() return 1 end
function gl.CreateShader(def) shaderIDs=shaderIDs+1; shaders[shaderIDs]=def; return shaderIDs end
function gl.RenderToTexture(_,fn) fn() end
local Spring = {
    GetGameFrame=function() return state.frame end,
    GetVisibleUnits=function() return {11,12,13,14,15,99} end,
    GetUnitDefID=function(id) return state.units[id] and state.units[id].def end,
    GetUnitHealth=function() return 100,100,0,0,1 end,
    GetUnitRulesParam=function(id,key) if key=='createdFrame' then return state.units[id].created end end,
    GetUnitHeight=function() return 150 end,
    GetMouseState=function() return 10,20,false,false,false,state.offscreen end,
    IsAboveMiniMap=function() return false end,
    TraceScreenRay=function() return 'unit',state.hover end,
    GetUnitIsDead=function(id) return state.units[id] and state.units[id].dead end,
    Log=function(_,_,msg) error(msg) end, ALL_UNITS=-1}
local env = setmetatable({widget={},Spring=Spring,UnitDefs=defs,gl=gl,
    GL=setmetatable({},{__index=function() return 1 end}),
    WG={Chili={Screen0={IsAbove=function() return state.above end}}},
    VFS={LoadFile=function(name) local f=assert(io.open(root..'/'..name)); local s=f:read('*a'); f:close(); return s end},
    widgetHandler={GetViewSizes=function() return 800,600 end}}, {__index=_G})
local chunk=assert(loadfile(root..'/LuaUI/Widgets/gfx_outline.lua')); setfenv(chunk,env)(); env.widget:Initialize()
local function draw() draws={}; env.widget:DrawWorldPreUnit() end
local function green(id) local c=assert(draws[id]).colour; return c[1]>.05 and c[2]>.9 end
for _,id in ipairs({11,12}) do state.hover=id; draw(); assert(green(id),'upgradeable tree has no hover rim') end
state.hover=13; draw(); assert(not green(13),'level-three tree advertises an upgrade')
state.hover=11; state.units[11].dead=true; draw(); assert(not green(11),'dead tree advertises an upgrade')
state.units[11].dead=false; state.above=true; draw(); assert(not green(11),'hover leaked through UI')
state.above=false; state.offscreen=true; draw(); assert(not green(11),'off-window hover')
state.offscreen=false; draw(); assert(not draws[15] and not draws[99],'hidden or missing unit drawn')
print('PASS upgrade hover: levels 1/2 only, live units, no UI/off-window leakage')
local materialEnv=setmetatable({Spring=Spring,UnitDefs=defs,GL=env.GL,gl=gl,include=function() return {} end},{__index=_G})
chunk=assert(loadfile(root..'/ModelMaterials/1_tree_normalmapping.lua')); setfenv(chunk,materialEnv)
local materials=chunk(); local material=materials.tree; material.shader=100
for _,frame in ipairs({120,121,137,180}) do
    state.frame=frame; draw()
    for _,id in ipairs({11,12,13,14}) do
        local silhouette=assert(draws[id]).deformation
        uniforms={}; material.DrawUnit(id,material)
        assert(math.abs(silhouette[1]-uniforms.frameLoc[1])<1e-12,'sway mismatch')
        assert(silhouette[2]==uniforms.grownPercentage[1],'growth mismatch')
        if id~=14 then assert(silhouette[3]==uniforms.height[1],'height mismatch') end
    end
end
assert(shaders[1].vertex:find('deformTree',1,true), 'outline has no deformation vertex shader')
for _,id in ipairs({2,3}) do assert(shaders[id].fragment:find('c.rgb * c.a',1,true),'blur destroys rim colour') end
print('PASS silhouette uniforms match the actual material callback across sway and growth frames')
env.options.lowQualityOutlines.value=true; state.hover=11; draw(); assert(green(11),'fallback lost hover')
print('PASS line-outline fallback retains hover')
