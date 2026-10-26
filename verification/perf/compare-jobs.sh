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
    "$root/verification/verify" perf "$game" "$scenario" --mode gpu --frame-step --wait-for-idle --wait-for-gpu-idle \
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
    # HAPFS path requests use the shared pool. Identical Lua replays can take
    # different paths at width four; keep a deterministic width-one control.
    for width in 1 4; do
        measure "$name-lua-rust-w$width" "$game" "$scenario" \
            --backend both --rust-jobs off --worker-threads "$width" "$@"
    done
}
case_pair hunted hunted autonomous
case_pair hunted-10x hunted autonomous --unit-multiplier 10
case_pair flove-combat flove scripted --input "$root/verification/perf/scenarios/flove-mushrooms.txt"
case_pair flove-combat-10x flove scripted --unit-multiplier 10 \
    --input "$root/verification/perf/scenarios/flove-mushrooms.txt"
for count in 1 10 100; do
    measure "fire-$count-lua-rust-w4" gravitas effects --effects-multiplier "$count" \
        --backend both --rust-jobs off --worker-threads 4
done
# The CPU renderer is a reference, not the production path. One substantial
# equal-budget fixture measures its off/on dispatch tradeoff at both widths.
for width in 1 4; do
    measure "fire-10-cpu-jobs-w$width" gravitas effects --effects-multiplier 10 \
        --backend wasm --fire-renderer cpu --rust-jobs compare --worker-threads "$width"
done
# GPU curve evaluation removes the CPU jobs workload. Record that activation
# state explicitly, rather than presenting an inactive switch as a speedup.
measure fire-10-gpu-jobs-w4 gravitas effects --effects-multiplier 10 \
    --backend wasm --rust-jobs compare --worker-threads 4 --repeats 1 --clean-pairs 1
for game in mycube partsneeded; do
    measure "$game-1x-w1" "$game" autonomous --backend both --worker-threads 1
done
# These ports' current hot paths are native engine work. Measure the shared
# pool's effect without pretending that adding game jobs parallelizes it.
for count in 1 10; do
    measure "ttld-shadows-${count}x-w1" ttld scripted --backend both --rust-jobs off \
        --worker-threads 1 --unit-multiplier "$count" \
        --input "$root/verification/perf/scenarios/ttld-shadows.txt"
done
for count in 1 2; do
    measure "area17-${count}x-w1" area17 autonomous --backend both --rust-jobs off \
        --worker-threads 1 --unit-multiplier "$count"
done
python3 "$root/verification/perf/report.py" "$output"
exit "$status"
