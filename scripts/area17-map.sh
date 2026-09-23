#!/usr/bin/env bash
# Build the patched Area 17 map (the original Area17.sd7 plus the dual-fog
# gadget from patches/area17-map/) and print its path.  Rebuilt only when an
# input is newer.
#
#   scripts/area17-map.sh          build/maps/Area17.sd7  (what the release ships)
#   scripts/area17-map.sh --dir    build/maps/Area17.sdd  (same content, extracted:
#                                  loads ~4s faster, used for local runs and tests)
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_map="$project_root/spring-linux/maps/Area17.sd7"
patch_dir="$project_root/patches/area17-map"
archive="$project_root/build/maps/Area17.sd7"
extracted="$project_root/build/maps/Area17.sdd"

[[ -f $source_map ]] || { echo "missing $source_map (see content.tsv)" >&2; exit 1; }

stale() {
    [[ ! -e $1 || $source_map -nt $1 ]] || [[ -n $(find "$patch_dir" -type f -newer "$1" -print -quit) ]]
}

if stale "$archive"; then
    mkdir -p "$(dirname "$archive")"
    cp -- "$source_map" "$archive.tmp"
    (cd "$patch_dir" && 7z u -bso0 -bsp0 "$archive.tmp" .)
    mv -- "$archive.tmp" "$archive"
fi

if [[ ${1:-} == --dir ]]; then
    if stale "$extracted/mapinfo.lua"; then
        rm -rf -- "$extracted.tmp"
        mkdir -p "$extracted.tmp"
        (cd "$extracted.tmp" && 7z x -bso0 -bsp0 "$archive")
        rm -rf -- "$extracted"
        mv -- "$extracted.tmp" "$extracted"
        touch "$extracted/mapinfo.lua"
    fi
    printf '%s\n' "$extracted"
else
    printf '%s\n' "$archive"
fi
