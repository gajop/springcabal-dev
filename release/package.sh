#!/usr/bin/env bash
# Build SpringCabal release bundles (engine + WASM menu + games + maps).
#
# Everything is packed from the local checkouts under spring-linux/, so this
# works before the game repositories are published.  See RELEASING.md.
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
content_root="$project_root/spring-linux"
out_root="$project_root/release/out"
cache_root="$project_root/release/cache"

engine_repo="gajop/spring-rust"
engine_tag=""
engine_dirs=()
platforms=(linux windows)
version="$(date +%Y.%m.%d)"
build_wasm=0
make_archives=1

usage() {
    cat <<EOF
Usage: release/package.sh --engine-tag TAG [options]

  --engine-tag TAG         engine release on $engine_repo to bundle (e.g. 2026.09.23)
  --engine-dir PLAT=DIR    use a local engine install instead of downloading,
                           e.g. linux=../spring-bar/build-amd64-linux/install
  --platform linux|windows|all   (default: all)
  --version VER            bundle version (default: today, $version)
  --build                  rebuild all WASM modules first (just build-all)
  --no-archive             stop after assembling release/out/<bundle>/
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --engine-tag) engine_tag="${2:?}"; shift 2 ;;
        --engine-dir) engine_dirs+=("${2:?}"); shift 2 ;;
        --platform)
            case "${2:-}" in
                all) platforms=(linux windows) ;;
                linux|windows) platforms=("$2") ;;
                *) usage ;;
            esac
            shift 2 ;;
        --version) version="${2:?}"; shift 2 ;;
        --build) build_wasm=1; shift ;;
        --no-archive) make_archives=0; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1" >&2; usage ;;
    esac
done

log() { echo "==> $*"; }
die() { echo "error: $*" >&2; exit 1; }

for tool in 7z zip rsync tar strings cargo python3; do
    command -v "$tool" >/dev/null || die "missing tool: $tool"
done

local_engine_dir() {
    local entry
    for entry in "${engine_dirs[@]}"; do
        if [[ "${entry%%=*}" == "$1" ]]; then
            echo "${entry#*=}"
            return
        fi
    done
}

for plat in "${platforms[@]}"; do
    if [[ -z "$(local_engine_dir "$plat")" && -z "$engine_tag" ]]; then
        die "no engine for $plat: pass --engine-tag or --engine-dir $plat=DIR"
    fi
done

# Manifest rows: kind path source branch ship
manifest() {
    grep -v -E '^\s*(#|$)' "$project_root/content.tsv"
}

# ---------------------------------------------------------------------------
# WASM modules
# ---------------------------------------------------------------------------
if (( build_wasm )); then
    log "Building WASM modules"
    (cd "$project_root" && just build-all)
fi

# Strings that only exist in modules built with a test feature (e2e,
# headless-integration, *-probe).  A test build left in a game folder must
# never ship.  Flove's e2e build logs "FLOVE E2E BUILD" (its test commands
# compile to no strings).
test_markers='ASSERTION (PASSED|FAILED)|INTEGRATION TESTS? PASSED|VISUAL E2E|E2E case|E2E summary|GRAVITAS_SHOT|UnitScriptProbe|TTLD E2E|Visual-Test|fire-probe|FLOVE E2E BUILD'

