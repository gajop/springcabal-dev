#!/usr/bin/env bash
# Build the patched Area 17 map (the original Area17.sd7 plus the dual-fog
# gadget from patches/area17-map/) and print its path.  Rebuilt only when an
# input is newer.  Used by run-wasm.sh, verification and release/package.sh.
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_map="$project_root/spring-linux/maps/Area17.sd7"
patch_dir="$project_root/patches/area17-map"
output="$project_root/build/maps/Area17.sd7"

[[ -f $source_map ]] || { echo "missing $source_map (see content.tsv)" >&2; exit 1; }

if [[ ! -f $output || $source_map -nt $output ]] ||
    [[ -n $(find "$patch_dir" -type f -newer "$output" -print -quit) ]]; then
    mkdir -p "$(dirname "$output")"
    cp -- "$source_map" "$output.tmp"
    (cd "$patch_dir" && 7z u -bso0 -bsp0 "$output.tmp" .)
    mv -- "$output.tmp" "$output"
fi
printf '%s\n' "$output"
