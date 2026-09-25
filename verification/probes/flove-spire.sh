#!/usr/bin/env bash
# Spire world-position probe on the Flove port, on the real GPU.
# SPIRE_PROBE_MODULE_DIR=dir swaps in modules built elsewhere;
# SPIRE_PROBE_PRESENTATION=1 adds the presentation probe; SPIRE_PROBE_MANUAL=1
# leaves the camera to you; SPIRE_PROBE_SECONDS sets the run length.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
vf_workspace "flove-spire-${1:-probe}"
staged=$(vf_stage_game "$GAMES_DIR/Flove-wasm.sdd")
if [[ -n ${SPIRE_PROBE_MODULE_DIR:-} ]]; then
    cp "$SPIRE_PROBE_MODULE_DIR/flove_rules_wasm.wasm" "$staged/LuaRules/wasm/flove-rules.wasm"
    cp "$SPIRE_PROBE_MODULE_DIR/flove_rules_unsynced_wasm.wasm" "$staged/LuaRules/wasm/flove-rules-unsynced.wasm"
    cp "$SPIRE_PROBE_MODULE_DIR/flove_ui_wasm.wasm" "$staged/LuaUI/wasm/flove-ui.wasm"
fi
cp "$FIXTURES_DIR/flove/spire_world_probe.lua" "$staged/LuaRules/Gadgets/spire_world_probe.lua"
if [[ ${SPIRE_PROBE_PRESENTATION:-0} == 1 ]]; then
    cp "$FIXTURES_DIR/flove/presentation_probe.lua" "$staged/LuaRules/Gadgets/presentation_probe.lua"
fi
vf_link_map "$MAPS_DIR/LD34-map.sdd" 'The Grove 0.3.sdd'
vf_start_file "$(vf_launch_script flove)"
[[ ${SPIRE_PROBE_MANUAL:-0} == 1 ]] && vf_modoption spire_probe_manual 1
vf_config "$FIXTURES_DIR/flove/spring.conf"
printf '\nXResolutionWindowed = 1280\nYResolutionWindowed = 720\nWindowBorderless = 0\nWindowState = 0\n' >> "$VF_CONFIG_FILE"
printf 'Probe workspace: %s\n' "$VF_TEST_ROOT"
timeout "${SPIRE_PROBE_SECONDS:-30}" "$(vf_engine_bin visual)" --window --write-dir "$VF_WRITE_DIR" --isolation --isolation-dir "$VF_ISOLATION" --config "$VF_CONFIG_FILE" "$VF_START_FILE" > "$VF_WRITE_DIR/stdout.txt" 2>&1 || VF_ENGINE_STATUS=$?
vf_save_logs
vf_collect_screenshots
grep -F '[Spire-Probe]' "$VF_WRITE_DIR/infolog.txt" || vf_die 'the spire probe logged nothing'
