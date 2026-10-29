-- Exercise the shipped particle expression compiler and its mutable environments.
local root = assert(arg[1], 'expected the Lua Gravitas game directory')
local compilations = 0
local env = setmetatable({Spring = {Echo = function() end}, print = error,
    loadstring = function(code)
        compilations = compilations + 1
        return loadstring(code)
    end}, {__index = _G})
local chunk = assert(loadfile(root .. '/lups/headers/mathenv.lua'))
setfenv(chunk, env)()
local text = 'x,y,z | x=radius*2,y=life+1,z=x-y'
local first = env.ParseParamString(text)
local second = env.ParseParamString(text)
assert(first ~= second, 'separate expressions shared a mutable function environment')
assert(compilations == 1, 'identical expressions were compiled again')
local x,y,z = env.ProcessParamCode(first, {radius=3,life=2})
assert(x==6 and y==3 and z==3, 'first particle locals changed')
x,y,z = env.ProcessParamCode(second, {radius=10,life=4})
assert(x==20 and y==5 and z==15, 'second particle reused old locals')
x,y,z = env.ProcessParamCode(first, {radius=1,life=7})
assert(x==2 and y==8 and z==-6, 'first expression kept the second environment')
for i=1,260 do
    local fn = env.ParseParamString(tostring(i)..',0,0')
    assert(env.ProcessParamCode(fn,{})==i, 'bounded-cache rollover changed an expression')
end
x,y,z = env.ProcessParamCode(env.ParseParamString(text), {radius=4,life=5})
assert(x==8 and y==6 and z==2, 'rollover retained stale locals')
print('PASS Lups expressions: one compilation, fresh functions, current locals, bounded-cache rollover')

-- Execute the real batch implementation against an in-memory VBO. Check GPU
-- contents at draw time, including wraps, visibility changes and reallocation.
local uploads,draws = 0,0
local gl = setmetatable({}, {__index=function() return function() end end})
gl.CreateShader = function() return 1 end
gl.GetUniformLocation = function() return 1 end
gl.GetVBO = function()
    return {
        Define=function(self,capacity) self.capacity=capacity;self.data={} end,
        Upload=function(self,values,_,offset,first,last)
            uploads=uploads+1
            offset,first,last=(offset or 0)*28,first or 1,last or #values
            for i=first,last do self.data[offset+i-first+1]=values[i] end
        end,
        Delete=function(self) self.deleted=true end,
    }
end
local expected,seen
gl.GetVAO = function()
    return {
        AttachVertexBuffer=function() end,
        AttachInstanceBuffer=function(self,buffer) self.buffer=buffer end,
        Delete=function() end,
        DrawArrays=function(self,_,_,_,count,offset)
            draws=draws+1
            for i=offset,offset+count-1 do
                local want=assert(expected[i], 'draw includes unallocated particle')
                assert(not seen[i], 'particle was drawn twice')
                seen[i]=true
                for j=1,28 do
                    assert(self.buffer.data[i*28+j]==want[j],
                        'VBO content changed before drawing: particle '..i..' field '..j)
                end
            end
        end,
    }
end
local batchEnv=setmetatable({gl=gl,GL={ARRAY_BUFFER=1,TRIANGLES=4},
    VFS={LoadFile=function() return '' end},Spring={Echo=function(message)
        assert(message=='LUPS: shared flat particle ring',message)
    end}}, {__index=_G})
