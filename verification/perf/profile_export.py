#!/usr/bin/env python3
"""Export real perf call stacks to compact, portable flame trees.

Run after capture.sh completes. The symbol cache must contain the debug file
whose build ID matches the unchanged release binary. No engine rebuild needed.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import subprocess

HEADER = re.compile(r'^(.*?)\s+(\d+)/(\d+)\s+([\d.]+):\s+(\d+)\s*$')
FRAME = re.compile(r'^\s+[a-fA-F\d]+\s+(.+)\s+\(([^()]*)\)\s*$')


def category(symbol, dso):
    """Mutually exclusive categories of the sampled instruction, not its callers."""
    if 'nvidia' in dso.lower() or re.search(r'lib(?:GL|EGL|drm)', dso):
        return 'Graphics driver (CPU)'
    if symbol == '[unknown]' or re.fullmatch(r'0x[\da-f]+', symbol):
        return 'Unresolved'
    if re.search(r'wasm\[|wasm::|^function\[', symbol):
        return 'Wasm guest'
    if re.search(r'wasmtime|cranelift|wasm_runtime|wasm_enter|wasm_to_array', symbol, re.I):
        return 'Wasmtime runtime'
    if re.search(r'^(lua[A-Z_a-z]|lj_)|spring_lua|LuaMemPool', symbol):
        return 'Lua runtime / tables / GC'
    if re.search(r'HAPFS|MoveMath|GroundMove|PathFinder|PathEstimator|MoveDef', symbol):
        return 'Native movement / pathfinding'
    if re.search(r'CSyncChecker|game_perf|sync_hash', symbol):
        return 'Checksums / measurement'
    if re.search(r'ConcurrentQueue|ThreadPool|SpinLoop|Threading::.*Yield', symbol):
        return 'Worker queue / waiting'
    if re.search(r'Wasm.*Import|spring::wasm::|WasmHost|wasm::host', symbol):
        return 'Wasm host API'
    if re.search(r'Draw|Render|Model|Frustum|Shadow|GL::|gl[A-Z]|PiecePos|PieceMatrix', symbol):
        return 'Native rendering / models'
    if re.search(r'CUnit|CWeapon|CProjectile|QuadField|Los|Sensor|UnitScript|UnitAnim|Cus', symbol):
        return 'Native simulation / animation'
    return 'Other native code'


def parse(text):
    samples, current = [], None
    for line in text.splitlines():
        match = HEADER.match(line)
        if match:
            if current:
                samples.append(current)
            comm, pid, tid, timestamp, period = match.groups()
            current = {'thread': f'{comm} ({tid})', 'comm': comm, 'tid': int(tid),
                       'time': float(timestamp), 'weight': int(period), 'frames': []}
        elif current:
            match = FRAME.match(line)
            if match:
                symbol, dso = match.groups()
                current['frames'].append((symbol, dso))
    if current:
        samples.append(current)
    return [s for s in samples if s['frames']]


def export(samples):
    threads, totals, categories, leaves = {}, Counter(), Counter(), {}
    for sample in samples:
        thread, weight = sample['thread'], sample['weight']
        root = threads.setdefault(thread, {'name': thread, 'weight': 0, 'self': 0, 'children': {}})
        node = root
        node['weight'] += weight
        # perf prints the sampled instruction first and its ancestors after it.
        for symbol, dso in reversed(sample['frames']):
            key = (symbol, dso)
            node = node['children'].setdefault(key, {'name': symbol, 'dso': Path(dso).name,
                                                    'weight': 0, 'self': 0, 'children': {}})
            node['weight'] += weight
        node['self'] += weight
        symbol, dso = sample['frames'][0]
        group = category(symbol, dso)
        totals[thread] += weight
        categories[thread, group] += weight
        key = thread, symbol, Path(dso).name, group
        leaves[key] = leaves.get(key, 0) + weight
    def pack(node):
        node['children'] = [pack(n) for n in sorted(node['children'].values(), key=lambda n: -n['weight'])]
        return node
    return {'samples': len(samples), 'first_sample': min(s['time'] for s in samples),
            'last_sample': max(s['time'] for s in samples), 'weight_unit': 'sampled CPU ns',
            'threads': [pack(n) for n in threads.values()],
            'categories': [{'thread': t, 'category': c, 'weight': w} for (t, c), w in categories.items()],
            'leaves': [{'thread': t, 'name': n, 'dso': d, 'category': c, 'weight': w}
                       for (t, n, d, c), w in sorted(leaves.items(), key=lambda item: -item[1])]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('captures', type=Path)
    parser.add_argument('--buildid-dir', type=Path, required=True)
    args = parser.parse_args()
    exporter_sha = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    for result in sorted(args.captures.glob('**/result.json')):
        directory = result.parent
        metadata = json.loads(result.read_text())
        raw = directory/'cpu.perf.data'
        output = directory/'profile.json'
        if not raw.exists() or (output.exists() and json.loads(output.read_text()).get('exporter_sha256') == exporter_sha):
            continue
        if not metadata['ok'] or not metadata.get('sampling'):
            raise ValueError(f'Incomplete profiling run: {directory}')
        controls = metadata['sampling']['control']
        if [c['action'] for c in controls] != ['enable', 'disable']:
            raise ValueError(f'Missing sampling window control: {directory}')
        source = raw
        if metadata['backend'] == 'wasm':
            source = directory/'cpu.injected.data'
            source.unlink(missing_ok=True)
            with (directory/'perf-inject.log').open('w') as log:
                subprocess.run(['perf', 'inject', '--jit', '-i', str(raw), '-o', str(source)],
                               stdout=log, stderr=subprocess.STDOUT, check=True)
        with (directory/'perf-script.log').open('w') as log:
            proc = subprocess.run(['perf', '--buildid-dir', str(args.buildid_dir.resolve()),
                                   'script', '--no-inline', '-i', str(source),
                                   '-F', 'comm,pid,tid,time,period,ip,sym,dso'],
                                  stdout=subprocess.PIPE, stderr=log, text=True, check=True)
        data = export(parse(proc.stdout))
        data['exporter_sha256'] = exporter_sha
        data['capture'] = metadata['sampling']
        data['run'] = {k: metadata.get(k) for k in
                       ('game', 'backend', 'rust_jobs', 'renderer', 'fire_renderer', 'worker_threads', 'contended',
                        'gpu_process_guard', 'gpu_contended')}
        output.write_text(json.dumps(data, separators=(',', ':'))+'\n')
        print(directory.relative_to(args.captures), data['samples'], 'samples', flush=True)


if __name__ == '__main__':
    main()
