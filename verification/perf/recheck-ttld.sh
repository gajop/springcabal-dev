#!/usr/bin/env bash
# Existing TTLD input fixtures, with explicit competing-GPU-process exclusion.
set -euo pipefail
project=$(cd -- "$(dirname -- "$0")/../.." && pwd)
out=${1:?Usage: recheck-ttld.sh /absolute/output [runner options]}
shift
for multiplier in 1 10; do
    for shadows in on off; do
        input="$project/verification/perf/scenarios/ttld-shadows.txt"
        [[ "$shadows" != off ]] || input="$project/verification/perf/scenarios/ttld-shadows-off.txt"
        "$project/verification/verify" perf ttld scripted \
            --input "$input" --output "$out/ttld-${multiplier}x-shadows-$shadows" \
            --unit-multiplier "$multiplier" --frame-step --worker-threads 4 \
            --cpu-pressure-scope cgroup --wait-for-idle --wait-for-gpu-idle \
            --repeats 5 --timeout 300 --max-minutes 40 "$@"
    done
done
python3 "$project/verification/perf/report.py" "$out"
