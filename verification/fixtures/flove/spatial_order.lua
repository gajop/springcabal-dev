function gadget:GetInfo() return {name="Quad order diagnostic",layer=1000004,enabled=true} end
if not gadgetHandler:IsSyncedCode() then return false end
function gadget:GameFramePost(frame)
 if frame<60 or frame>66 then return end
 local all=Spring.GetUnitsInRectangle(0,0,Game.mapSizeX,Game.mapSizeZ,-1)
 Spring.Echo("[QuadOrder] frame="..frame.." all="..table.concat(all,","))
 local x,y,z=Spring.GetUnitPosition(23952)
 if x then
  local near=Spring.GetUnitsInCylinder(x,z,500,-1)
  Spring.Echo("[QuadOrder] frame="..frame.." near="..table.concat(near,","))
 end
end