check_wasm_modules() {
    local dir="$1" module hits
    local modules=()
    local found
    found="$(find "$dir/LuaRules/wasm" "$dir/LuaUI/wasm" -maxdepth 1 -name '*.wasm' 2>/dev/null | head -1)"
    [[ -n "$found" ]] || die "$(basename "$dir") has no built .wasm modules (run with --build)"
    for module in "$dir"/LuaRules/wasm/*.wasm "$dir"/LuaUI/wasm/*.wasm; do
        [[ -f $module ]] || continue
        modules+=("$module")
        hits="$(strings "$module" | grep -oE "$test_markers" | sort -u | tr '\n' ' ' || true)"
        [[ -z $hits ]] || die "${module#"$content_root"/} is a test build (contains: $hits); rebuild with 'just copy' in its wasm-src"
    done
    python3 "$project_root/release/wasm-info.py" "$dir/wasm-src" "${modules[@]}" >> "$build_info"
}

# ---------------------------------------------------------------------------
# Content: games -> .sdz, maps -> .sd7 (shared by every platform)
# ---------------------------------------------------------------------------
content_dir="$out_root/content-$version"
rm -rf -- "$content_dir"
mkdir -p "$content_dir/games" "$content_dir/maps" "$content_dir/projects"

# Always stripped, on top of each archive's own springignore.txt.
base_excludes=(
    --exclude=/.git --exclude=/.gitmodules --exclude=/.gitignore
    --exclude=/.vscode --exclude=/.idea
    --exclude=/wasm-src --exclude=/wasm-test
    --exclude=/verification --exclude=/springignore.txt
    --exclude=target/ --exclude='*.cwasm' --exclude='*.log'
)

stage_tree() {
    local src="$1" dst="$2"
    local args=("${base_excludes[@]}")
    local ignore_file=""
    if [[ -f "$src/springignore.txt" ]]; then
        ignore_file="$(mktemp)"
        grep -v -E '^\s*(#|$)' "$src/springignore.txt" > "$ignore_file" || true
        args+=(--exclude-from="$ignore_file")
    fi
    rsync -a "${args[@]}" "$src/" "$dst/"
    [[ -z "$ignore_file" ]] || rm -f -- "$ignore_file"
}

pack_sdz() {
    local src="$1" archive="$2"
    local tmp
    tmp="$(mktemp -d)"
    stage_tree "$src" "$tmp/root"
    (cd "$tmp/root" && zip -q -r -X "$archive" .)
    rm -rf -- "$tmp"
}

pack_sd7() {
    local src="$1" archive="$2"
    local tmp
    tmp="$(mktemp -d)"
    stage_tree "$src" "$tmp/root"
    (cd "$tmp/root" && 7z a -t7z -mx=5 -bso0 -bsp0 "$archive" .)
    rm -rf -- "$tmp"
}

# Record shipped checkouts and the current Cargo dependency resolution.
build_info="$content_dir/BUILDINFO.txt"
{
    echo "SpringCabal $version"
    echo "engine: ${engine_tag:-local} ($engine_repo)"
    echo "Cargo provenance describes current inputs; use --build to rebuild the shipped modules."
    echo "dev repo: $(git -C "$project_root" rev-parse --short HEAD)$(git -C "$project_root" diff --quiet HEAD -- wasm-menu || echo ' +local changes in wasm-menu')"
} > "$build_info"

record_source() {
    local label="$1" src="$2"
    if git -C "$src" rev-parse --show-toplevel 2>/dev/null | grep -qx "$src"; then
        local rev dirty=""
        rev="$(git -C "$src" rev-parse --short HEAD)"
        if [[ -n "$(git -C "$src" status --porcelain --untracked-files=no)" ]]; then
            dirty=" +uncommitted changes"
            echo "warning: $label has uncommitted changes" >&2
        fi
        printf '%-32s %s %s%s\n' "$label" "$(git -C "$src" rev-parse --abbrev-ref HEAD)" "$rev" "$dirty" >> "$build_info"
    else
        printf '%-32s (not a git checkout)\n' "$label" >> "$build_info"
    fi
}

log "Packing games"
while IFS=$'\t' read -r kind path source branch ship; do
    [[ "$ship" == yes ]] || continue
    record_source "$kind/$path" "$content_root/${kind}s/$path"
    case "$kind" in
        game)
            src="$content_root/games/$path"
            [[ -d "$src" ]] || die "missing game checkout: $src"
            [[ "$path" == *-wasm.sdd ]] && check_wasm_modules "$src"
            echo "    $path"
            pack_sdz "$src" "$content_dir/games/${path%.sdd}.sdz"
            ;;
        map)
            src="$content_root/maps/$path"
            [[ -e "$src" ]] || die "missing map: $src"
            echo "    $path"
            if [[ "$path" == Area17.sd7 ]]; then
                # The shipped Area 17 map carries a patched dual-fog gadget.
                cp -- "$("$project_root/scripts/area17-map.sh")" "$content_dir/maps/$path"
            elif [[ -d "$src" ]]; then
                pack_sd7 "$src" "$content_dir/maps/${path%.sdd}.sd7"
            else
                cp -- "$src" "$content_dir/maps/$path"
            fi
            ;;
        project)
            src="$content_root/projects/$path"
            [[ -d "$src" ]] || die "missing project: $src"
            echo "    projects/$path"
            stage_tree "$src" "$content_dir/projects/$path"
            ;;
    esac
done < <(manifest)

log "Packing WasmMenu"
menu_wasm="$project_root/wasm-menu/WasmMenu/wasm-menu.wasm"
[[ -f "$menu_wasm" ]] || die "wasm-menu.wasm missing (run with --build)"
record_source "WasmMenu" "$project_root/wasm-menu"
python3 "$project_root/release/wasm-info.py" "$project_root/wasm-menu/wasm-src" "$menu_wasm" >> "$build_info"
# The menu compiles in launch/games/ (start scripts, per-game graphics) and
# game-info/*/README.md (the games' descriptions).
if [[ -n "$(find "$project_root/launch/games" "$project_root/game-info" -newer "$menu_wasm" -print -quit)" ]]; then
    die "launch/games/ or game-info/ changed after wasm-menu.wasm was built (run with --build)"
fi
menu_tmp="$(mktemp -d)"
# Native menu libraries are local development builds. Both release platforms
# use the portable Wasm module rather than a library built for this host.
rsync -a --exclude=/wasm-src --exclude=/generate-rating-stars.sh \
    --exclude='/WasmMenu/libNativeMenu.*' --exclude=/WasmMenu/NativeMenu.dll \
    "$project_root/wasm-menu/" "$menu_tmp/root/"
(cd "$menu_tmp/root" && zip -q -r -X "$content_dir/games/WasmMenu.sdz" .)
rm -rf -- "$menu_tmp"

# ---------------------------------------------------------------------------
# Per-platform bundles
# ---------------------------------------------------------------------------
fetch_engine() {
    local plat="$1" dst="$2"
    local dir
    dir="$(local_engine_dir "$plat")"
    if [[ -n "$dir" ]]; then
        [[ -d "$dir" ]] || die "engine dir not found: $dir"
        log "Engine ($plat): local install $dir"
        rsync -a "$dir/" "$dst/"
        return
    fi
    local asset="recoil_${engine_tag}_amd64-${plat}.7z"
    local cached="$cache_root/engine/$engine_tag/$asset"
    if [[ ! -f "$cached" ]]; then
        log "Downloading $asset from $engine_repo"
        mkdir -p "$(dirname "$cached")"
        gh release download "$engine_tag" -R "$engine_repo" -p "$asset" -D "$(dirname "$cached")"
    fi
    log "Engine ($plat): $asset"
    7z x -bso0 -bsp0 -o"$dst" "$cached"
}

write_settings() {
    local cfg="$1"
    # An existing springsettings.cfg next to the binary puts the engine in
    # portable mode; we append the defaults the games are tuned for.
    {
        echo ""
        echo "# SpringCabal defaults"
        grep -v -E '^\s*(#|$)' "$project_root/launch/springsettings.cfg"
        grep -v -E '^\s*(#|$)' "$project_root/launch/menu.cfg"
    } >> "$cfg"
}

prepare_engine() {
    local plat="$1" dst="$2"
    local suffix="" entry
    [[ "$plat" != windows ]] || suffix=".exe"
    mv -- "$dst/spring$suffix" "$dst/SpringCabal$suffix"
    rm -f -- "$dst/spring-dedicated$suffix" "$dst/spring-headless$suffix" \
        "$dst/pr-downloader$suffix" "$dst/libunitsync.so" "$dst/unitsync.dll" \
        "$dst/files.md5.gz" "$dst"/*.a "$dst"/*.lib "$dst"/*.dbg
    rm -rf -- "$dst/examples"
    # Every launch script uses NullAI for the other team. Keep its C interface,
    # but discard the unrelated RTS skirmish AIs and their interfaces.
    for entry in "$dst"/AI/Skirmish/*; do
        [[ "${entry##*/}" == NullAI ]] || rm -rf -- "$entry"
    done
    for entry in "$dst"/AI/Interfaces/*; do
        [[ "${entry##*/}" == C ]] || rm -rf -- "$entry"
    done
    # The engine resolves this marker relative to its executable, including
    # when launched from a file manager or another working directory.
    touch "$dst/isolated.txt"
}

