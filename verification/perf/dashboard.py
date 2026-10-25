#!/usr/bin/env python3
"""Build the portable HTML benchmark explorer from saved verification evidence.

No timings are invented or rerun. Replicates, frame traces, observed worlds and
sampled stacks retain their separate provenance and measurement roles.
"""
import argparse
import base64
from collections import defaultdict
import csv
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import statistics

import report

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
SCENES = [
    ('hunted', 'hunted', 'Hunted', 'Normal', 'hunted-lua-rust-w4', 'hunted', 'hunted-1x'),
    ('hunted10', 'hunted', 'Hunted', '10× initial units', 'hunted-10x-lua-rust-w4', 'hunted-10x', 'hunted-10x'),
    ('flove', 'flove', 'Flove', '350 mushrooms', 'flove-combat-lua-rust-w4', 'flove-combat', 'flove-combat-1x'),
    ('flove10', 'flove', 'Flove', '3,500 mushrooms', 'flove-combat-10x-lua-rust-w4', 'flove-combat-10x', 'flove-combat-10x'),
    ('ttld', 'ttld', 'To the Last Drop', 'Shadows on · normal', 'ttld-shadows-1x-w4', None, 'ttld-shadows-1x'),
    ('ttld10', 'ttld', 'To the Last Drop', 'Shadows on · 10×', 'ttld-shadows-10x-w4', None, 'ttld-shadows-10x'),
    ('area17', 'area17', 'Area 17', 'Normal', 'area17-1x-w4', None, 'area17-1x'),
    ('area172', 'area17', 'Area 17', '2× initial scene', 'area17-2x-w4', None, 'area17-2x'),
    ('fire1', 'gravitas', 'Gravitas fire', '1 emitter pair', 'fire-1-lua-rust-w4', 'fire-1', 'fire-1'),
    ('fire10', 'gravitas', 'Gravitas fire', '10 emitter pairs', 'fire-10-lua-rust-w4', 'fire-10', 'fire-10'),
    ('fire100', 'gravitas', 'Gravitas fire', '100 pairs · different caps', 'fire-100-lua-rust-w4', 'fire-100', None),
]
TRACE_FIELDS = ['frame', 'sim_ms', 'draw_ms', 'sim_lua_ms', 'sim_wasm_ms', 'sim_import_ms',
                'draw_lua_ms', 'draw_wasm_ms', 'draw_import_ms', 'units', 'projectiles', 'particles']


def read(path):
    return json.loads(path.read_text())


def asset(out, key, value):
    encoded = json.dumps(value, separators=(',', ':'), ensure_ascii=True).encode()
    compressed = gzip.compress(encoded, compresslevel=6, mtime=0)
    file = out/(key+'.js')
    file.parent.mkdir(parents=True, exist_ok=True)
    file.write_text('window.SC_ASSET('+json.dumps(key)+','+json.dumps(base64.b64encode(compressed).decode())+');\n')
    return {'key': key, 'url': key+'.js', 'sha256': hashlib.sha256(encoded).hexdigest(),
            'json_bytes': len(encoded), 'gzip_bytes': len(compressed)}


def trace(directory):
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
            raise ValueError(f'Missing frame in {directory}: {frame}')
        sim, draw = kinds['sim'], kinds['draw']
        values = [frame, float(sim['elapsed_us'])/1000, float(draw['elapsed_us'])/1000]
        for row in (sim, draw):
            values += [float(row[k])/1000 for k in ('lua_us', 'wasm_us', 'import_us')]
        values += [int(sim[k]) for k in ('units', 'projectiles', 'particles')]
        result.append([round(v, 6) if isinstance(v, float) else v for v in values])
    if len(result) != 600:
        raise ValueError(f'Expected 600 measured frames: {directory}')
    return result


