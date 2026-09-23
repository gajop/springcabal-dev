#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
out="$VERIFICATION_ROOT/out/gravitas-fire-comparison"
mkdir -p "$out"
mapfile -t lua < <(find "$VERIFICATION_ROOT/out/gravitas-fire-lua/run/write/screenshots" -name 'screen_*.png' | sort)
mapfile -t wasm < <(find "$VERIFICATION_ROOT/out/gravitas-fire-wasm/run/write/screenshots" -name 'screen_*.png' | sort)
[[ ${#lua[@]} == 5 && ${#wasm[@]} == 5 ]] || vf_die 'run both fire fixtures first'
frames=(90 105 120 150 180)
for i in "${!frames[@]}"; do
    frame=${frames[$i]}
    # Include the entire flame, heat footprint and nearby textured floor.
    # Exclude unrelated HUDs, minimap and map-edge drawing.
    convert "${lua[$i]}" -crop 420x300+480+80 +repage "$out/lua-$frame.png"
    convert "${wasm[$i]}" -crop 420x300+480+80 +repage "$out/wasm-$frame.png"
    metric=$(vf_rmse "$out/lua-$frame.png" "$out/wasm-$frame.png" "$out/diff-$frame.png")
    printf 'frame %s: fire-region RMSE %.5f%%\n' "$frame" "$(awk -v value="$metric" 'BEGIN { print value * 100 }')"
    vf_within "$metric" 0.1 || vf_die "fire mismatch at frame $frame"
    convert "$out/lua-$frame.png" "$out/wasm-$frame.png" +append "$out/pair-$frame.png"
done
