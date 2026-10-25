-- Isolated visual fixture. Identical events drive the real Lua particle
-- classes and the Rust renderer, with no gameplay or moving camera.
local options = Spring.GetModOptions() or {}
local perf = tonumber(options.fire_perf) == 1
local emitters = tonumber(options.fire_perf_emitters) or 1
if SendToUnsynced then
    function GameFrame(n)
        if perf then
            if n == 1 then Spring.Echo("[FirePerf] emitters=" .. emitters) end
            if n >= 30 then
                for i = 1, emitters do
                    -- Same burn + flame schedule as the existing parity probe.
                    SendToUnsynced("GRAVITAS_FX|burn|4400|144.25|531|25|1|0.5|-0.25")
                    if n % 15 == 0 then
                        SendToUnsynced("GRAVITAS_FX|flame|4288|144.25|531|500")
                    end
                end
            end
            return
        end
        if n == 1 then
            SendToUnsynced("GRAVITAS_SHOT|look|4288|600|650")
        end
        if n >= 30 and n <= 150 and n % 30 == 0 then
            SendToUnsynced("GRAVITAS_SHOT|probe|" .. ({90,105,120,150,180})[n/30])
        end
        if n >= 45 and n <= 165 and n % 30 == 15 then
            SendToUnsynced("GRAVITAS_SHOT|shot|" .. n)
        end
        if n == 190 then SendToUnsynced("GRAVITAS_SHOT|done") end
    end
else
    -- This is a raw LuaRules entry point, without the gadget loader that
    -- invokes gadget:Initialize. Enable stepping during chunk loading.
    if perf then Spring.SetVideoCapturingMode(true) end
    function Update()
        if perf then
            Spring.SetCameraState({name="ta", mode=1, px=4288, py=0, pz=600,
                height=650, angle=0.464, fov=45}, 0)
        end
    end
    function RecvFromSynced(message)
        if Script.LuaUI("FireProbe") then Script.LuaUI.FireProbe(message) end
    end
end
