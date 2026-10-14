#!/usr/bin/env bash
# Isolate the Lua outlines and compare revised models with upstream models.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
mode=${1:-current}
[[ $mode == current || $mode == upstream-models ]] || vf_die 'expected current or upstream-models'
vf_workspace "flove-presentation-$mode" stable
staged=$(vf_stage_game "$GAMES_DIR/Flove.sdd")
if [[ $mode == upstream-models ]]; then
    while IFS= read -r path; do
        git -C "$GAMES_DIR/Flove.sdd" show "origin/master:$path" > "$staged/$path"
    done < <(git -C "$GAMES_DIR/Flove.sdd" diff --name-only origin/master HEAD -- 'Objects3d/*.dae')
fi
for file in "$staged"/LuaRules/Gadgets/*.lua; do
    case $(basename "$file") in unit_script.lua|api_custom_unit_shaders.lua|unit_centeroffset.lua) ;; *) rm "$file" ;; esac
done
for file in "$staged"/LuaUI/Widgets/*.lua; do
    case $(basename "$file") in gfx_outline.lua|ui_hide_default_layout.lua|start_force.lua) ;; *) rm "$file" ;; esac
done
rm -f "$staged"/LuaUI/Config/*_order.lua
cat > "$staged/LuaRules/Gadgets/zz_model_review.lua" <<'LUA'
function gadget:GetInfo() return {name='Flove model review',layer=100000,enabled=true} end
if not gadgetHandler:IsSyncedCode() then return false end
local names={'normalmushroom','smallmushroom','bigmushroom','bombmushroom','mushroomcluster','poisonmushroom','kingshroom','treelevel1','treelevel2','treelevel3','grass1','grass2','grass5'}
function gadget:GameFrame(frame)
    if frame==3 then
        for i,name in ipairs(names) do
            local x,z=4100+((i-1)%5)*300,5900+math.floor((i-1)/5)*350
            local id=assert(Spring.CreateUnit(name,x,Spring.GetGroundHeight(x,z),z,0,1))
            Spring.SetUnitRulesParam(id,'review',i,{public=true})
            Spring.SetUnitRulesParam(id,'createdFrame',0,{public=true})
        end
    elseif frame==20 then
        for _,id in ipairs(Spring.GetAllUnits()) do
            local def=UnitDefs[Spring.GetUnitDefID(id)]
            local model=def.model
            Spring.Echo(string.format('[ModelReview] %s height=%.3f bounds=(%.3f,%.3f,%.3f)-(%.3f,%.3f,%.3f)',def.name,(model.maxy or 0)-(model.miny or 0),model.minx or 0,model.miny or 0,model.minz or 0,model.maxx or 0,model.maxy or 0,model.maxz or 0))
            for name,piece in pairs(Spring.GetUnitPieceMap(id)) do
                local x,y,z=Spring.GetUnitPiecePosition(id,piece)
                Spring.Echo(string.format('[ModelPiece] %s %s %.3f %.3f %.3f',def.name,name,x,y,z))
            end
        end
    end
end
LUA
cat > "$staged/LuaUI/Widgets/zz_outline_review.lua" <<'LUA'
function widget:GetInfo() return {name='Flove outline review',layer=100000,enabled=true} end
local pending, shots=0,0
local labels={'level1_hover','level2_hover','level3_hover','no_hover'}
function widget:GameFrame(frame)
    if frame==25 then
        Spring.SetCameraState({name='spring',mode=2,px=4700,py=Spring.GetGroundHeight(4700,6250),pz=6250,dist=1800,rx=2.38,ry=0,rz=0,fov=45},0)
    elseif frame==50 or frame==80 or frame==110 or frame==140 then
        local level=({[50]=1,[80]=2,[110]=3,[140]=0})[frame]
        if level==0 then Spring.WarpMouse(48,48)
        else
            for _,id in ipairs(Spring.GetAllUnits()) do
                if Spring.GetUnitDefID(id)==UnitDefNames['treelevel'..level].id then
                    local x,y,z=Spring.GetUnitPosition(id)
                    local sx,sy=Spring.WorldToScreenCoords(x,y+Spring.GetUnitHeight(id)*.6,z)
                    Spring.WarpMouse(sx,sy)
                    break
                end
            end
        end
        pending=level==0 and 4 or level
    end
end
function widget:DrawScreenPost()
    if pending==0 then return end
    -- Give WarpMouse's event a drawn frame to reach the engine state.
    local frame=Spring.GetGameFrame()
    if frame~=55 and frame~=85 and frame~=115 and frame~=145 then return end
    local mx,my=Spring.GetMouseState()
    local hit,id=Spring.TraceScreenRay(mx,my)
    local def=id and hit=='unit' and Spring.GetUnitDefID(id)
    Spring.Echo('[OutlineReview] '..labels[pending]..' hit='..tostring(def and UnitDefs[def].name or hit))
    if pending<4 and tonumber(Spring.GetModOptions().review_old_models)~=1 then
        assert(def==UnitDefNames['treelevel'..pending].id,'probe cursor missed tree')
    end
    local w,h=Spring.GetViewGeometry()
    assert(gl.SaveImage(0,0,w,h,'screenshots/screen_'..labels[pending]..'.png'))
    shots=shots+1; pending=0
    if shots==4 then Spring.Echo('FLOVE PRESENTATION REVIEW PASSED'); Spring.SendCommands('quitforce') end
end
LUA
vf_link_map "$MAPS_DIR/LD34-map.sdd" 'The Grove 0.3.sdd'
vf_start_file "$(vf_launch_script flove lua)"
vf_start_set FixedRNGSeed 1
[[ $mode != upstream-models ]] || vf_modoption review_old_models 1
vf_config
vf_config_set XResolutionWindowed 1024
vf_config_set YResolutionWindowed 720
vf_graphics flove
VF_RENDERER=${VF_RENDERER:-gpu}
vf_run_visual 25 1024x720x24
vf_save_logs
vf_require_clean_exit
vf_require 'FLOVE PRESENTATION REVIEW PASSED'
vf_forbid_runtime_failures
vf_require_screenshots 4
vf_summary
vf_collect_screenshots
