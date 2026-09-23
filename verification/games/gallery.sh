#!/usr/bin/env bash
# Golden galleries: every CEG, and every unit type's animations, captured in
# one engine run per game by fixtures/gallery/gallery.lua.
#
#   gallery.sh ceg [game|all]            CEG statistics against goldens
#   gallery.sh anim [game|all]           unit poses + images against goldens
#   gallery.sh parity [game|all]         WASM vs Lua unit poses (report)
#   gallery.sh <kind> <game> --only a,b  restrict to some CEGs / unit defs
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

GALLERY_FIXTURE="$FIXTURES_DIR/gallery/gallery.lua"
# The galleries fit in the offscreen display, so they render on the real GPU
# without a window by default.  Goldens note the renderer they came from.
VF_DEFAULT_RENDERER=gpu
GALLERY_SIZE=720
GALLERY_TOOL="$VERIFICATION_ROOT/lib/gallery.py"
# Games with CEGs of their own (MyCube and Parts Needed define none).
CEG_GAMES=(area17 flove gravitas hunted ttld)
ANIM_GAMES=(area17 flove gravitas hunted mycube partsneeded ttld)

# gallery_game GAME: sets WASM_DIR, LUA_DIR and the maps to link.  Start
# scripts are the menu's own, from launch/games/GAME/.
gallery_game() {
    LUA_MAP=''
    case "${1:?game}" in
        area17) WASM_DIR="$GAMES_DIR/Area17-wasm.sdd" LUA_DIR="$GAMES_DIR/Area-17.sdd"
            MAP="$("$PROJECT_ROOT/scripts/area17-map.sh" --dir)" ;;
        flove) WASM_DIR="$GAMES_DIR/Flove-wasm.sdd" LUA_DIR="$GAMES_DIR/Flove.sdd"
            MAP="$MAPS_DIR/LD34-map.sdd" ;;
        gravitas) WASM_DIR="$GAMES_DIR/Gravitas-wasm.sdd" LUA_DIR="$GAMES_DIR/Scenario-Editor-Gravitas.sdd"
            MAP="$MAPS_DIR/Gravitas-map.sdd" ;;
        hunted) WASM_DIR="$GAMES_DIR/Hunted-wasm.sdd" LUA_DIR="$GAMES_DIR/Hunted.sdd"
            MAP="$MAPS_DIR/HuntedMap.sdd" ;;
        ttld) WASM_DIR="$GAMES_DIR/ToTheLastDrop-wasm.sdd" LUA_DIR="$GAMES_DIR/ToTheLastDrop.sdd"
            MAP="$MAPS_DIR/LD43-map.sdd" ;;
        mycube) WASM_DIR="$GAMES_DIR/MyCube-wasm.sdd" LUA_DIR="$GAMES_DIR/MyCube.sdd"
            MAP="$MAPS_DIR/MyCube_v1-wasm.sdd" LUA_MAP="$MAPS_DIR/MyCube_v1.sd7" ;;
        partsneeded) WASM_DIR="$GAMES_DIR/PartsNeeded-wasm.sdd" LUA_DIR="$GAMES_DIR/PartsNeeded.sdd"
            MAP="$MAPS_DIR/LD35-map.sdd" ;;
        *) vf_die "unknown gallery game: $1" ;;
    esac
}

# Removes game code that would move the camera or draw over the capture.
# CEG runs also drop every rules gadget and module: CEGs are pure game data.
gallery_strip() {
    local staged=$1 kind=$2
    rm -rf -- "$staged/LuaUI/Widgets" "$staged/LuaUI/widgets"
    [[ -f $staged/LuaUI/wasm/manifest.txt ]] && : >"$staged/LuaUI/wasm/manifest.txt"
    if [[ $kind == ceg ]]; then
        find "$staged/LuaRules/Gadgets" -maxdepth 1 -type f -delete 2>/dev/null || true
        [[ -f $staged/LuaRules/wasm/manifest.txt ]] && : >"$staged/LuaRules/wasm/manifest.txt"
    fi
    return 0
}

