#!/usr/bin/env bash
# Set up a SpringCabal development checkout.
#
#   ./setup.sh                      clone the game/map repos listed in content.tsv
#   ./setup.sh --engine-tag TAG     also download that Linux engine release into
#                                   engine/TAG and point engine/current at it
#
# Existing checkouts are never touched.  See README.md for the full workflow.
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
content_root="$project_root/spring-linux"
engine_repo="gajop/spring-rust"
engine_tag=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --engine-tag) engine_tag="${2:?}"; shift 2 ;;
        -h|--help) sed -n 2,9p "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ -n "$engine_tag" ]]; then
    engine_dir="$project_root/engine/$engine_tag"
    if [[ ! -x "$engine_dir/spring" ]]; then
        asset="recoil_${engine_tag}_amd64-linux.7z"
        echo "==> Downloading $asset from $engine_repo"
        tmp="$(mktemp -d)"
        gh release download "$engine_tag" -R "$engine_repo" -p "$asset" -D "$tmp"
        mkdir -p "$engine_dir"
        7z x -bso0 -bsp0 -o"$engine_dir" "$tmp/$asset"
        rm -rf -- "$tmp"
    fi
    ln -sfn "$engine_tag" "$project_root/engine/current"
    echo "==> engine/current -> $engine_tag"
fi

mkdir -p "$content_root/games" "$content_root/maps" "$content_root/projects"

missing=()
while IFS=$'\t' read -r kind path source branch ship; do
    dst="$content_root/${kind}s/$path"
    [[ -e "$dst" ]] && continue
    case "$source" in
        local|download)
            missing+=("$kind/$path ($source)")
            ;;
        *)
            echo "==> Cloning $kind/$path ($branch)"
            if ! git clone --recursive --branch "$branch" "$source" "$dst"; then
                missing+=("$kind/$path (branch $branch not available from $source)")
            fi
            ;;
    esac
done < <(grep -v -E '^\s*(#|$)' "$project_root/content.tsv")

if (( ${#missing[@]} )); then
    echo ""
    echo "Not set up automatically; copy these into spring-linux/ by hand:"
    printf '  %s\n' "${missing[@]}"
fi
