#!/usr/bin/env python3
"""Summarize paired perf evidence without converting CPU times into FPS."""
import argparse
import csv
import json
from pathlib import Path
import statistics
import run as runner


def is_timing(result):
    return result.get('rust_jobs') != 'check' and not result.get('instrumented', False)


def summarize(root):
    groups = {}
    for path in sorted(root.glob('**/result.json')):
        result = json.loads(path.read_text())
        campaign = str(path.parent.parent.relative_to(root))
        mode = result.get('rust_jobs', '')
        key = campaign, result['game'], result['backend'], mode
        groups.setdefault(key, []).append(result)
    rows = []
    for (campaign, game, backend, mode), runs in groups.items():
        good = [r for r in runs if r['ok']]
        timed = [r for r in good if not r['contended'] and is_timing(r)]
        def median(values):
            values = [v for v in values if v is not None]
            return statistics.median(values) if values else None
        def metric(name, quantile='p50', divisor=1):
            value = median(r['metrics'].get(name, {}).get(quantile) for r in timed)
            return value / divisor if value is not None else None
        rows.append({
            'campaign': campaign, 'game': game, 'backend': backend,
            'rust_jobs': mode,
            'completed': len(good), 'attempted': len(runs),
            'timed_runs': len(timed),
            'contended_runs': sum(r['contended'] for r in runs),
            'units_p50': median(r['population']['units']['p50'] for r in good),
            'sim_p50_ms': metric('sim.elapsed_us', divisor=1000),
            'sim_p95_ms': metric('sim.elapsed_us', 'p95', 1000),
            'frame_cpu_p50_ms': metric('frame.cpu_us', divisor=1000),
            'frame_cpu_p95_ms': metric('frame.cpu_us', 'p95', 1000),
            'window_wall_ms_per_frame': median(r.get('window_wall_ms_per_frame') for r in timed),
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


def paired_summary(root, jobs=False):
    groups = {}
    for path in sorted(root.glob('**/result.json')):
        result = json.loads(path.read_text())
        if (result.get('comparison_kind') == 'jobs') != jobs:
            continue
        if 'repeat' not in result:
            continue
        key = str(path.parent.parent.relative_to(root)), result['game']
        variant = result['rust_jobs'] if jobs else result['backend']
        groups.setdefault(key, {}).setdefault(result['repeat'], {})[variant] = result
    output = []
    for (campaign, game), repeats in groups.items():
        left, right = ('off', 'on') if jobs else ('lua', 'wasm')
        names = ('off', 'on') if jobs else ('lua', 'rust')
        change = 'jobs' if jobs else 'rust'
        pairs = [pair for pair in repeats.values() if set(pair) == {left, right}
                 and all(r['ok'] and not r['contended'] and is_timing(r) for r in pair.values())]
        row = {'campaign': campaign, 'game': game, 'measured_pairs': len(pairs),
               'attempted_pairs': len(repeats), 'excluded_pairs': len(repeats)-len(pairs)}
        if jobs:
            row['worker_threads'] = next(iter(next(iter(repeats.values())).values())).get('worker_threads')
            row['on_active_runs'] = sum(pair['on'].get('jobs_active', False) for pair in pairs)
            equalities = []
            for repeat, pair in repeats.items():
                if any(pair is accepted for accepted in pairs):
                    path = root/campaign/f'{game}-{repeat:02d}-equivalence.json'
                    if path.exists():
                        equalities.append(json.loads(path.read_text()))
            row['state_matched_pairs'] = sum(e['first_state_divergence'] is None and e['alive_counters_match'] for e in equalities)
            row['events_matched_pairs'] = sum(all(v['off'] == v['on'] for v in e['event_totals'].values()) for e in equalities)
        for name, metric in [('sim', 'sim.elapsed_us'), ('draw', 'draw.elapsed_us'),
                             ('cpu', 'frame.cpu_us'), ('wall', None)]:
            for quantile in (('mean',) if metric is None else ('p50', 'p95')):
                def value(result):
                    if metric is None:
                        return result.get('window_wall_ms_per_frame')
                    number = result['metrics'].get(metric, {}).get(quantile)
                    return number/1000 if number is not None else None
                values = [(value(pair[left]), value(pair[right])) for pair in pairs]
                values = [(lua, wasm) for lua, wasm in values if lua and wasm]
                prefix = name+'_'+quantile
                for i, backend in enumerate(names):
                    row[prefix+'_'+backend+'_ms'] = statistics.median(v[i] for v in values) if values else None
                ratios = [wasm/lua for lua, wasm in values]
                row[prefix+'_paired_'+change+'_change_pct'] = (statistics.median(ratios)-1)*100 if ratios else None
                interval = runner.confidence(ratios)
                row[prefix+'_mean_ratio_95ci_lo'] = interval[0] if interval else None
                row[prefix+'_mean_ratio_95ci_hi'] = interval[1] if interval else None
        for backend in (left, right):
            row[backend+'_units_p50'] = statistics.median(pair[backend]['population']['units']['p50'] for pair in pairs) if pairs else None
        output.append(row)
    return output


def source_optimization_summary(manifest, project):
    """Compare the same backend before/after using complete four-run rounds."""
    output = []
    for experiment in manifest:
        backends = experiment.get('backends', ['lua', 'wasm'])
        if not backends or len(set(backends)) != len(backends) or not set(backends) <= {'lua', 'wasm'}:
            raise ValueError('Source A/B backends must select lua, wasm, or both')
        rounds = []
        attempted = 0
        for candidates in experiment['rounds']:
            phases = {}
            for phase in ('before', 'after'):
                choices = []
                for relative in candidates[phase]:
                    directory = project/relative
                    provenance = directory/'provenance.json'
                    if not provenance.exists():
                        continue
                    stamp = json.loads(provenance.read_text())
                    pairs = {}
                    for path in sorted(directory.glob('*/result.json')):
                        result = json.loads(path.read_text())
                        if result['backend'] not in backends:
                            continue
                        pairs.setdefault(result['repeat'], {})[result['backend']] = (result, path)
                    attempted += len(pairs)
                    for pair in pairs.values():
                        if set(pair) != set(backends):
                            continue
                        if all(r['ok'] and not r['contended'] and is_timing(r) for r, _ in pair.values()):
                            choices.append((pair, stamp))
                if choices:
                    phases[phase] = choices[0]
            if set(phases) != {'before', 'after'}:
                continue
            before, after = phases['before'], phases['after']
            for key in ('input_sha256', 'effective_input_sha256'):
                if before[1].get(key) != after[1].get(key):
                    raise ValueError(f'Source A/B has different {key}')
            for key in ('worker_threads', 'unit_multiplier', 'effects_multiplier', 'warmup', 'frames', 'rust_jobs'):
                if before[1].get('args', {}).get(key) != after[1].get('args', {}).get(key):
                    raise ValueError(f'Source A/B has different {key}')
            if before[1]['engine_sha256'] != after[1]['engine_sha256']:
                raise ValueError('Source A/B must use the same engine binary')
            for backend in backends:
                a, b = before[0][backend][0], after[0][backend][0]
                for key in ('game', 'worker_threads', 'cpu_affinity', 'unit_multiplier', 'effects_multiplier', 'fire_renderer', 'callback_timers'):
                    if a.get(key) != b.get(key):
                        raise ValueError(f'Source A/B has different {key}')
            rounds.append(phases)
        for backend in backends:
            row = {k: v for k, v in experiment.items() if k != 'rounds'}
            row.update(backend=backend, measured_rounds=len(rounds), planned_rounds=len(experiment['rounds']),
                       attempted_phase_pairs=attempted, evidence=[])
            for name, metric in (('wall', None), ('sim', 'sim.elapsed_us'), ('draw', 'draw.elapsed_us')):
                values = []
                for phases in rounds:
                    results = [phases[p][0][backend][0] for p in ('before', 'after')]
                    pair = [r.get('window_wall_ms_per_frame') if metric is None else
                            r['metrics'][metric]['p50']/1000 for r in results]
                    if all(v is not None and v > 0 for v in pair):
                        values.append(pair)
                ratios = [b/a for a, b in values]
                row[name+'_before_ms'] = statistics.median(a for a, _ in values) if values else None
                row[name+'_after_ms'] = statistics.median(b for _, b in values) if values else None
                row[name+'_change_pct'] = (statistics.median(ratios)-1)*100 if ratios else None
                row[name+'_mean_ratio_95ci'] = runner.confidence(ratios) if ratios else None
            for phases in rounds:
                row['evidence'].append({phase: str(phases[phase][0][backend][1].parent.relative_to(project))
                                        for phase in ('before', 'after')})
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
    write_rows(args.output/'jobs-summary', paired_summary(args.output, jobs=True))
    for row in rows:
        print(f"{row['campaign']:24} {row['game']:8} {row['backend']:4} {row['rust_jobs']:3} "
              f"{row['completed']}/{row['attempted']} complete; "
              f"sim={row['sim_p50_ms']} ms draw={row['draw_p50_ms']} ms units={row['units_p50']}")


if __name__ == '__main__':
    main()
