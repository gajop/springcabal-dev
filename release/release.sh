#!/usr/bin/env bash
# Prepare all five public assets locally, then explicitly publish them to GitHub.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
caller=$PWD
cd "$root"
repo=gajop/springcabal-dev
engine_repo=gajop/spring-rust
out="$root/release/out"

usage() {
    cat <<'EOF'
Usage:
  release/release.sh prepare VERSION --engine-tag TAG
  release/release.sh publish VERSION --notes FILE [--title TITLE] [--prerelease] [--draft] [--dry-run]

prepare  Rebuild local WASM, package Linux + Windows from published engine
         binaries, archive committed sources, write BUILDINFO and SHA256SUMS.
publish  Check those assets and revisions, push framework main + vVERSION,
         upload to a draft release, verify GitHub checksums, then publish it.
         --prerelease publishes without changing the latest stable release.
         --draft leaves it as a draft; --dry-run performs no remote writes.

Game, map and shared-crate repositories are never pushed. See RELEASING.md.
EOF
}
die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }
[[ ${1:-} != --help && ${1:-} != -h ]] || { usage; exit 0; }
[[ $# -ge 2 ]] || { usage; exit 1; }
action=$1 version=$2
shift 2
[[ $action == prepare || $action == publish ]] || die "expected prepare or publish"
[[ $version =~ ^[0-9][A-Za-z0-9._-]*$ ]] || die "invalid version: $version"
engine_tag='' notes='' title="SpringCabal $version" prerelease=0 draft=0 dry_run=0
while [[ $# -gt 0 ]]; do
    case $1 in
        --engine-tag) engine_tag=${2:?missing tag}; shift 2 ;;
        --notes) notes=${2:?missing notes file}; shift 2 ;;
        --title) title=${2:?missing title}; shift 2 ;;
        --prerelease) prerelease=1; shift ;;
        --draft) draft=1; shift ;;
        --dry-run) dry_run=1; shift ;;
        *) die "unknown option: $1" ;;
    esac
