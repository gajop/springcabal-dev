#!/usr/bin/env python3
"""Build the portable HTML benchmark explorer from saved verification evidence.

No timings are invented or rerun. Replicates, frame traces, observed worlds and
sampled stacks retain their separate provenance and measurement roles.
"""
import argparse
import base64
from collections import defaultdict
import csv
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import statistics

import report
from storage import open_world

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
SCENES = [
    ('hunted', 'hunted', 'Hunted', 'Normal', 'hunted-lua-rust-w1', 'hunted', 'hunted-1x'),
    ('hunted10', 'hunted', 'Hunted', '10× initial units', 'hunted-10x-lua-rust-w1', 'hunted-10x', 'hunted-10x'),
    ('flove', 'flove', 'Flove', '350 mushrooms', 'flove-combat-lua-rust-w1', 'flove-combat', 'flove-combat-1x'),
    ('flove10', 'flove', 'Flove', '3,500 mushrooms', 'flove-combat-10x-lua-rust-w1', 'flove-combat-10x', 'flove-combat-10x'),
    ('ttld', 'ttld', 'To the Last Drop', 'Shadows on · normal', 'ttld-shadows-1x-w1', None, 'ttld-shadows-1x'),
    ('ttld10', 'ttld', 'To the Last Drop', 'Shadows on · 10×', 'ttld-shadows-10x-w1', None, 'ttld-shadows-10x'),
    ('area17', 'area17', 'Area 17', 'Normal', 'area17-1x-w1', None, 'area17-1x'),
    ('area172', 'area17', 'Area 17', '2× initial scene', 'area17-2x-w1', None, 'area17-2x'),
    ('fire1', 'gravitas', 'Gravitas fire', '1 emitter pair', 'fire-1-lua-rust-w4', 'fire-1-cpu', 'fire-1'),
    ('fire10', 'gravitas', 'Gravitas fire', '10 emitter pairs', 'fire-10-lua-rust-w4', 'fire-10-cpu', 'fire-10'),
    ('fire100', 'gravitas', 'Gravitas fire', '100 emitter pairs', 'fire-100-lua-rust-w4', 'fire-100-cpu', 'fire-100'),
    ('mycube', 'mycube', 'My Cube', 'Normal', 'mycube-1x-w1', None, 'mycube-1x'),
    ('partsneeded', 'partsneeded', 'Parts Needed', 'Normal', 'partsneeded-1x-w1', None, 'partsneeded-1x'),
]
TRACE_FIELDS = ['frame', 'sim_ms', 'draw_ms', 'sim_lua_ms', 'sim_wasm_ms', 'sim_import_ms',
                'draw_lua_ms', 'draw_wasm_ms', 'draw_import_ms', 'units', 'projectiles', 'particles']


def read(path):
    return json.loads(path.read_text())


def scene_summary(summaries, campaign, game, allow_incomplete=False):
    if campaign in summaries:
        return summaries[campaign]
    if not allow_incomplete:
        raise ValueError(f'Missing timing campaign: {campaign}')
    return {'campaign': campaign, 'game': game, 'measured_pairs': 0,
            'attempted_pairs': 0, 'excluded_pairs': 0, 'run_ids': []}


def asset(out, key, value):
    encoded = json.dumps(value, separators=(',', ':'), ensure_ascii=True).encode()
    compressed = gzip.compress(encoded, compresslevel=6, mtime=0)
    file = out/(key+'.js')
    file.parent.mkdir(parents=True, exist_ok=True)
    file.write_text('window.SC_ASSET('+json.dumps(key)+','+json.dumps(base64.b64encode(compressed).decode())+');\n')
    return {'key': key, 'url': key+'.js', 'sha256': hashlib.sha256(encoded).hexdigest(),
            'json_bytes': len(encoded), 'gzip_bytes': len(compressed)}


def trace(directory, strict=True):
    if not (directory/'frames.csv').exists() and not strict:
        return []
    with (directory/'frames.csv').open() as stream:
        rows = list(csv.DictReader(stream))
    frames = defaultdict(dict)
    for row in rows:
        frame = int(row['frame'])
        if 300 <= frame < 900:
            frames[frame][row['kind']] = row
    result = []
    for frame, kinds in sorted(frames.items()):
        if set(kinds) != {'sim', 'draw'}:
            if strict:
                raise ValueError(f'Missing frame in {directory}: {frame}')
            continue
        sim, draw = kinds['sim'], kinds['draw']
        values = [frame, float(sim['elapsed_us'])/1000, float(draw['elapsed_us'])/1000]
        for row in (sim, draw):
            values += [float(row[k])/1000 for k in ('lua_us', 'wasm_us', 'import_us')]
        values += [int(sim[k]) for k in ('units', 'projectiles', 'particles')]
        result.append([round(v, 6) if isinstance(v, float) else v for v in values])
    if strict and len(result) != 600:
        raise ValueError(f'Expected 600 measured frames: {directory}')
    return result


