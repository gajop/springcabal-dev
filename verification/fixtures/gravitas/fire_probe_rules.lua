-- Isolated visual fixture. Identical events drive the real Lua particle
-- classes and the Rust renderer, with no gameplay or moving camera.
if SendToUnsynced then
    function GameFrame(n)
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
    function RecvFromSynced(message)
        if Script.LuaUI("FireProbe") then Script.LuaUI.FireProbe(message) end
    end
end
