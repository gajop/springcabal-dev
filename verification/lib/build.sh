#!/usr/bin/env bash
# Run workspaces, staged game modules and Rust builds. Sourced by common.sh.

vf_workspace() {
    local name=${1:?name} kind=${2:-temp}

    VF_OUT_DIR="$VERIFICATION_ROOT/out/$name"
    mkdir -p "$VF_OUT_DIR"

    if [[ $kind == stable ]]; then
        VF_TEST_ROOT="$VF_OUT_DIR/run"
    else
        VF_TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/$name-verify.XXXXXX")
    fi
    VF_ISOLATION="$VF_TEST_ROOT/isolation"
    VF_WRITE_DIR="$VF_TEST_ROOT/write"

    rm -rf -- "$VF_ISOLATION/games" "$VF_ISOLATION/maps"
    mkdir -p "$VF_ISOLATION/games" "$VF_ISOLATION/maps" \
        "$VF_WRITE_DIR/screenshots" "$VF_WRITE_DIR/cache"

    vf_share_fontcache
    vf_link_engine_data
}

vf_share_fontcache() {
    mkdir -p "$SHARED_FONTCACHE"
    rm -rf -- "$VF_WRITE_DIR/fontcache"
    ln -sfn "$SHARED_FONTCACHE" "$VF_WRITE_DIR/fontcache"
}

# Suites never modify a checkout under spring-linux/: anything that needs test
# modules, probe gadgets or edited files gets a private copy in the isolation
# view.  The checkout is what release/package.sh ships.
vf_stage_game() {
    local dir=${1:?game dir} staged
    VF_GAME_DIR=$dir
    staged="$VF_ISOLATION/games/$(basename "$dir")"
    rm -rf -- "$staged"
    mkdir -p "$staged"
    (cd "$dir" && tar --exclude=./wasm-src --exclude=./target --exclude=./.git -cf - .) | (cd "$staged" && tar -xf -)
    printf '%s\n' "$staged"
}

