#!/usr/bin/env bash
# The requested four game pairs, plus Gravitas fire rendering only.
set -euo pipefail
root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
[[ $# -ge 1 ]] || { echo 'usage: compare.sh OUTPUT_DIR [perf runner options]' >&2; exit 2; }
output=$(realpath -m -- "$1")
shift
mkdir -p "$output"
status=0
measure() {
    local name=$1 game=$2 scenario=$3
    shift 3
    "$root/verification/verify" perf "$game" "$scenario" --output "$output/$name" "$@" || status=1
}
options=("$@")
measure normal comparison autonomous --frame-step "${options[@]}"
measure flove-combat flove scripted --frame-step \
    --input "$root/verification/perf/scenarios/flove-mushrooms.txt" "${options[@]}"
for game in hunted flove ttld; do
    measure "$game-10x" "$game" autonomous --frame-step --unit-multiplier 10 "${options[@]}"
done
# The earlier 10x campaign established both backends' full-scene limits.
# Use the largest measured working case rather than repeating that failure.
measure area17-2x area17 autonomous --frame-step --unit-multiplier 2 "${options[@]}"
for count in 1 10; do
    measure "ttld-shadows-${count}x" ttld scripted --frame-step \
        --unit-multiplier "$count" \
        --input "$root/verification/perf/scenarios/ttld-shadows.txt" "${options[@]}"
done
for count in 0 1 10; do
    measure "gravitas-effects-$count" gravitas effects --effects-multiplier "$count" "${options[@]}"
done
python3 "$root/verification/perf/report.py" "$output"
exit "$status"
