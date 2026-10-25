#!/usr/bin/env bash
# Profile without the world observer: its serialization is unrelated to game cost.
set -euo pipefail
project=$(cd -- "$(dirname -- "$0")/../.." && pwd)
out=${1:?Usage: capture-profiles.sh /absolute/output [runner options]}
shift
run=("$project/verification/verify" perf)
common=(--frame-step --profile --repeats 1 --worker-threads 4
    --cpu-pressure-scope cgroup --wait-for-idle --wait-for-gpu-idle
    --timeout 300 --max-minutes 30 "$@")
for multiplier in 1 10; do
    "${run[@]}" hunted --output "$out/hunted-${multiplier}x" \
        --unit-multiplier "$multiplier" "${common[@]}"
    "${run[@]}" flove scripted --output "$out/flove-combat-${multiplier}x" \
        --input "$project/verification/perf/scenarios/flove-mushrooms.txt" \
        --unit-multiplier "$multiplier" "${common[@]}"
    "${run[@]}" ttld scripted --output "$out/ttld-shadows-${multiplier}x" \
        --input "$project/verification/perf/scenarios/ttld-shadows.txt" \
        --unit-multiplier "$multiplier" "${common[@]}"
done
for multiplier in 1 2; do
    "${run[@]}" area17 --output "$out/area17-${multiplier}x" \
        --unit-multiplier "$multiplier" "${common[@]}"
done
for multiplier in 1 10; do
    "${run[@]}" gravitas effects --output "$out/fire-${multiplier}" \
        --effects-multiplier "$multiplier" "${common[@]}"
done
"${run[@]}" hunted --output "$out/hunted-10x-jobs" --backend wasm \
    --rust-jobs compare --unit-multiplier 10 "${common[@]}"
"${run[@]}" flove scripted --output "$out/flove-combat-10x-jobs" --backend wasm \
    --rust-jobs compare --unit-multiplier 10 \
    --input "$project/verification/perf/scenarios/flove-mushrooms.txt" "${common[@]}"
"${run[@]}" gravitas effects --output "$out/fire-10-jobs" --backend wasm \
    --rust-jobs compare --effects-multiplier 10 "${common[@]}"