local batchChunk=assert(loadfile(root..'/lups/headers/particle_batch.lua'))
local Batch=setfenv(batchChunk,batchEnv)()
local palette={{1,1,1,1}}
local function effect(id,count)
    local fx={texture='test',layer=0,gpuOnly=true,gpuParticles={},gpuPalette=palette,frame=0}
    for i=1,count do for j=1,28 do fx.gpuParticles[#fx.gpuParticles+1]=id*10000+i*100+j end end
    return fx
end
local function flush(batch,effects,retained)
    expected,seen={},{}
    local required={}
    local function remember(fx,entry,visible)
        for i=0,entry[3]-1 do
            local values={}
            for j=1,28 do values[j]=fx.gpuParticles[i*28+j] end
            expected[entry[2]+i]=values
            if visible then required[entry[2]+i]=true end
        end
    end
    for _,fx in ipairs(effects) do remember(fx,fx.gpuEntry,true) end
    for _,r in ipairs(retained or {}) do remember(r.fx,r.entry,false) end
    batch:flush(0)
    for i in pairs(required) do assert(seen[i], 'allocated particle was omitted from the draw: '..i) end
end
local batch=assert(Batch.new(false))
local a,b,c=effect(1,100),effect(2,100),effect(3,80)
batch:begin(1);batch:queue(a);batch:queue(b)
flush(batch,{a,b})
local firstUploads=uploads-1 -- exclude the fixed quad upload
assert(draws==1, 'contiguous entries were not drawn as one range')
Batch.release(a)
batch:begin(2);batch:queue(b);batch:queue(c)
flush(batch,{b,c})
assert(c.gpuEntry[2]==0 and b.gpuEntry[2]==100, 'ring wrap changed allocation order')
assert(draws==3, 'wrapped entries require two ordered draw ranges')
batch:begin(3);batch:queue(c)
-- b is retained in the ring but must become invisible before either draw.
for i=20,#b.gpuParticles,28 do b.gpuParticles[i]=-1 end
flush(batch,{b,c})
batch:begin(4);b.gpuReset=true;b.frame=2;batch:queue(b);batch:queue(c)
for i=20,#b.gpuParticles,28 do b.gpuParticles[i]=b.gpuEntry[7] end
flush(batch,{b,c})
assert(b.gpuParticles[4]==2, 'repeat birth was not updated')
local old=b.gpuGroup.instances
local d=effect(4,400)
batch:begin(5);batch:queue(b);batch:queue(c);batch:queue(d)
flush(batch,{b,c,d})
assert(old.deleted, 'growth retained the replaced VBO')
batch:delete()
print('PASS Lups batch: exact draw-time VBO values, ring wrap, hidden/repeated effects, growth; initial uploads='..firstUploads)

local function removedInterior(deadline,lastParticle)
    local ring=assert(Batch.new(false))
    local left,middle,right=effect(10,80),effect(11,80),effect(12,80)
    middle.frame,middle.dieGameFrame=1,deadline
    middle.gpuLastParticle=lastParticle
    for at=1,#middle.gpuParticles,28 do
        middle.gpuParticles[at+7],middle.gpuParticles[at+11]=deadline,0
    end
    ring:begin(1);ring:queue(left);ring:queue(middle);ring:queue(right)
    flush(ring,{left,middle,right})
    local oldEntry=middle.gpuEntry
    local before=uploads
    batchEnv.thisGameFrame=2
    Batch.release(middle)
    ring:begin(2);ring:queue(left);ring:queue(right)
    flush(ring,{left,right},{{fx=middle,entry=oldEntry}})
    local changed=uploads-before
    if deadline>2 or (deadline==2 and lastParticle==2) then
        assert(changed==1,'early removal did not upload its visibility change')
        for at=20,#middle.gpuParticles,28 do
            assert(middle.gpuParticles[at]==-1,'early removal left a visible particle')
        end
    elseif arg[2]=='skip-expired-uploads' or arg[2]=='flat-particle-ring' then
        assert(changed==0,'natural expiry uploaded already invisible particles')
    end
    ring:delete()
    batchEnv.thisGameFrame=nil
    return changed
end
local expiredUploads=removedInterior(1)
removedInterior(100)
removedInterior(2,2) -- An opaque endpoint at the exact deadline needs a mask.
removedInterior(2,1) -- An already-clipped endpoint needs no upload.
print('PASS Lups expiry: retained interior records, exact early-removal masks; natural expiry uploads='..expiredUploads)

-- Exercise the real attribute-writer entry point as well as late registration.
-- Local-space effects keep the ordinary table; world-space data can share the
-- backing ring, including its per-effect read/write view used by diagnostics.
local writer=assert(Batch.new(false))
local function prepared(gpu)
    return {texture='test',layer=0,count=2,frame=0,gpuOnly=gpu,colormap=palette,
        force={1,2,3},speedExp=1,sizeExp=1,rotExp=1,forceExp=1,ncolors=0}
end
local pooled,legacy=prepared(true),prepared(false)
batchEnv.thisGameFrame=7
Batch.prepare(pooled,writer);Batch.prepare(legacy,writer)
for _,fx in ipairs({pooled,legacy}) do
    for i=1,2 do Batch.pack(fx,20+i,i,1,2,3,4,5,6,7,8,9,10,0,0) end
end
assert(#pooled.gpuParticles==56 and #legacy.gpuParticles==56,'attribute view length changed')
if arg[2]=='flat-particle-ring' then
    assert(type(pooled.gpuParticles)=='userdata','world-space attributes were not written into the shared ring')
    assert(type(legacy.gpuParticles)=='table','local-space fallback lost its particle table')
end
writer:begin(7);writer:queue(pooled);flush(writer,{pooled})
for i=1,56 do
    if (i-4)%28~=0 then
        assert(pooled.gpuParticles[i]==legacy.gpuParticles[i],'shared writer changed particle field '..i)
    end
end
writer:delete();batchEnv.thisGameFrame=nil
print('PASS Lups attribute writer: pooled/local records and per-effect views')

local function preparedPalette(colors)
    local fx={colormap=colors,gpuOnly=false}
    Batch.prepare(fx)
    return fx.gpuPalette
end
local ca={{0.1,0.2,0.3,0.4},{0,0,0,0}}
local cb={{0.1,0.2,0.3,0.4},{0,0,0,0}}
local canonical=preparedPalette(ca)
assert(preparedPalette(cb)==canonical,'equal color values were not interned')
cb[1][1]=0.25
assert(preparedPalette(cb)~=canonical and canonical[1][1]==0.1,'changed input reused an old palette')
assert(preparedPalette({{'0.1','0.2','0.3','0.4'},{0,0,0,0}})==canonical,
    'numeric channel strings lost their existing palette identity')
local zero=0
assert(preparedPalette({{zero,0.6,0.7,0.8}})~=preparedPalette({{-zero,0.6,0.7,0.8}}),
    'signed zero changed palette identity')
print('PASS Lups palettes: exact values, changed inputs, numeric strings and signed zero')
if Batch.options then
    setfenv(assert(loadfile(root..'/lups/headers/general.lua')),batchEnv)()
    local colors={{0.2,0.3,0.4,0.5}}
    local defaults={colormap=colors,force={1,2,3},speed=2}
    local input={colormap=colors,force={[2]=9}}
    local mutable=Batch.options(input,defaults)
    assert(mutable.colormap~=colors and mutable.force~=input.force)
    assert(mutable.force[1]==1 and mutable.force[2]==9 and mutable.force[3]==3)
    mutable.colormap[1][1]=0.8
    assert(colors[1][1]==0.2,'mutable input lost its copy')
    input.immutableColormap=true
    local a,b=Batch.options(input,defaults),Batch.options(input,defaults)
    assert(a.colormap==colors and b.colormap==colors,'immutable palette was copied')
    assert(a.force~=b.force and a.force~=input.force,'mutable vectors were shared')
    Batch.prepare(a);Batch.prepare(b)
    assert(a.gpuPalette==b.gpuPalette,'immutable palette did not reuse its identity')
    print('PASS Lups options: immutable palettes shared, mutable palettes/vectors copied')
end


-- The performance harness must emit once per simulation step in UI Update,
-- including skipped UI polls, without introducing synced message callbacks.
local frame,burns,flames=29,{},{}
local perfMath=setmetatable({}, {__index=math})
local noop=function() end
local probeEnv=setmetatable({math=perfMath,Spring={
    GetModOptions=function() return {fire_perf=1,fire_perf_emitters=2} end,
    GetViewGeometry=function() return 1024,736,0,0 end,
    GetGameFrame=function() return frame end,
    WarpMouse=function(x,y)
        assert(x>20 and x<1004 and y>20 and y<716, 'probe cursor triggers viewport edge scrolling')
    end,SetCameraState=noop,SendCommands=noop,
},gl={},VFS={}}, {__index=_G})
local function record(list)
    list[#list+1]={probeEnv.thisGameFrame,perfMath.random()}
end
probeEnv.VFS.Include=function(path)
    if path:find('ParticleClasses') then
        return {Initialize=noop,ViewResize=noop}
    elseif path:find('lups_flame_jitter') then
        probeEnv.EmitFlame=function() record(flames) end
        probeEnv.gadget.GameFrame=noop
    elseif path:find('gfx_lups_units_on_fire') then
        probeEnv.onFireUnit=function() record(burns) end
        probeEnv.widget.Update=noop
    end
end
local fixtures=assert(arg[0]:match('(.*/)'))
setfenv(assert(loadfile(fixtures..'fire_probe_ui.lua')),probeEnv)()
probeEnv.Update();assert(#burns==0 and #flames==0)
frame=30;probeEnv.Update();probeEnv.Update()
assert(#burns==2 and #flames==2, 'same-frame UI polls repeated an emission')
frame=45;probeEnv.Update()
assert(#burns==32 and #flames==4, 'skipped UI polls changed the fixed emission schedule')
for i,row in ipairs(burns) do
    local n=29+math.ceil(i/2)
    assert(row[1]==n and row[2]==((n*20*251+1)%65521)/65521, 'burn frame or seed changed')
end
for i,row in ipairs(flames) do
    local n=i<=2 and 30 or 45
    assert(row[1]==n and row[2]==((n*10*251+1)%65521)/65521, 'flame frame or seed changed')
end
assert(not pcall(probeEnv.FireProbe,'GRAVITAS_FX|burn'), 'unexpected performance transport was accepted')
local rulesEnv=setmetatable({Spring={GetModOptions=probeEnv.Spring.GetModOptions,Echo=noop},
    SendToUnsynced=function() error('performance fixture sent a synced emission') end}, {__index=_G})
setfenv(assert(loadfile(fixtures..'fire_probe_rules.lua')),rulesEnv)()
rulesEnv.GameFrame(30);rulesEnv.GameFrame(45)
print('PASS fire harness: local UI emissions, exact skipped-poll frames/seeds, no synced emissions')
