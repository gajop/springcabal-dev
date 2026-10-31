-- Controlled input for the real production fire widgets and LUPS handler.
-- No particle replacement or visibility override is installed by this fixture.
function gadget:GetInfo()
 return {name="Production fire control",desc="Deterministic near/far burning houses",author="SpringCabal",license="GPL v2 or later",layer=1000003,enabled=true}
end
if not gadgetHandler:IsSyncedCode() then return end
function gadget:GameFramePost(frame)
 if frame ~= 120 then return end
 local houses,hero={},nil
 for _,id in ipairs(Spring.GetAllUnits()) do
  local name=UnitDefs[Spring.GetUnitDefID(id)].name
  if name=="bloodmage" and not hero then hero=id end
  if name=="house" then houses[#houses+1]=id end
 end
 assert(hero,"production fire control requires a bloodmage")
 local x,_,z=Spring.GetUnitPosition(hero)
 local distance={}
 for _,id in ipairs(houses) do
  local hx,_,hz=Spring.GetUnitPosition(id)
  distance[id]=(hx-x)*(hx-x)+(hz-z)*(hz-z)
 end
 table.sort(houses,function(a,b)
  if distance[a]==distance[b] then return a<b end
  return distance[a]<distance[b]
 end)
 local half=math.min(64,math.floor(#houses/2))
 assert(half>0,"production fire control requires houses")
 local chosen={}
 for i=1,half do chosen[#chosen+1]=houses[i];chosen[#chosen+1]=houses[#houses-i+1] end
 table.sort(chosen)
 for _,id in ipairs(chosen) do Spring.SetUnitRulesParam(id,"on_fire",1,{public=true}) end
 Spring.SetGameRulesParam("perf_fire_control_count",#chosen,{public=true})
 Spring.Echo("[PerfFireProduction] burning="..#chosen.." near="..half.." far="..half.." ids="..table.concat(chosen,","))
end