write_readme() {
    local plat="$1" dst="$2"
    local launcher="./SpringCabal"
    [[ "$plat" == windows ]] && launcher="SpringCabal.exe"
    local engine_desc="${engine_tag:-local build}"
    sed -e "s|@VERSION@|$version|g" -e "s|@ENGINE@|$engine_desc|g" -e "s|@LAUNCHER@|$launcher|g" \
        "$project_root/release/README.txt.in" > "$dst/README.txt"
    [[ "$plat" == windows ]] && sed -i 's/$/\r/' "$dst/README.txt"
    return 0
}

for plat in "${platforms[@]}"; do
    bundle="SpringCabal-$version-$plat"
    dst="$out_root/$bundle"
    log "Assembling $bundle"
    rm -rf -- "$dst"
    mkdir -p "$dst"
    fetch_engine "$plat" "$dst"
    prepare_engine "$plat" "$dst"
    # Hard links keep the per-platform copies cheap.
    cp -al "$content_dir/games/." "$dst/games/"
    cp -al "$content_dir/maps/." "$dst/maps/"
    mkdir -p "$dst/projects"
    cp -al "$content_dir/projects/." "$dst/projects/"
    touch "$dst/springsettings.cfg"
    write_settings "$dst/springsettings.cfg"
    write_readme "$plat" "$dst"
    cp -- "$build_info" "$dst/BUILDINFO.txt"

    if (( make_archives )); then
        rm -f -- "$out_root/$bundle.tar.gz" "$out_root/$bundle.zip"
        if [[ "$plat" == linux ]]; then
            log "Archiving $bundle.tar.gz"
            tar -C "$out_root" -czf "$out_root/$bundle.tar.gz" "$bundle"
        else
            log "Archiving $bundle.zip"
            (cd "$out_root" && zip -q -r -X "$bundle.zip" "$bundle")
        fi
    fi
done

log "Done. Output in $out_root"
ls -la "$out_root"
