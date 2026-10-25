#!/usr/bin/env bash
# Serve the generated benchmark explorer with the same in-ctrl static server
# used for Ship Game's reports. No npm install or engine update is performed.
set -euo pipefail
project=$(cd -- "$(dirname -- "$0")/../.." && pwd)
site=${1:-"$project/docs/benchmarks/2026-10-26"}
port=${2:-8784}
for dir in "${IN_CTRL_DIR:-}" "$HOME/projects/in-ctrl" "$HOME/worktrees/in-ctrl-layout"; do
    if [[ -n "$dir" && -f "$dir/bin/in-ctrl.mjs" && -d "$dir/node_modules" ]]; then
        exec node "$dir/bin/in-ctrl.mjs" --root "$project" site serve "$site" \
            --host 127.0.0.1 --port "$port" --no-comments
    fi
done
echo "in-ctrl not found. Set IN_CTRL_DIR, or serve $site with any static HTTP server." >&2
exit 1
