#!/usr/bin/env python3
"""Summarize paired perf evidence without converting CPU times into FPS."""
import argparse
import csv
import json
from pathlib import Path
import statistics


def summarize(root):
    groups = {}
    for path in sorted(root.glob('**/result.json')):
        result = json.loads(path.read_text())
        campaign = str(path.parent.parent.relative_to(root))
        key = campaign, result['game'], result['backend']
        groups.setdefault(key, []).append(result)
    rows = []
    for (campaign, game, backend), runs in groups.items():
        good = [r for r in runs if r['ok']]
        def median(values):
            values = [v for v in values if v is not None]
            return statistics.median(values) if values else None
        def metric(name, quantile='p50', divisor=1):
            value = median(r['metrics'].get(name, {}).get(quantile) for r in good)
            return value / divisor if value is not None else None
        rows.append({
            'campaign': campaign, 'game': game, 'backend': backend,
            'completed': len(good), 'attempted': len(runs),
            'contended_runs': sum(r['contended'] for r in runs),
            'units_p50': median(r['population']['units']['p50'] for r in good),
            'sim_p50_ms': metric('sim.elapsed_us', divisor=1000),
            'sim_p95_ms': metric('sim.elapsed_us', 'p95', 1000),
            'frame_cpu_p50_ms': metric('frame.cpu_us', divisor=1000),
            'frame_cpu_p95_ms': metric('frame.cpu_us', 'p95', 1000),
            'draw_p50_ms': metric('draw.elapsed_us', divisor=1000),
            'draw_p95_ms': metric('draw.elapsed_us', 'p95', 1000),
            'sim_lua_p50_ms': metric('sim.lua_us', divisor=1000),
            'sim_wasm_p50_ms': metric('sim.wasm_us', divisor=1000),
            'sim_import_p50_ms': metric('sim.import_us', divisor=1000),
            'sim_imports_p50': metric('sim.imports'),
            'draw_imports_p50': metric('draw.imports'),
            'sampled_peak_rss_mib': (lambda v: v/1024 if v is not None else None)(
                median(r.get('sampled_peak_rss_kib') for r in good)),
        })
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    rows = summarize(args.output)
    if not rows:
        parser.error('no result.json files found')
    with (args.output/'summary.csv').open('w') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    (args.output/'summary.json').write_text(json.dumps(rows, indent=2)+'\n')
    for row in rows:
        print(f"{row['campaign']:24} {row['game']:8} {row['backend']:4} "
              f"{row['completed']}/{row['attempted']} complete; "
              f"sim={row['sim_p50_ms']} ms draw={row['draw_p50_ms']} ms units={row['units_p50']}")


if __name__ == '__main__':
    main()
