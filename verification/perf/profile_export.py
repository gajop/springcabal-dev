#!/usr/bin/env python3
"""Export real perf call stacks to compact, portable flame trees.

Run after capture.sh completes. The symbol cache must contain the debug file
whose build ID matches the unchanged release binary. No engine rebuild needed.
"""
import argparse
from bisect import bisect_right
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess

HEADER = re.compile(r'^(.*?)\s+(\d+)/(\d+)\s+([\d.]+):\s+(\d+)\s*$')
FRAME = re.compile(r'^\s+([a-fA-F\d]+)\s+(.+)\s+\(([^()]*)\)\s*$')


class JitSymbols:
    """Recover named code ranges when perf inject leaves compressed blocks intact.

    Linux's jitdump format records the process, native address, size and load
    time. Only unambiguous, already-loaded ranges using CLOCK_MONOTONIC qualify.
    Moving or overlapping code stays unresolved; no call-chain parents are added.
    https://github.com/torvalds/linux/blob/v6.8/tools/perf/Documentation/jitdump-specification.txt
    """
    def __init__(self, directory):
        self.ranges, self.sources, self.resolved_frames, self.closed = {}, [], 0, {}
        by_pid = {}
        for path in sorted(directory.glob('**/jit-*.dump')):
            data = path.read_bytes()
            if len(data) < 40:
                raise ValueError(f'Truncated jitdump header: {path}')
            endian = '<' if struct.unpack('<I', data[:4])[0] == 0x4a695444 else '>'
            magic, version, size, _, _, pid, _, flags = struct.unpack(endian+'6I2Q', data[:40])
            if magic != 0x4a695444 or size < 40 or size > len(data):
                raise ValueError(f'Invalid jitdump header: {path}')
            reason = 'unsupported version or clock' if version not in (1, 2) or flags else None
            loads, cursor = [], size
            while cursor < len(data):
                if cursor+16 > len(data):
                    raise ValueError(f'Truncated jitdump record: {path}')
                kind, length, timestamp = struct.unpack_from(endian+'IIQ', data, cursor)
                end = cursor+length
                if length < 16 or end > len(data):
                    raise ValueError(f'Invalid jitdump record length: {path}')
                if kind == 0:
                    if length < 57:
                        raise ValueError(f'Truncated jitdump code load: {path}')
                    process, _, _, address, count, _ = struct.unpack_from(endian+'II4Q', data, cursor+16)
                    name_end = data.find(b'\0', cursor+56, end)
                    if process != pid or name_end < 0 or end-name_end-1 != count:
                        raise ValueError(f'Invalid jitdump code load: {path}')
                    name = data[cursor+56:name_end].decode('utf-8', errors='replace')
                    if count and name:
                        loads.append((address, address+count, name, timestamp))
                elif kind == 1:
                    reason = 'moving code is not resolved by this fallback'
                elif kind == 3:
                    self.closed[pid] = min(timestamp, self.closed.get(pid, timestamp))
                elif kind not in (2, 3, 4):
                    reason = 'unsupported jitdump record'
                cursor = end
            self.sources.append({'file': str(path.relative_to(directory)),
                                 'sha256': hashlib.sha256(data).hexdigest(),
                                 'code_loads': len(loads), 'skipped_reason': reason})
            if not reason:
                by_pid.setdefault(pid, []).extend(loads)
        for pid, loads in by_pid.items():
            # Identical registrations are safe; reused/overlapping addresses
            # cannot be assigned a lifetime from CODE_LOAD alone. Exclude them.
            unique = {}
            for start, end, name, timestamp in loads:
                key = start, end, name
                unique[key] = min(timestamp, unique.get(key, timestamp))
            ordered = sorted((*key, timestamp) for key, timestamp in unique.items())
            clean, cluster, limit = [], [], 0
            for entry in ordered:
                if cluster and entry[0] >= limit:
                    if len(cluster) == 1:
                        clean.extend(cluster)
                    cluster = []
                cluster.append(entry)
                limit = max(e[1] for e in cluster)
            if len(cluster) == 1:
                clean.extend(cluster)
            self.ranges[pid] = ([entry[0] for entry in clean], clean)

    def resolve(self, pid, address, timestamp):
        if timestamp >= self.closed.get(pid, float('inf')):
            return None
        starts, ranges = self.ranges.get(pid, ([], []))
        index = bisect_right(starts, address)-1
        if index < 0:
            return None
        start, end, name, loaded = ranges[index]
        if start <= address < end and loaded <= timestamp:
            self.resolved_frames += 1
            return name, f'jit-{pid}.dump'
        return None


def category(symbol, dso):
    """Mutually exclusive categories of the sampled instruction, not its callers."""
    if 'nvidia' in dso.lower() or re.search(r'lib(?:GL|EGL|drm)', dso):
        return 'Graphics driver (CPU)'
    if symbol == '[unknown]' or re.fullmatch(r'0x[\da-f]+', symbol):
        return 'Unresolved'
    if re.search(r'wasmtime|cranelift|wasm_runtime|wasm_enter|wasm_to_array', symbol, re.I):
        return 'Wasmtime runtime'
    if re.search(r'wasm\[|wasm::|^function\[', symbol) or re.fullmatch(r'jit-\d+\.dump', Path(dso).name):
        return 'Wasm guest'
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


def parse(text, jit=None):
    samples, current = [], None
    for line in text.splitlines():
        match = HEADER.match(line)
        if match:
            if current:
                samples.append(current)
            comm, pid, tid, timestamp, period = match.groups()
            current = {'thread': f'{comm} ({tid})', 'comm': comm, 'pid': int(pid), 'tid': int(tid),
                       'time': float(timestamp), 'weight': int(period), 'frames': []}
        elif current:
            match = FRAME.match(line)
            if match:
                address, symbol, dso = match.groups()
                if jit and (symbol == '[unknown]' or re.fullmatch(r'0x[\da-f]+', symbol)):
                    resolved = jit.resolve(current['pid'], int(address, 16), round(current['time']*1e9))
                    if resolved:
                        symbol, dso = resolved
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
            print(f'Skipping incomplete profiling run: {directory}', flush=True)
            continue
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
        jit = JitSymbols(directory) if metadata['backend'] == 'wasm' else None
        data = export(parse(proc.stdout, jit))
        if jit:
            data['jit_symbols'] = {'sources': jit.sources, 'resolved_frames': jit.resolved_frames}
        data['exporter_sha256'] = exporter_sha
        data['capture'] = metadata['sampling']
        data['run'] = {k: metadata.get(k) for k in
                       ('game', 'backend', 'rust_jobs', 'renderer', 'fire_renderer', 'worker_threads', 'contended',
                        'gpu_process_guard', 'gpu_contended', 'callback_timers')}
        provenance = json.loads((directory.parent/'provenance.json').read_text())
        data['runtime'] = {key: provenance.get(key) for key in
                           ('engine_commit', 'engine_sha256', 'engine_source')}
        output.write_text(json.dumps(data, separators=(',', ':'))+'\n')
        # The raw capture and jitdump inputs can regenerate this intermediate.
        if source != raw:
            source.unlink()
        print(directory.relative_to(args.captures), data['samples'], 'samples', flush=True)


if __name__ == '__main__':
    main()
