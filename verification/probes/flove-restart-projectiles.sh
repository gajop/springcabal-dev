#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
vf_build "$GAMES_DIR/Flove-wasm.sdd/wasm-src" ""
vf_workspace flove-restart-projectiles stable
staged=$(vf_stage_game "$GAMES_DIR/Flove-wasm.sdd")
vf_install_modules "$staged" flove_rules_wasm:LuaRules/wasm/flove-rules.wasm flove_ui_wasm:LuaUI/wasm/flove-ui.wasm
cp "$FIXTURES_DIR/flove/restart_projectiles.lua" "$staged/LuaRules/Gadgets/zz_restart_projectiles.lua"
vf_link_map "$MAPS_DIR/LD34-map.sdd" 'The Grove 0.3.sdd'
vf_start_file "$(vf_launch_script flove)"
vf_start_set FixedRNGSeed 1
vf_config
vf_graphics flove
vf_run_visual 25
vf_save_logs
vf_require_clean_exit
vf_require 'FLOVE OLD ROUND PROJECTILES IGNORED'
vf_require 'FLOVE CURRENT ROUND PROJECTILES WORK'
vf_forbid_runtime_failures
vf_summary
