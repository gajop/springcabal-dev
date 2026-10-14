#!/usr/bin/env bash
set -euo pipefail
# An isolated Xvfb session: send actual SDL input, never touch the user's desktop.
"$FLOVE_REAL_ENGINE" "$@" &
engine_pid=$!
trap 'kill "$engine_pid" 2>/dev/null || true' EXIT
for i in $(seq 1 120); do
    win=$(xdotool search --onlyvisible --pid "$engine_pid" 2>/dev/null | head -1 || true)
    if [[ -n $win ]] && grep -q 'FLOVE INPUT BOOT' "$FLOVE_INPUT_LOG"; then break; fi
    sleep .25
done
[[ -n ${win:-} ]]
xdotool windowfocus "$win"
xdotool key 1
sleep 1
xdotool key s
for i in $(seq 1 120); do
    coord=$(sed -n 's/.*FLOVE CLICK \([0-9]*\) \([0-9]*\).*/\1 \2/p' "$FLOVE_INPUT_LOG" | tail -1)
    [[ -n $coord ]] && break
    sleep .25
done
[[ -n ${coord:-} ]]
read -r x y <<< "$coord"
xdotool mousemove --window "$win" "$x" "$y"
xdotool mousedown 1
sleep .5
xdotool mouseup 1
sleep .25
xdotool mousedown 3
sleep .5
xdotool mouseup 3
wait "$engine_pid"
trap - EXIT