# Several WASM ports switch unsynced LuaRules off (draw.lua is `return true`).
# Give those, and every CEG run, an entry point that runs only the gallery's
# unsynced half, so the game's own unsynced gadgets stay as they ship.
gallery_unsynced_entry() {
    local staged=$1 kind=$2 draw="$1/LuaRules/draw.lua"
    if [[ $kind == anim ]] && grep -q 'luagadgets/gadgets.lua' "$draw" 2>/dev/null; then
        return 0
    fi
    cat >"$draw" <<'LUA'
-- Verification entry point: runs only the golden gallery's unsynced half.
gadget = {}
gadgetHandler = { IsSyncedCode = function() return false end }
VFS.Include("LuaRules/Gadgets/zz_golden_gallery.lua", nil, VFS.ZIP_FIRST)
function GameFrame(n) if gadget.GameFrame then gadget:GameFrame(n) end end
function DrawScreenEffects(vsx, vsy) if gadget.DrawScreenEffects then gadget:DrawScreenEffects(vsx, vsy) end end
if gadget.Initialize then gadget:Initialize() end
LUA
}

# gallery_run KIND GAME VARIANT(wasm|lua) -> captures in $VF_OUT_DIR/captures
gallery_run() {
    local kind=$1 game=$2 variant=$3 dir staged t0=$EPOCHREALTIME t1
    gallery_game "$game"
    dir=$([[ $variant == lua ]] && echo "$LUA_DIR" || echo "$WASM_DIR")
    [[ -d $dir ]] || vf_die "missing archive: $dir"

    vf_workspace "gallery-$kind-$game-$variant" stable
    staged=$(vf_stage_game "$dir")
    gallery_strip "$staged" "$kind"
    mkdir -p "$staged/LuaRules/Gadgets"
    cp "$GALLERY_FIXTURE" "$staged/LuaRules/Gadgets/zz_golden_gallery.lua"
    gallery_unsynced_entry "$staged" "$kind"
    # For testing the goldens themselves: break something in the staged copy.
    if [[ -n ${GALLERY_STAGE_HOOK:-} ]]; then
        (cd "$staged" && eval "$GALLERY_STAGE_HOOK")
    fi
    vf_link_map "$MAP"
    [[ -n $LUA_MAP ]] && vf_link_map "$LUA_MAP"
    if [[ $variant == lua ]]; then
        # The Lua Gravitas is Scenario Editor Gravitas, which depends on the
        # Gravitas and Scenario Editor Core archives and a project directory.
        local dep
        for dep in "$GAMES_DIR/Gravitas.sdd" "$GAMES_DIR/Scenario-Editor-Core.sdd"; do
            [[ $game == gravitas ]] && vf_link_game "$dep"
        done
        [[ -d $PROJECT_ROOT/spring-linux/projects ]] &&
            ln -sfn "$PROJECT_ROOT/spring-linux/projects" "$VF_ISOLATION/projects"
    fi

    vf_start_file "$(vf_launch_script "$game" "$variant")"
    vf_start_set FixedRNGSeed 1
    vf_start_set minspeed 1
    vf_start_set maxspeed 1
    vf_modoption gallery "$kind"
    vf_modoption gallery_out gallery
    [[ -n ${GALLERY_ONLY:-} ]] && vf_modoption gallery_only "$GALLERY_ONLY"
    [[ ${GALLERY_FULL:-0} == 1 ]] && vf_modoption gallery_full 1

    vf_config "$VISUAL_CONFIG"
    vf_config_set XResolutionWindowed $GALLERY_SIZE
    vf_config_set YResolutionWindowed $GALLERY_SIZE
    vf_config_set WindowPosX 0
    vf_config_set WindowPosY 0
    vf_graphics "$game"
    rm -rf -- "$VF_WRITE_DIR/gallery"
    t1=$EPOCHREALTIME
    vf_run_visual "${GALLERY_SECONDS:-300}" "${GALLERY_SIZE}x${GALLERY_SIZE}x24"
    printf 'timing: stage %.1fs, engine %.1fs\n' "$(echo "$t1 - $t0" | bc)" "$(echo "$EPOCHREALTIME - $t1" | bc)"
    vf_save_logs
    vf_forbid 'Gallery\] ERROR (effects-file|pose-no-piece-map|job|create-unit|spawn-ceg|save-failed)' \
        "the gallery reported an error"
    vf_require 'Gallery\] COMPLETE' "the $kind gallery did not finish (see $VF_OUT_DIR/last.combined.txt)"

    rm -rf -- "$VF_OUT_DIR/captures"
    mv "$VF_WRITE_DIR/gallery" "$VF_OUT_DIR/captures"

    grep -oE '\[Gallery\] pose .*' "$VF_WRITE_DIR/stdout.txt" | sed 's/^\[Gallery\] pose //' \
        >"$VF_OUT_DIR/captures/poses.txt" || true
    grep -oE '\[Gallery\] ERROR .*' "$VF_WRITE_DIR/stdout.txt" >&2 || true
}

