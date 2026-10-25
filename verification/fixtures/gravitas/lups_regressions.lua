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
