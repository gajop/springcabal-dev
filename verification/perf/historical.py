#!/usr/bin/env python3
"""Export retained measurements for display, outside current timing aggregates."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
from zoneinfo import ZoneInfo

import report

PROJECT = Path(__file__).resolve().parents[2]
SOURCES = [
    'perf-runs/2026-10-30-night-v4-hunted',
    'perf-runs/2026-10-30-night-v4-unaffected',
    'perf-runs/2026-10-30-night-v6-fire',
    'perf-runs/2026-10-30-night-v6-unaffected',
]
SCENES = {
    'hunted-lua-rust-w1': 'hunted', 'hunted-10x-lua-rust-w1': 'hunted10',
    'flove-combat-lua-rust-w1': 'flove', 'flove-combat-10x-lua-rust-w1': 'flove10',
    'area17-1x-w1': 'area17', 'area17-2x-w1': 'area172',
    'ttld-shadows-1x-w1': 'ttld', 'ttld-shadows-10x-w1': 'ttld10',
    'ttld-burning-1x-w1': 'ttldburn', 'ttld-burning-10x-w1': 'ttldburn10',
    'mycube-1x-w1': 'mycube', 'partsneeded-1x-w1': 'partsneeded',
}
NOTES = {
    'hunted': ('stale', 'Older engine/source; the current engine changes job dispatch.'),
    'area17': ('stale', 'Older engine and SDK.'),
    'flove': ('superseded', 'Before marker and native spatial-index corrections; the recorded worlds diverged. These times do not isolate language cost.'),
    'ttld': ('superseded', 'Rust omitted world health bars and ordinary house ignition. These timings compare unequal rendering work.'),
    'mycube': ('superseded', 'Rust omitted the original world health-bar pass.'),
    'partsneeded': ('stale', 'Older engine and SDK; normal puzzle scene.'),
    'gravitas': ('superseded', 'Before the selected particle-renderer/lifetime/upload changes. The archived 100-emitter Lua/Rust case also had different particle caps.'),
}


def read(path):
    return json.loads(path.read_text())


def entry(row, source, game, **metadata):
    status, note = NOTES[game]
    return dict(summary=row, source=source, game=game, status=status, note=note, **metadata)


def export(project, archive):
    scenes, jobs = {}, []
    archived = read(archive)
    archive_sha = hashlib.sha256(archive.read_bytes()).hexdigest()
    for scene in archived['scenes']:
        game = scene['game']
        metadata = dict(campaign_label='26–27 October archived campaign',
                        source_sha256=archive_sha, engine_commit=None)
        scenes[scene['id']] = entry(scene['language'], str(archive.relative_to(project)), game, **metadata)
        if game == 'gravitas':
            for width, row in scene.get('jobs', {}).items():
                jobs.append(entry(row, str(archive.relative_to(project)), game,
                                  load=scene['load'], worker_threads=int(width), **metadata))
    for relative in SOURCES:
        root = project / relative
        if not root.exists():
            continue
        for is_jobs in (False, True):
            if is_jobs and root.name == '2026-10-30-night-v6-unaffected':
                continue
            for row in report.paired_summary(root, jobs=is_jobs):
                if not row['measured_pairs']:
                    continue
                campaign = root / row['campaign']
                stamp = read(campaign / 'provenance.json')
                args = stamp['args']
                files = list(campaign.glob('*/result.json'))
                saved = datetime.fromtimestamp(max(p.stat().st_mtime for p in files), ZoneInfo('Europe/Budapest'))
                value = entry(row, str(campaign.relative_to(project)), row['game'],
                              campaign_label=saved.strftime('%d %b %Y') + ' saved campaign',
                              engine_commit=stamp['engine_commit'],
                              engine_sha256=stamp['engine_sha256'],
                              resource_guard_sha256=stamp.get('resource_guard_sha256'),
                              cpu_activity_policy=stamp.get('cpu_activity_policy'),
                              worker_threads=args['worker_threads'], unit_multiplier=args['unit_multiplier'],
                              effects_multiplier=args['effects_multiplier'], fire_renderer=args['fire_renderer'],
                              provenance_sha256=hashlib.sha256((campaign / 'provenance.json').read_bytes()).hexdigest())
                if root.name == '2026-10-30-night-v6-unaffected':
                    value.update(status='stale' if row['game'] == 'area17' else 'superseded', note={
                        'area17': 'Before aligning Lua/Rust camera averaging order; replaced by the corrected-source campaign.',
                        'flove': 'Before global HUD/power publication and wisp/spire rendering alignment; the old stress HUD read a stale spire.',
                        'mycube': 'Before matching story creation/RNG order, unit mass and idle animation.',
                        'partsneeded': 'Before matching level creation, prop/gate physics, rotation and camera initialization.',
                    }[row['game']])
                if is_jobs:
                    value['load'] = ('10×' if args['unit_multiplier'] == 10 else 'Normal')
                    jobs.append(value)
                elif row['campaign'] in SCENES:
                    scenes[SCENES[row['campaign']]] = value
    games = [
        dict(game='area17', title='Area 17', code='Selected code work complete.', remaining='Fresh normal/2× comparisons, captures and profile review on aligned camera arithmetic.', expected=2),
        dict(game='hunted', title='Hunted', code='Selected Lua/Rust optimizations implemented and tested; no identified code fix pending.', remaining='All six timing configurations and matching worlds/profiles complete; final profile analysis remains.', expected=6),
        dict(game='flove', title='Flove', code='Physics/HUD fixes are public. The private renderer/spire candidate passes serial/jobs correctness checks and extended animation/effect traces.', remaining='GPU visual/wisp/input checks and paired world replay, source/cost review and adoption, then six fresh normal/10× and jobs comparisons/captures.', expected=6),
        dict(game='ttld', title='To the Last Drop', code='House ignition and health-bar fixes implemented/tested/pushed. Final parity verification remains active.', remaining='Finish ordinary-fire and four detailed-world checks; then fresh timings, captures and analysis.', expected=4),
        dict(game='gravitas', title='Gravitas effects', code='Selected optimizations implemented/tested on both sides; no identified code fix pending.', remaining='Current-engine effects/jobs comparisons, captures and analysis. Effects only.', expected=6),
        dict(game='mycube', title='My Cube', code='Story/RNG, mass and idle fixes tested/pushed; all 151 full-world and 9,750 pose samples match Lua exactly.', remaining='Fresh normal-scene comparisons/captures and profile review on the corrected public sources.', expected=1),
        dict(game='partsneeded', title='Parts Needed', code='Level/gate/camera and same-frame rotation fixes tested/pushed; all 151 full-world samples match Lua exactly.', remaining='Fresh normal-scene comparisons/captures and profile review on the corrected public sources.', expected=1),
    ]
    state_path = project / 'codex-work/night-2026-10-30/v4/state.json'
    completed = read(state_path)['completed'] if state_path.exists() else {}
    roots_path = project / 'codex-work/current-timing-roots.json'
    if roots_path.exists():
        current_roots = {(project / p).resolve() for p in read(roots_path)}
        completed = {name: path for name, path in completed.items()
                     if (project / path).parent.resolve() in current_roots}
    for game in games:
        prefix = {'gravitas': 'fire-'}.get(game['game'], game['game'])
        game['completed'] = sum(name.startswith(prefix) for name in completed)
    world_path = project / 'codex-work/night-2026-10-30/v4/ttld-ui-parity/worlds-final.json'
    if world_path.exists():
        worlds = read(world_path)
        ttld = next(g for g in games if g['game'] == 'ttld')
        ttld['remaining'] = f"Detailed-world checks: {len(worlds['passed'])}/4 complete. Ordinary-fire verification, fresh timings/captures and analysis remain."
    gate_path = state_path.parent / 'ttld-ui-matched-selection.json'
    if gate_path.exists():
        gate = read(gate_path)
        if all(gate.get(key) for key in ('reviewed', 'checks_passed', 'worlds_passed', 'ordinary_fire_passed')):
            ttld = next(g for g in games if g['game'] == 'ttld')
            ttld['code'] = 'House ignition and health-bar fixes tested/pushed. Existing suites, ordinary fire and all 604 detailed-world sample pairs pass; normal screenshots reviewed.'
            ttld['remaining'] = 'Fresh final timings, matching captures and profile analysis.'
    by_game = {game['game']: game for game in games}
    for name in ('hunted', 'gravitas'):
        if by_game[name]['completed'] == by_game[name]['expected']:
            by_game[name]['remaining'] = 'Timing matrix complete. Final profile interpretation and jobs-cost diagnostics remain.'
    if by_game['area17']['completed'] == 1:
        by_game['area17']['remaining'] = 'Normal timing/profile/world/clip complete; finish the fresh 2× case and its captures, then final analysis.'
    if by_game['ttld']['completed'] == 4:
        capture_counts = {}
        for kind in ('profiles', 'videos'):
            path = project / f'codex-work/cpu-idle-fire-{kind}.json'
            saved = read(path).get('completed', {}) if path.exists() else {}
            capture_counts[kind] = sum(name.startswith('ttld-') for name in saved)
        by_game['ttld']['remaining'] = (
            f"All four timing cases and world pairs complete. CPU profile pairs {capture_counts['profiles']}/4; "
            f"clip pairs {capture_counts['videos']}/4. Finish remaining captures and final profile analysis."
        )
    hold_path = project / 'verification/perf/web/world-parity-holds.json'
    if hold_path.exists():
        for name, hold in read(hold_path).get('campaigns', {}).items():
            game = next(g for g in games if name.startswith(g['game']))
            game['remaining'] += ' Earlier mismatched comparisons remain held until replaced.'
    return dict(generated_at=datetime.now(timezone.utc).isoformat(), timezone='Europe/Budapest',
                scope='Display-only retained results. Never merged into current statistics, traces, identities or capture eligibility. Superseded rows had known implementation/workload differences; their percentages are recorded observations, not language speedups.',
                scenes=scenes, jobs=jobs, games=games)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=PROJECT / 'verification/perf/web')
    parser.add_argument('--archive', type=Path, default=PROJECT / 'docs/benchmarks/2026-10-26/data.json')
    args = parser.parse_args()
    data = export(PROJECT, args.archive)
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / 'historical-results.json').write_text(json.dumps(data, indent=2) + '\n')
    (args.output / 'historical-results.js').write_text('window.SC_HISTORY=' + json.dumps(data, separators=(',', ':')) + ';\n')
    print(f'Historical overview: {len(data["scenes"])} scenes, {len(data["jobs"])} jobs comparisons; current aggregates untouched.')


if __name__ == '__main__':
    main()