gallery_compare() {
    local kind=$1 game=$2
    local golden="$FIXTURES_DIR/$game/goldens/$kind"
    local mode=compare
    [[ ${VF_UPDATE_GOLDENS:-0} == 1 ]] && mode=update
    local t0=$EPOCHREALTIME status=0
    GALLERY_RENDERER=$(vf_renderer) python3 "$GALLERY_TOOL" "$mode" "$kind" \
        "${GALLERY_CAPTURES:-$VF_OUT_DIR/captures}" "$golden" "$VF_OUT_DIR/report" || status=$?
    printf 'timing: compare %.1fs\n' "$(echo "$EPOCHREALTIME - $t0" | bc)"
    return $status
}

gallery_each() {
    local kind=$1 target=$2 failed=() game
    shift 2
    local -a games
    if [[ $target == all ]]; then
        [[ $kind == ceg ]] && games=("${CEG_GAMES[@]}") || games=("${ANIM_GAMES[@]}")
    else
        games=("$target")
    fi
    for game in "${games[@]}"; do
        vf_note "$kind gallery: $game"
        if ! ( "$@" "$game" ); then
            failed+=("$game")
        fi
    done
    [[ ${#failed[@]} -eq 0 ]] || vf_die "$kind gallery failed for: ${failed[*]}"
}

# Recording takes GALLERY_RECORD_RUNS runs (CEGs 4, animations 2), so each
# capture's own run-to-run noise sets its tolerance.
gallery_golden() {
    local kind=$1 game=$2 runs=1 i
    local -a captures=()
    if [[ ${VF_UPDATE_GOLDENS:-0} == 1 ]]; then
        [[ $kind == ceg ]] && runs=${GALLERY_RECORD_RUNS:-4} || runs=${GALLERY_RECORD_RUNS:-2}
    fi
    for ((i = 1; i <= runs; i++)); do
        # The first recording run also keeps full-size captures for screenshots.
        GALLERY_FULL=$([[ ${VF_UPDATE_GOLDENS:-0} == 1 && $i == 1 ]] && echo 1 || echo "${GALLERY_FULL:-0}") \
            gallery_run "$kind" "$game" wasm
        if [[ $runs -gt 1 ]]; then
            rm -rf -- "$VF_OUT_DIR/captures-$i"
            mv "$VF_OUT_DIR/captures" "$VF_OUT_DIR/captures-$i"
            captures+=("$VF_OUT_DIR/captures-$i")
        fi
    done
    if [[ $runs -gt 1 ]]; then
        ln -sfn "captures-1" "$VF_OUT_DIR/captures"
        GALLERY_CAPTURES=$(IFS=,; echo "${captures[*]}")
    else
        GALLERY_CAPTURES="$VF_OUT_DIR/captures"
    fi
    gallery_compare "$kind" "$game" || return
    if [[ ${VF_UPDATE_GOLDENS:-0} == 1 ]]; then
        local first=${GALLERY_CAPTURES%%,*}
        python3 "$GALLERY_TOOL" screenshots "$kind" "$first" "$FIXTURES_DIR/$game/screenshots/$kind" -
        gallery_game "$game"
        vf_provenance "$FIXTURES_DIR/$game/goldens/$kind/PROVENANCE.txt" "$WASM_DIR" "$MAP" \
            "$([[ $game == area17 ]] && echo "$MAPS_DIR/Area17.sd7")"
    fi
}

gallery_parity() {
    local game=$1 wasm lua
    gallery_run anim "$game" wasm
    wasm="$VF_OUT_DIR/captures"
    gallery_run anim "$game" lua
    lua="$VF_OUT_DIR/captures"
    python3 "$GALLERY_TOOL" parity anim "$wasm" "$lua" "$VERIFICATION_ROOT/out/gallery-parity-$game"
}

kind=${1:-ceg}
target=${2:-all}
if [[ ${3:-} == --only ]]; then
    export GALLERY_ONLY=${4:?--only needs a list}
fi
case "$kind" in
    ceg) gallery_each ceg "$target" gallery_golden ceg ;;
    anim) gallery_each anim "$target" gallery_golden anim ;;
    parity) gallery_each anim "$target" gallery_parity ;;
    *) vf_die 'usage: gallery.sh [ceg|anim|parity] [game|all] [--only name,...]' ;;
esac