def world(path):
    # Detailed snapshots can be gigabytes: discard diagnostic-only fields one
    # sample at a time instead of keeping their parsed copies in memory.
    previous, packed = {}, []
    header = ending = None
    last_frame = None
    with open_world(path) as stream:
        for line in stream:
            sample = json.loads(line)
            if ending is not None:
                raise ValueError(f'Data follows world ending: {path}')
            if sample['type'] == 'header':
                header = sample
                continue
            if sample['type'] == 'end':
                ending = sample
                continue
            if sample['type'] != 'sample':
                continue
            current = {u[0]: u[:3] + [round(v*100) for v in u[3:]] for u in sample['units']}
            changed = []
            for uid, unit in current.items():
                before = previous.get(uid)
                if before == unit:
                    continue
                if before is None or any(before[i] != unit[i] for i in (1, 2, 6)):
                    changed.append(unit)
                else:
                    changed.append([uid] + [unit[i]-before[i] for i in (3, 4, 5)])
            removed = sorted(previous.keys() - current.keys())
            packed.append([sample['frame'], changed, removed, sample['projectiles']])
            previous, last_frame = current, sample['frame']
    if (not header or header.get('format') != 'springcabal-world' or not ending
            or not packed or ending['samples'] != len(packed) or ending['frame'] != last_frame):
        raise ValueError(f'Incomplete world recording: {path}')
    return {'header': header, 'encoding': 'delta-v2-centi', 'samples': packed, 'ending': ending}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--timings', type=Path, required=True)
    parser.add_argument('--recordings', type=Path, required=True)
    parser.add_argument('--profiles', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--videos', type=Path, help='capture-video.sh output directory')
    parser.add_argument('--optimizations', type=Path, help='same-behavior source A/B experiment manifest')
    parser.add_argument('--allow-incomplete', action='store_true',
                        help='Show pending scenes while a campaign is running; never fill missing measurements')
    args = parser.parse_args()
    args.timings = args.timings.resolve()
    args.recordings = args.recordings.resolve()
    args.profiles = args.profiles.resolve()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    data = {'schema': 1, 'audit': {}, 'scenes': [],
            'trace_fields': TRACE_FIELDS, 'runs': {}, 'profiles': [], 'recordings': [],
            'optimization': []}
    if args.optimizations:
        data['optimization'] = report.source_optimization_summary(read(args.optimizations), PROJECT)
        report.write_rows(out/'optimizations', [{k: v for k, v in row.items() if k != 'evidence'} for row in data['optimization']])
    language = {r['campaign']: r for r in report.paired_summary(args.timings)}
    jobs = {r['campaign']: r for r in report.paired_summary(args.timings, jobs=True)}
    for sid, game, title, load, control, job, capture in SCENES:
        scene = {'id': sid, 'game': game, 'title': title, 'load': load,
                 'language': scene_summary(language, control, game, args.allow_incomplete), 'jobs': {}, 'capture': capture,
                 'different_cap': False, 'jobs_renderer': 'CPU reference' if game == 'gravitas' else 'production'}
        campaigns = [(control, scene['language'])]
        secondary = control[:-1]+'4' if control.endswith('w1') else None
        if secondary in language:
            scene['language4'] = language[secondary]
            campaigns.append((secondary, scene['language4']))
        if job:
            for width in (1, 4):
                key = f'{job}-jobs-w{width}'
                if key not in jobs:
                    continue
                scene['jobs'][str(width)] = jobs[key]
                campaigns.append((key, scene['jobs'][str(width)]))
        for campaign, summary in campaigns:
            if not (args.timings/campaign/'provenance.json').exists() and args.allow_incomplete:
                continue
            stamp = read(args.timings/campaign/'provenance.json')
            summary['runtime'] = {key: stamp.get(key) for key in
                                  ('engine_commit', 'engine_sha256', 'engine_source')}
            pair_status = {}
            paths = sorted((args.timings/campaign).glob('*/result.json'))
            for path in paths:
                result = read(path)
                pair_status.setdefault(result['repeat'], []).append(result)
            accepted = {r for r, pair in pair_status.items()
                        if len(pair) == 2 and all(p['ok'] and not p['contended'] and report.is_timing(p) for p in pair)}
            reasons = {}
            for repeat, pair in pair_status.items():
                why = []
                if len(pair) != 2: why.append('missing counterpart')
                if any(not p['ok'] for p in pair): why.append('failed run')
                if any(p.get('gpu_contended') for p in pair): why.append('GPU overlap')
                if any(p['contended'] and not p.get('gpu_contended') for p in pair): why.append('CPU pressure')
                if any(not report.is_timing(p) for p in pair): why.append('instrumented')
                reasons[repeat] = why
            ids = []
            for path in paths:
                result = read(path)
                rid = campaign+'/'+path.parent.name
                key = 'traces/'+rid.replace('/', '--')
                frames = trace(path.parent, strict=result['ok'])
                result['trace_frames'] = len(frames)
                result['trace'] = asset(out, key, frames)
                result['means'] = {field: round(statistics.mean(row[i] for row in frames), 6) if frames else None
                                   for i, field in enumerate(TRACE_FIELDS) if i}
                result['pair_accepted'] = result['repeat'] in accepted
                result['pair_rejection_reasons'] = reasons[result['repeat']]
                result['id'] = rid
                result['evidence_path'] = str(path.parent.relative_to(PROJECT))
                data['runs'][rid] = result
                ids.append(rid)
            summary['run_ids'] = ids
        data['scenes'].append(scene)
    capture_to_scene = {s['capture']: s['id'] for s in data['scenes'] if s['capture']}
    for path in sorted([*args.recordings.glob('**/world.jsonl'), *args.recordings.glob('**/world.jsonl.gz')]):
        case = path.parent.parent.name
        sid = capture_to_scene.get(case)
        if not sid:
            sid = {'hunted-10x-jobs': 'hunted10', 'flove-combat-10x-jobs': 'flove10'}.get(case)
        if not sid:
            continue
        result = read(path.parent/'result.json')
        if not result['ok']:
            raise ValueError(f'Failed recording: {path}')
        key = 'recordings/'+case+'--'+path.parent.name
        data['recordings'].append(dict(asset(out, key, world(path)), scene=sid,
            backend=result['backend'], jobs=result['rust_jobs'],
            renderer=result['renderer'], source=str(path.relative_to(PROJECT))))
    for path in sorted(args.profiles.glob('**/profile.json')):
        case = path.parent.parent.name
        sid = capture_to_scene.get(case)
        if not sid:
            sid = {'hunted-10x-jobs': 'hunted10', 'flove-combat-10x-jobs': 'flove10', 'fire-10-jobs': 'fire10'}.get(case)
        if not sid:
            continue
        result = read(path.parent/'result.json')
        if result.get('world_recording'):
            raise ValueError('Profiles must be separate from the world observer')
        if not result['ok'] or result['contended']:
            continue
        key = 'profiles/'+case+'--'+path.parent.name
        profile = read(path)
        data['profiles'].append(dict(asset(out, key, profile), scene=sid,
            backend=result['backend'], jobs=result['rust_jobs'], samples=profile['samples'],
            fire_renderer=result.get('fire_renderer'),
            source=str(path.relative_to(PROJECT))))
    for source in (HERE/'web').iterdir():
        if source.is_file():
            shutil.copyfile(source, out/source.name)
    if args.videos:
        clips = read(args.videos/'videos.json')
        (out/'videos').mkdir(exist_ok=True)
        for clip in clips:
            clip['scene'] = capture_to_scene.get(clip['case'])
            shutil.copyfile(args.videos/clip['file'], out/clip['url'])
        data['videos'] = clips
    report.write_rows(out/'language', list(language.values()))
    report.write_rows(out/'jobs', list(jobs.values()))
    saved = [read(p) for p in args.timings.glob('**/result.json')]
    provenance = [read(p) for p in args.timings.glob('**/provenance.json')]
    sources = {}
    for path in args.timings.glob('**/*-content.json'):
        sources[path.stem.removesuffix('-content')+':'+path.parent.name] = read(path)
    data['audit'] = {
        'generated_at': datetime.now(timezone.utc).isoformat(timespec='seconds'),
        'primary_scenes_at_five_pairs': sum(s['language']['measured_pairs'] >= 5 for s in data['scenes']),
        'primary_scene_count': len(data['scenes']),
        'callback_timers': sorted({r.get('callback_timers', 'on') for r in saved}),
        'runs': len(saved), 'complete': sum(r['ok'] for r in saved),
        'accepted_pairs': sum(r['measured_pairs'] for r in [*language.values(), *jobs.values()]),
        'attempted_pairs': sum(r['attempted_pairs'] for r in [*language.values(), *jobs.values()]),
        'contended': sum(r['contended'] for r in saved),
        'gpu_overlap_runs': sum(r.get('gpu_contended', False) for r in saved),
        'renderers': sorted({r['renderer'] for r in saved if r.get('renderer')}),
        'rendered_frame_counts': sorted({r['rendered_measurement_frames'] for r in saved}),
        'engine_commits': sorted({p['engine_commit'] for p in provenance}),
        'engine_sha256': sorted({p['engine_sha256'] for p in provenance}),
        'cpu_affinity': sorted({tuple(r['cpu_affinity'] or []) for r in saved}),
        'source_commits': sources,
    }
    (out/'data.json').write_text(json.dumps(data, separators=(',', ':'))+'\n')
    (out/'data.js').write_text('window.SC_DATA='+json.dumps(data, separators=(',', ':'))+';\n')
    print(f'{len(data["runs"])} timing runs, {len(data["recordings"])} recordings, {len(data["profiles"])} profiles → {out}')


if __name__ == '__main__':
    main()
