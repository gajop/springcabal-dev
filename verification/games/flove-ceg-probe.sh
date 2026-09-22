#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
vf_workspace "flove-ceg-${1:-current}"
staged=$(vf_stage_game "$GAMES_DIR/Flove.sdd")
cp "$FIXTURES_DIR/flove/ceg_probe.lua" "$staged/LuaUI/Widgets/ceg_probe.lua"
cp "$FIXTURES_DIR/flove/draw_callback_probe.lua" "$staged/LuaRules/Gadgets/draw_callback_probe.lua"
vf_link_map "$MAPS_DIR/LD34-map.sdd" 'The Grove 0.3.sdd'
vf_start_file "$FIXTURES_DIR/flove/start.txt" 1 1
sed -i 's/gametype=Flove WASM 0.1.0-wasm;/gametype=Flove $VERSION;/' "$VF_START_FILE"
if [[ ${PROBE_FORCE_LEGACY:-0} == 1 ]]; then
    sed -i '/test_mode=1;/a ceg_force_legacy=1;' "$VF_START_FILE"
fi
vf_config "$FIXTURES_DIR/flove/spring.conf"
printf '\nXResolutionWindowed = 1280\nYResolutionWindowed = 720\nWindowBorderless = 0\nAllowDeferredMapRendering = 1\nAllowDeferredModelRendering = 1\n' >> "$VF_CONFIG_FILE"
if [[ ${PROBE_GPU:-0} == 1 ]]; then
    timeout 90 "$(vf_engine_bin visual)" --window --write-dir "$VF_WRITE_DIR" --isolation --isolation-dir "$VF_ISOLATION" --config "$VF_CONFIG_FILE" "$VF_START_FILE" > "$VF_WRITE_DIR/stdout.txt" 2>&1 || VF_ENGINE_STATUS=$?
else
    vf_run_visual 90
fi
vf_save_logs
vf_require '\[CEG-Probe\] COMPLETE' 'Probe did not complete; inspect its log.'
vf_require_screenshots 4
vf_collect_screenshots
printf 'Staged game and logs retained at %s\n' "$VF_TEST_ROOT"