done
if [[ -n $notes && $notes != /* ]]; then notes="$caller/$notes"; fi
for tool in git gh python3 sha256sum; do
    command -v "$tool" >/dev/null || die "missing tool: $tool"
done
mkdir -p "$out"
temporary=$(mktemp -d "$out/.release-XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT
record="$out/SOURCES-$version.json"
tag="v$version"
assets=("SpringCabal-$version-linux.tar.gz" "SpringCabal-$version-windows.zip"
        "SpringCabal-$version-source.tar.gz" "BUILDINFO-$version.txt" "SHA256SUMS-$version.txt")

source_inventory() {
    python3 "$root/release/source-snapshot.py" --version "$version" \
        --engine-tag "$engine_tag" --engine-commit "$engine_commit" "$@"
}

if [[ $action == prepare ]]; then
    [[ -n $engine_tag ]] || die "prepare requires --engine-tag"
    [[ -z $notes && $prerelease == 0 && $draft == 0 && $dry_run == 0 ]] || die "--notes, --prerelease, --draft and --dry-run are publish options"
    # Resolve annotated or lightweight tags to the actual released engine commit.
    ref=$(gh api "repos/$engine_repo/git/ref/tags/$engine_tag" --jq '.object | [.type, .sha] | @tsv')
    while [[ $ref == tag$'\t'* ]]; do
        ref=$(gh api "repos/$engine_repo/git/tags/${ref#*$'\t'}" --jq '.object | [.type, .sha] | @tsv')
    done
    [[ $ref == commit$'\t'* ]] || die "engine tag does not resolve to a commit"
    engine_commit=${ref#*$'\t'}
    gh release view "$engine_tag" -R "$engine_repo" --json assets,isDraft \
        --jq 'select(.isDraft == false) | .assets[].name' > "$temporary/engine-assets"
    for platform in linux windows; do
        grep -Fxq "recoil_${engine_tag}_amd64-$platform.7z" "$temporary/engine-assets" ||
            die "engine release is missing its $platform binary"
    done
    log "Checking committed sources for $version (engine $engine_tag at $engine_commit)"
    source_inventory --check > "$temporary/before.json"
    # Invalidate any earlier preparation before replacing its payloads.
    rm -f -- "$record"
    "$root/release/package.sh" --engine-tag "$engine_tag" --version "$version" --platform all --build
    source_inventory > "$temporary/after.json"
    cmp -s "$temporary/before.json" "$temporary/after.json" || die "sources changed during preparation; prepare again"
    cp -- "$out/content-$version/BUILDINFO.txt" "$out/BUILDINFO-$version.txt"
    printf '\nReleased engine commit: %s\n' "$engine_commit" >> "$out/BUILDINFO-$version.txt"
    (cd "$out" && sha256sum "${assets[@]:0:4}") > "$temporary/checksums"
    mv -- "$temporary/checksums" "$out/SHA256SUMS-$version.txt"
    mv -- "$temporary/after.json" "$record"
    log "Prepared all five assets in $out (nothing pushed or uploaded)"
    printf '  %s\n' "${assets[@]}"
    exit 0
fi

[[ -z $engine_tag ]] || die "publish reads the engine tag from the prepared sources"
[[ -f $notes ]] || die "publish requires --notes FILE"
[[ -f $record ]] || die "run prepare $version first"
engine_tag=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["engine_tag"])' "$record")
engine_commit=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["engine_commit"])' "$record")
source_inventory --check > "$temporary/current.json"
cmp -s "$record" "$temporary/current.json" || die "sources differ from the prepared release; prepare again"
for asset in "${assets[@]}"; do
    [[ -s $out/$asset ]] || die "missing asset: $asset"
done
# Check the exact expected file list, not an arbitrary checksum file's paths.
(cd "$out" && sha256sum "${assets[@]:0:4}") > "$temporary/checksums"
cmp -s "$temporary/checksums" "$out/SHA256SUMS-$version.txt" || die "prepared asset checksums do not match"
[[ $(git branch --show-current) == main ]] || die "publish from the framework's main branch"
[[ $(gh repo view --json nameWithOwner --jq .nameWithOwner) == "$repo" ]] || die "origin must be $repo"
commit=$(git rev-parse HEAD)
if git show-ref --verify --quiet "refs/tags/$tag"; then
    [[ $(git rev-parse "$tag^{commit}") == "$commit" ]] || die "$tag already names a different commit"
fi
remote_commit=''
remote_refs=$(git ls-remote origin "refs/tags/$tag" "refs/tags/$tag^{}")
while read -r remote_sha remote_ref; do
    [[ -n $remote_sha ]] || continue
    remote_commit=$remote_sha
    [[ $remote_ref != "refs/tags/$tag^{}" ]] || break
done <<< "$remote_refs"
[[ -z $remote_commit || $remote_commit == "$commit" ]] || die "remote $tag already names a different commit"
existing=$(gh release list -R "$repo" --limit 1000 --json tagName,isDraft \
    --jq ".[] | select(.tagName == \"$tag\") | .isDraft")
[[ $existing != false ]] || die "$tag is already public; choose a new version"
log "Publish $tag at $commit to $repo"
if (( dry_run )); then
    printf 'Would push framework main and %s, upload these assets, and %s:\n' \
        "$tag" "$([[ $draft == 1 ]] && echo 'keep a draft' || echo 'publish the release')"
    printf '  %s\n' "${assets[@]}"
    printf 'Title: %s\nNotes: %s\n' "$title" "$notes"
    printf 'Prerelease: %s\n' "$prerelease"
    exit 0
fi
if ! git show-ref --verify --quiet "refs/tags/$tag"; then
    git tag -a "$tag" -m "$title" "$commit"
fi
git push --atomic origin HEAD:refs/heads/main "refs/tags/$tag"
classification=(--prerelease=false)
if (( prerelease )); then classification=(--prerelease=true); fi
if [[ -z $existing ]]; then
    gh release create "$tag" -R "$repo" --verify-tag --draft "${classification[@]}" --title "$title" --notes-file "$notes"
else
    gh release edit "$tag" -R "$repo" "${classification[@]}" --title "$title" --notes-file "$notes"
fi
asset_paths=()
for asset in "${assets[@]}"; do asset_paths+=("$out/$asset"); done
gh release upload "$tag" -R "$repo" --clobber "${asset_paths[@]}"
release_api=$(gh release view "$tag" -R "$repo" --json apiUrl --jq .apiUrl)
gh api "$release_api" > "$temporary/uploaded.json"
python3 - "$temporary/uploaded.json" "${asset_paths[@]}" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

uploaded = {asset['name']: asset.get('digest') for asset in json.load(open(sys.argv[1]))['assets']}
for name in sys.argv[2:]:
    path = Path(name)
    with path.open('rb') as stream:
        expected = 'sha256:' + hashlib.file_digest(stream, 'sha256').hexdigest()
    if uploaded.get(path.name) != expected:
        sys.exit(f'GitHub checksum mismatch for {path.name}; release remains a draft')
print('All five GitHub asset checksums match.')
PY
if (( ! draft )); then
    if (( prerelease )); then
        gh release edit "$tag" -R "$repo" --verify-tag --draft=false --prerelease=true --latest=false
    else
        gh release edit "$tag" -R "$repo" --verify-tag --draft=false --prerelease=false --latest
    fi
fi
gh release view "$tag" -R "$repo" --json url,isDraft,isPrerelease --jq '{url, isDraft, isPrerelease}'