def world(path):
    with path.open() as stream:
        rows = [json.loads(line) for line in stream]
    header, ending = rows[0], rows[-1]
    samples = [r for r in rows if r['type'] == 'sample']
    if (header.get('format') != 'springcabal-world' or ending['type'] != 'end'
            or ending['samples'] != len(samples) or ending['frame'] != samples[-1]['frame']):
        raise ValueError(f'Incomplete world recording: {path}')
    # Delta snapshots retain every observation, including ID reuse or team changes.
    # Static scenery otherwise defeats gzip's 32 KiB history in crowded scenes.
    previous = {}
    packed = []
    for sample in samples:
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
        previous = current
    return {'header': header, 'encoding': 'delta-v2-centi', 'samples': packed, 'ending': ending}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--timings', type=Path, required=True)
    parser.add_argument('--recordings', type=Path, required=True)
    parser.add_argument('--profiles', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--videos', type=Path, help='capture-video.sh output directory')
    parser.add_argument('--followup', type=Path, help='GPU-guarded TTLD recheck, kept separate from the original campaign')
    args = parser.parse_args()
    args.timings = args.timings.resolve()
    args.recordings = args.recordings.resolve()
    args.profiles = args.profiles.resolve()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    data = {'schema': 1, 'audit': read(args.timings/'final-audit.json'), 'scenes': [],
            'trace_fields': TRACE_FIELDS, 'runs': {}, 'profiles': [], 'recordings': [],
            'optimization': list(csv.DictReader((HERE/'both-backends-2026-10-25.csv').open()))}
    language = {r['campaign']: r for r in report.paired_summary(args.timings)}
    jobs = {r['campaign']: r for r in report.paired_summary(args.timings, jobs=True)}
    for sid, game, title, load, control, job, capture in SCENES:
        scene = {'id': sid, 'game': game, 'title': title, 'load': load,
                 'language': language[control], 'jobs': {}, 'capture': capture,
                 'different_cap': sid == 'fire100'}
        campaigns = [control]
        if job:
            for width in (1, 4):
                key = f'{job}-jobs-w{width}'
                scene['jobs'][str(width)] = jobs[key]
                campaigns.append(key)
        for campaign in campaigns:
            pair_status = {}
            paths = sorted((args.timings/campaign).glob('*/result.json'))
            for path in paths:
                result = read(path)
                pair_status.setdefault(result['repeat'], []).append(result)
            accepted = {r for r, pair in pair_status.items()
                        if len(pair) == 2 and all(p['ok'] and not p['contended'] and report.is_timing(p) for p in pair)}
            ids = []
            for path in paths:
                result = read(path)
                rid = campaign+'/'+path.parent.name
                key = 'traces/'+rid.replace('/', '--')
                frames = trace(path.parent)
                result['trace'] = asset(out, key, frames)
                result['means'] = {field: round(statistics.mean(row[i] for row in frames), 6)
                                   for i, field in enumerate(TRACE_FIELDS) if i}
                result['pair_accepted'] = result['repeat'] in accepted
                result['id'] = rid
                result['evidence_path'] = str(path.parent.relative_to(PROJECT))
                data['runs'][rid] = result
                ids.append(rid)
            if campaign == control:
                scene['language']['run_ids'] = ids
            else:
                width = campaign.rsplit('w', 1)[1]
                scene['jobs'][width]['run_ids'] = ids
        data['scenes'].append(scene)
    capture_to_scene = {s['capture']: s['id'] for s in data['scenes'] if s['capture']}
    for path in sorted(args.recordings.glob('**/world.jsonl')):
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
        key = 'profiles/'+case+'--'+path.parent.name
        profile = read(path)
        data['profiles'].append(dict(asset(out, key, profile), scene=sid,
            backend=result['backend'], jobs=result['rust_jobs'], samples=profile['samples'],
            source=str(path.relative_to(PROJECT))))
    for source in (HERE/'web').iterdir():
        if source.is_file():
            shutil.copyfile(source, out/source.name)
    if args.videos:
        clips = read(args.videos/'videos.json')
        (out/'videos').mkdir(exist_ok=True)
        for clip in clips:
            shutil.copyfile(args.videos/clip['file'], out/clip['url'])
        data['videos'] = clips
    if args.followup:
        checked = [read(p) for p in args.followup.glob('**/result.json')]
        data['followup'] = {'rows': report.paired_summary(args.followup),
                            'completed_runs': sum(r['ok'] for r in checked),
                            'gpu_overlap_runs': sum(r.get('gpu_contended', False) for r in checked),
                            'guarded_runs': sum(r.get('gpu_process_guard', False) for r in checked),
                            'source': str(args.followup.resolve().relative_to(PROJECT))}
    for name in ('jobs-comparison-2026-10-26.csv', 'jobs-lua-controls-2026-10-26.csv', 'both-backends-2026-10-25.csv'):
        shutil.copyfile(HERE/name, out/name)
    (out/'data.json').write_text(json.dumps(data, separators=(',', ':'))+'\n')
    (out/'data.js').write_text('window.SC_DATA='+json.dumps(data, separators=(',', ':'))+';\n')
    print(f'{len(data["runs"])} timing runs, {len(data["recordings"])} recordings, {len(data["profiles"])} profiles → {out}')


if __name__ == '__main__':
    main()
