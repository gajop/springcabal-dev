#!/usr/bin/env bash
# Fire renderer parity, step 1: render 5 fixed fire frames with the Lua or
# the Rust renderer (arg: lua|wasm).  See gravitas-fire.md.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
variant=${1:-wasm}
[[ $variant == lua || $variant == wasm ]] || vf_die 'expected lua or wasm'
source_game="$GAMES_DIR/Gravitas.sdd"
wasm_game="$GAMES_DIR/Gravitas-wasm.sdd"
if [[ $variant == wasm ]]; then
    (cd "$wasm_game/wasm-src" && cargo build -p gravitas-ui-wasm --features fire-probe --release \
        --target wasm32-unknown-unknown --target-dir "$BUILD_CACHE/gravitas-fire-probe")
fi
vf_workspace "gravitas-fire-$variant" stable
staged=$(vf_stage_game "$source_game")
cp "$FIXTURES_DIR/gravitas/fire_probe_rules.lua" "$staged/LuaRules/main.lua"
cp "$FIXTURES_DIR/gravitas/fire_probe_rules.lua" "$staged/LuaRules/draw.lua"
if [[ $variant == lua ]]; then
    cp "$FIXTURES_DIR/gravitas/fire_probe_ui.lua" "$staged/LuaUI/main.lua"
else
    mv "$staged/LuaUI" "$staged/LuaUI-reference"
    cp -a "$wasm_game/LuaUI" "$staged/LuaUI"
    cp "$BUILD_CACHE/gravitas-fire-probe/wasm32-unknown-unknown/release/gravitas_ui_wasm.wasm" "$staged/LuaUI/wasm/gravitas-ui.wasm"
fi
vf_link_map "$MAPS_DIR/Gravitas-map.sdd"
vf_start_file "$(vf_launch_script gravitas)"
vf_start_set GameType Gravitas
vf_config "$VISUAL_CONFIG"
vf_config_set UseFontConfigLib 0
vf_config_set GroundDetail 200
vf_config_set MaxMapDetail 5
vf_config_set LODScale 2.0
vf_run_visual 35
vf_save_logs
mapfile -t captures < <(vf_screenshots)
[[ ${#captures[@]} == 5 ]] || vf_die "expected five fire frames; got ${#captures[@]}"
vf_forbid 'Error in (Update|DrawWorld)|LuaUI.*Error|shader.*error'
printf '%s\n' "${captures[@]}"
