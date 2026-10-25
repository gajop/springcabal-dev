#!/usr/bin/env bash
# Diagnostic recordings/profiles of the existing benchmark scenes. These runs
# are deliberately excluded from timing aggregates by report.py.
set -euo pipefail
project=$(cd -- "$(dirname -- "$0")/../.." && pwd)
out=${1:?Usage: capture.sh /absolute/output [runner options]}
shift
run=("$project/verification/verify" perf)
common=(--frame-step --repeats 1 --worker-threads 4
    --cpu-pressure-scope cgroup --timeout 300 --max-minutes 30 "$@")
for multiplier in 1 10; do
    "${run[@]}" hunted --output "$out/hunted-${multiplier}x" \
        --unit-multiplier "$multiplier" --record-world "${common[@]}"
    "${run[@]}" flove scripted --output "$out/flove-combat-${multiplier}x" \
        --input "$project/verification/perf/scenarios/flove-mushrooms.txt" \
        --unit-multiplier "$multiplier" --record-world "${common[@]}"
    "${run[@]}" ttld scripted --output "$out/ttld-shadows-${multiplier}x" \
        --input "$project/verification/perf/scenarios/ttld-shadows.txt" \
        --unit-multiplier "$multiplier" --record-world "${common[@]}"
done
for multiplier in 1 2; do
    "${run[@]}" area17 --output "$out/area17-${multiplier}x" \
        --unit-multiplier "$multiplier" --record-world "${common[@]}"
done
# Stress scenes expose the useful-work/dispatch tradeoff most clearly.
"${run[@]}" hunted --output "$out/hunted-10x-jobs" --backend wasm \
    --rust-jobs compare --unit-multiplier 10 --record-world "${common[@]}"
"${run[@]}" flove scripted --output "$out/flove-combat-10x-jobs" --backend wasm \
    --rust-jobs compare --unit-multiplier 10 --record-world \
    --input "$project/verification/perf/scenarios/flove-mushrooms.txt" "${common[@]}"
# Fire has no unit world to project; capture-profiles.sh and capture-video.sh
# retain its real renderer instead.
