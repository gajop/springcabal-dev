#!/usr/bin/env bash
# Compare serial Rust and pure jobs at identical engine pool widths, with Lua controls.
set -euo pipefail
root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
[[ $# -ge 1 ]] || { echo 'usage: compare-jobs.sh OUTPUT_DIR [perf runner options]' >&2; exit 2; }
output=$(realpath -m -- "$1")
shift
mkdir -p "$output"
options=("$@")
status=0
measure() {
    local name=$1 game=$2 scenario=$3
    shift 3
    "$root/verification/verify" perf "$game" "$scenario" --mode gpu --frame-step --wait-for-idle \
        --output "$output/$name" "${options[@]}" "$@" || status=1
}
case_pair() {
    local name=$1 game=$2 scenario=$3
    shift 3
    local width
    for width in 1 4; do
        measure "$name-jobs-w$width" "$game" "$scenario" \
            --backend wasm --rust-jobs compare --worker-threads "$width" "$@"
    done
    measure "$name-lua-rust-w4" "$game" "$scenario" \
        --backend both --rust-jobs off --worker-threads 4 "$@"
}
case_pair hunted hunted autonomous
case_pair hunted-10x hunted autonomous --unit-multiplier 10
case_pair flove-combat flove scripted --input "$root/verification/perf/scenarios/flove-mushrooms.txt"
case_pair flove-combat-10x flove scripted --unit-multiplier 10 \
    --input "$root/verification/perf/scenarios/flove-mushrooms.txt"
for count in 1 10 100; do
    case_pair "fire-$count" gravitas effects --effects-multiplier "$count"
done
# These ports' current hot paths are native engine work. Measure the shared
# pool's effect without pretending that adding game jobs parallelizes it.
for count in 1 10; do
    measure "ttld-shadows-${count}x-w4" ttld scripted --backend both --rust-jobs off \
        --worker-threads 4 --unit-multiplier "$count" \
        --input "$root/verification/perf/scenarios/ttld-shadows.txt"
done
for count in 1 2; do
    measure "area17-${count}x-w4" area17 autonomous --backend both --rust-jobs off \
        --worker-threads 4 --unit-multiplier "$count"
done
python3 "$root/verification/perf/report.py" "$output"
exit "$status"
