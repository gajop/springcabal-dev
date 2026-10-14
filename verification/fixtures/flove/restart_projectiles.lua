-- An in-flight shot must not bloom or upgrade a tree in the following round.
function gadget:GetInfo() return {name='Flove restart projectile regression',layer=100000,enabled=true} end
if gadgetHandler:IsSyncedCode() then
    local previousRound, target, resetFrame
    local function status()
        for _,id in ipairs(Spring.GetTeamUnits(1)) do
            local round=Spring.GetUnitRulesParam(id,'round')
            if round and Spring.GetUnitDefID(id)==UnitDefNames.spire.id then return round,id end
        end
    end
    local function shoot(owner,ttl)
        for _,name in ipairs({'flowershot','upgradeshot'}) do
            local height=(ttl==10 and name=='upgradeshot') and 1 or 500
            assert(Spring.SpawnProjectile(WeaponDefNames[name].id,{pos={target[1],target[2]+height,target[3]},['end']=target,speed={0,0,0},owner=owner,ttl=ttl,gravity=0}))
        end
    end
    local function counts()
        local flowers,progress=0,0
        for _,id in ipairs(Spring.GetAllUnits()) do
            local def=UnitDefs[Spring.GetUnitDefID(id)]
            if def.name:match('^flower[1-6]$') then flowers=flowers+1 end
            if def.customParams.tree then progress=progress+(Spring.GetUnitRulesParam(id,'upgradeProgress') or 0) end
        end
        return flowers,progress
    end
    function gadget:GameFrame(frame)
        if frame==20 then
            local owner; previousRound,owner=status()
            for _,id in ipairs(Spring.GetTeamUnits(1)) do
                if Spring.GetUnitDefID(id)==UnitDefNames.treelevel1.id then target={Spring.GetUnitPosition(id)}; break end
            end
            assert(target and owner); shoot(owner,80)
        end
        local round,owner=status()
        if previousRound and round and round>previousRound then resetFrame=resetFrame or frame end
        if frame==115 then
            local flowers,progress=counts()
            assert(resetFrame and flowers==0 and progress==0,'old-round impacts leaked: flowers='..flowers..', upgrade='..progress)
            Spring.Echo('FLOVE OLD ROUND PROJECTILES IGNORED'); shoot(owner,10)
        elseif frame==145 then
            local flowers,progress=counts()
            assert(flowers>0 and progress==1,'new-round impacts stopped: flowers='..flowers..', upgrade='..progress)
            Spring.Echo('FLOVE CURRENT ROUND PROJECTILES WORK'); Spring.SetGameRulesParam('restart_projectiles_done',1)
        end
    end
else
    local sent=false
    function gadget:Update()
        if not sent and Spring.GetGameFrame()>=40 then sent=true; Spring.SendLuaRulesMsg('restart|1') end
        if Spring.GetGameRulesParam('restart_projectiles_done')==1 then Spring.SendCommands('quitforce') end
    end
end
