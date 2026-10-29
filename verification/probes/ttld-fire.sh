#!/usr/bin/env bash
# Reuse the existing fixed-age fire capture method with TTLD's actual curves.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
variant=${1:-wasm}
[[ $variant == lua || $variant == wasm ]] || vf_die 'expected lua or wasm'
source_game="$GAMES_DIR/ToTheLastDrop.sdd"
wasm_game="$GAMES_DIR/ToTheLastDrop-wasm.sdd"
if [[ $variant == wasm ]]; then
    fire_module=${VF_EFFECTS_MODULE:?frozen TTLD fire-probe module required}
    [[ -f $fire_module ]] || vf_die "missing TTLD fire probe: $fire_module"
fi
vf_workspace "ttld-fire-$variant" stable
rm -f -- "$VF_WRITE_DIR"/cache/ArchiveCache*.lua
staged=$(vf_stage_game "$source_game")
printf 'function GameFrame() end\n' > "$staged/LuaRules/main.lua"
printf 'Spring.SetVideoCapturingMode(true)\nSpring.SendCommands("mapborder 0")\n' > "$staged/LuaRules/draw.lua"
if [[ $variant == lua ]]; then
    cp "$FIXTURES_DIR/ttld/fire_probe_ui.lua" "$staged/LuaUI/main.lua"
else
    mv "$staged/LuaUI" "$staged/LuaUI-reference"
    cp -a "$wasm_game/LuaUI" "$staged/LuaUI"
    cp "$fire_module" "$staged/LuaUI/wasm/ttld-ui.wasm"
fi
vf_link_map "$MAPS_DIR/Gravitas-map.sdd"
vf_start_file "$(vf_launch_script gravitas)"
vf_start_set GameType 'To the last Drop $VERSION'
vf_start_set FixedRNGSeed 424242
vf_start_set FixedUnsyncedRNGSeed 424242
vf_config "$VISUAL_CONFIG"
vf_config_set UseFontConfigLib 0
vf_config_set GroundDetail 200
vf_config_set MaxMapDetail 5
vf_config_set LODScale 2.0
vf_run_visual 35
vf_save_logs
vf_require_clean_exit
vf_forbid_runtime_failures 'TTLD fire parity capture'
mapfile -t captures < <(vf_screenshots)
[[ ${#captures[@]} == 5 ]] || vf_die "expected five TTLD fire frames; got ${#captures[@]}"
printf '%s\n' "${captures[@]}"
