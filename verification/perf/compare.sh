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
for game in hunted flove ttld; do
    measure "$game-10x" "$game" autonomous --frame-step --unit-multiplier 10 "${options[@]}"
done
# A full-scene clone exceeds Area 17's current limits. One pair records that
# failure without repeatedly allocating to the Lua memory limit.
measure area17-10x area17 autonomous --frame-step --unit-multiplier 10 "${options[@]}" --repeats 1
for count in 0 1 10; do
    measure "gravitas-effects-$count" gravitas effects --effects-multiplier "$count" "${options[@]}"
done
python3 "$root/verification/perf/report.py" "$output"
exit "$status"
