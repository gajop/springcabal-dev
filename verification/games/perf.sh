#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == tests ]]; then
    exec python3 -m unittest discover -s "$(dirname -- "${BASH_SOURCE[0]}")/../perf" -p 'test_*.py'
fi
exec python3 "$(dirname -- "${BASH_SOURCE[0]}")/../perf/run.py" "$@"
