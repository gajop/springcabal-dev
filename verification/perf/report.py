#!/usr/bin/env python3
"""Summarize paired perf evidence without converting CPU times into FPS."""
import argparse
import csv
import json
from pathlib import Path
import statistics
import run as runner


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
            'window_wall_ms_per_frame': median(r.get('window_wall_ms_per_frame') for r in good),
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


def paired_summary(root):
    groups = {}
    for path in sorted(root.glob('**/result.json')):
        result = json.loads(path.read_text())
        if 'repeat' not in result:
            continue
        key = str(path.parent.parent.relative_to(root)), result['game']
        groups.setdefault(key, {}).setdefault(result['repeat'], {})[result['backend']] = result
    output = []
    for (campaign, game), repeats in groups.items():
        pairs = [pair for pair in repeats.values() if set(pair) == {'lua', 'wasm'}
                 and all(r['ok'] and not r['contended'] for r in pair.values())]
        row = {'campaign': campaign, 'game': game, 'measured_pairs': len(pairs),
               'attempted_pairs': len(repeats), 'excluded_pairs': len(repeats)-len(pairs)}
        for name, metric in [('sim', 'sim.elapsed_us'), ('draw', 'draw.elapsed_us'),
                             ('cpu', 'frame.cpu_us'), ('wall', None)]:
            for quantile in (('mean',) if metric is None else ('p50', 'p95')):
                def value(result):
                    if metric is None:
                        return result.get('window_wall_ms_per_frame')
                    number = result['metrics'].get(metric, {}).get(quantile)
                    return number/1000 if number is not None else None
                values = [(value(pair['lua']), value(pair['wasm'])) for pair in pairs]
                values = [(lua, wasm) for lua, wasm in values if lua and wasm]
                prefix = name+'_'+quantile
                for i, backend in enumerate(('lua', 'rust')):
                    row[prefix+'_'+backend+'_ms'] = statistics.median(v[i] for v in values) if values else None
                ratios = [wasm/lua for lua, wasm in values]
                row[prefix+'_paired_rust_change_pct'] = (statistics.median(ratios)-1)*100 if ratios else None
                interval = runner.confidence(ratios)
                row[prefix+'_mean_ratio_95ci_lo'] = interval[0] if interval else None
                row[prefix+'_mean_ratio_95ci_hi'] = interval[1] if interval else None
        for backend in ('lua', 'wasm'):
            row[backend+'_units_p50'] = statistics.median(pair[backend]['population']['units']['p50'] for pair in pairs) if pairs else None
        output.append(row)
    return output


def write_rows(path, rows):
    if not rows:
        return
    with path.with_suffix('.csv').open('w') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)
    path.with_suffix('.json').write_text(json.dumps(rows, indent=2)+'\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    rows = summarize(args.output)
    if not rows:
        parser.error('no result.json files found')
    write_rows(args.output/'summary', rows)
    write_rows(args.output/'paired-summary', paired_summary(args.output))
    for row in rows:
        print(f"{row['campaign']:24} {row['game']:8} {row['backend']:4} "
              f"{row['completed']}/{row['attempted']} complete; "
              f"sim={row['sim_p50_ms']} ms draw={row['draw_p50_ms']} ms units={row['units_p50']}")


if __name__ == '__main__':
    main()