# vf_install_modules STAGED CRATE:ARCHIVE_PATH...
# Copies modules from the last vf_build into a staged game copy.
vf_install_modules() {
    local staged=${1:?staged game} pair crate dest
    shift
    [[ -n $VF_BUILD_OUT ]] || vf_die 'vf_install_modules: call vf_build first'
    [[ $staged == "$VF_ISOLATION"/* ]] || vf_die "refusing to install modules outside the isolation view: $staged"
    for pair in "$@"; do
        crate=${pair%%:*}
        dest=${pair#*:}
        [[ -s "$VF_BUILD_OUT/$crate.wasm" ]] || vf_die "missing build artifact: $crate.wasm"
        cp "$VF_BUILD_OUT/$crate.wasm" "$staged/$dest"
    done
}

# vf_cleanup_on_exit: remove the temporary workspace when the suite ends.
# Only EXIT runs the cleanup.  INT and TERM just exit (130/143), which runs
# the EXIT trap once; a handler on INT itself would let the script continue
# after Ctrl+C and then clean up a second time on exit.
vf_cleanup_on_exit() {
    trap 'vf_keep_workspace_unless' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
}

vf_keep_workspace_unless() {
    local keep=${KEEP_TEST_ARTIFACTS:-0}
    [[ $keep == 1 ]] && return 0
    [[ $VF_TEST_ROOT == /tmp/* || $VF_TEST_ROOT == "${TMPDIR:-/tmp}"/* ]] || return 0
    rm -rf -- "$VF_TEST_ROOT"
}

vf_link_engine_data() {
    ln -sfn "$ENGINE_INSTALL/base" "$VF_ISOLATION/base"
    ln -sfn "$ENGINE_INSTALL/fonts" "$VF_ISOLATION/fonts"

    if [[ -d "$ENGINE_INSTALL/AI" ]]; then
        ln -sfn "$ENGINE_INSTALL/AI" "$VF_ISOLATION/AI"
    elif [[ -d "$PROJECT_ROOT/spring-linux/AI" ]]; then
        ln -sfn "$PROJECT_ROOT/spring-linux/AI" "$VF_ISOLATION/AI"
    fi
    [[ -d "$PROJECT_ROOT/spring-linux/LuaUI" ]] &&
        ln -sfn "$PROJECT_ROOT/spring-linux/LuaUI" "$VF_ISOLATION/LuaUI"
    return 0
}

vf_link_game() {
    local dir=${1:?game dir}
    [[ -e $dir ]] || vf_die "game archive not found: $dir"
    [[ $dir == "$VF_ISOLATION"/* ]] || VF_GAME_DIR=$dir
    [[ $dir == "$VF_ISOLATION"/* ]] && return 0
    ln -sfn "$dir" "$VF_ISOLATION/games/$(basename "$dir")"
}

vf_link_map() {
    local path=${1:?map path}; shift
    VF_MAP=$path
    [[ -e $path ]] || vf_die "map archive not found: $path"
    ln -sfn "$path" "$VF_ISOLATION/maps/$(basename "$path")"
    local alias
    for alias in "$@"; do
        ln -sfn "$path" "$VF_ISOLATION/maps/$alias"
    done
}

# vf_build SOURCE_ROOT [FEATURES] [TARGET_DIR]
# fmt + clippy + build into verification/cache/target/<game> (or TARGET_DIR),
# never into the checkout's own target/ (whose output `just copy` installs).
# Sets VF_BUILD_OUT.
vf_build() {
    local source_root=${1:?wasm-src} features=${2:-} game target=${3:-}
    [[ -d $source_root ]] || vf_die "wasm source not found: $source_root"
    game=$(basename "$(dirname "$source_root")")
    [[ -n $target ]] || target="$BUILD_CACHE/$game"
    local -a feature_args=()
    [[ -n $features ]] && feature_args=(--features "$features")
    (
        cd "$source_root"
        # The enclosing || disables Bash's errexit inside this subshell.
        # Stop explicitly so a later successful build cannot hide failed checks.
        cargo fmt --all -- --check || exit
        cargo clippy --workspace "${feature_args[@]}" --target wasm32-unknown-unknown \
            --release --target-dir "$target" -- -D warnings || exit
        cargo build --workspace "${feature_args[@]}" --target wasm32-unknown-unknown \
            --release --target-dir "$target"
    ) || vf_die "build failed: $source_root ${features:+(features: $features)}"
    VF_BUILD_OUT="$target/wasm32-unknown-unknown/release"
}

# vf_installed_matches_source GAME_DIR: the modules `just copy` installs in
# the game (its justfile's copy recipe) match a fresh build of wasm-src/,
# made outside the checkout (see vf_same_length_target).  Custom sections
# (names, producers) are ignored: ThinLTO suffixes local symbol names with a
# hash of the object file's path, so they change with the target directory
# even when the code does not.
vf_installed_matches_source() {
    local game_dir=${1:?game dir} source_root reference target line crate dest installed fresh count=0
    source_root="$game_dir/wasm-src"
    reference="$source_root/target"
    target=$(vf_same_length_target "$reference" "$(basename "$game_dir" -wasm.sdd)")
    vf_build "$source_root" '' "$target"
    while read -r line; do
        crate=$(sed -E 's|.*release/([^ ]+)\.wasm .*|\1|' <<<"$line")
        dest=$(sed -E 's|.* \.\./([^ ]+)$|\1|' <<<"$line")
        installed="$game_dir/$dest"
        fresh="$VF_OUT_DIR/$crate.wasm"
        [[ -s "$VF_BUILD_OUT/$crate.wasm" ]] || vf_die "missing build artifact: $crate.wasm"
        [[ -s $installed ]] || vf_die "not installed: $installed (run \`just copy\` in $source_root)"
        # Name the fresh build's target directory as `just copy` names it.
        FROM=$target TO=$reference perl -0777 -pe 's/\Q$ENV{FROM}\E/$ENV{TO}/g' \
            "$VF_BUILD_OUT/$crate.wasm" | vf_wasm_code_only >"$fresh"
        vf_wasm_code_only <"$installed" >"$fresh.installed"
        cmp -s "$fresh" "$fresh.installed" ||
            vf_die "$installed does not match its source; rebuild it with \`just copy\` in $source_root"
        count=$((count + 1))
    done < <(grep -E '^[[:space:]]+cp target/wasm32-unknown-unknown/release/[^ ]+\.wasm \.\./' "$source_root/justfile")
    [[ $count -gt 0 ]] || vf_die "no module copies found in $source_root/justfile"
    printf 'installed modules match the source: %s (%s modules)\n' "$(basename "$game_dir")" "$count"
}

# A wasm module without its custom sections (the name section, producers):
# code, data, types, imports and exports.
vf_wasm_code_only() {
    python3 -c '
import sys
data = sys.stdin.buffer.read()
def leb(i):
    value = shift = 0
    while True:
        byte = data[i]; i += 1
        value |= (byte & 0x7f) << shift; shift += 7
        if byte < 0x80:
            return value, i
out, i = bytearray(data[:8]), 8
while i < len(data):
    size, body = leb(i + 1)
    if data[i] != 0:
        out += data[i:body + size]
    i = body + size
sys.stdout.buffer.write(out)
'
}

# vf_same_length_target REFERENCE NAME: a build directory whose path is
# exactly as long as REFERENCE.  The modules embed their build directory (the
# spring crate's generated bindings live in OUT_DIR, and panic locations name
# it), so a build elsewhere can't be byte-identical to the checkout's
# target/, which the suites never write to.  With equal lengths, the only
# difference is the text of that path, which the caller replaces.  (Cargo's
# metadata hashes don't depend on the target directory.)
vf_same_length_target() {
    local reference=${1:?reference} name=${2:?name} base pad
    for base in "$BUILD_CACHE/$name-static-" "${TMPDIR:-/tmp}/vf-$name-" "${TMPDIR:-/tmp}/vf-"; do
        pad=$(( ${#reference} - ${#base} ))
        if (( pad >= 1 )); then
            printf '%s%s\n' "$base" "$(printf '%*s' "$pad" '' | tr ' ' x)"
            return
        fi
    done
    vf_die "no build directory as short as $reference; the check needs one of equal length"
}
