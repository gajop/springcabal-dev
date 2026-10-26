#!/usr/bin/env python3
"""Compact completed evidence; retain logs, source identities and raw samples."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil

from run import VerificationLease
from storage import compress_world


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(4 << 20), b''):
            h.update(block)
    return h.hexdigest()


def compact(root):
    compressed = {}
    worlds = intermediates = 0
    for result in sorted(root.glob('**/result.json')):
        directory = result.parent
        metadata = json.loads(result.read_text())
        source = directory/metadata.get('world_recording', 'world.jsonl')
        if source.name == 'world.jsonl' and source.is_file():
            stat = source.stat()
            identity = stat.st_dev, stat.st_ino
            destination = directory/'world.jsonl.gz'
            if identity in compressed:
                previous, changes = compressed[identity]
                os.link(previous, destination)
                source.unlink()
            elif destination.exists():
                raise ValueError(f'Both raw and compressed worlds exist: {directory}')
            else:
                changes = compress_world(source, destination)
                compressed[identity] = destination, changes
            duplicate = directory/'write/perf-world.jsonl'
            if duplicate.is_file():
                other = duplicate.stat()
                if ((other.st_dev, other.st_ino) == identity or
                        digest(duplicate) == changes['world_recording_sha256']):
                    duplicate.unlink()
            metadata.update(changes)
            temporary = result.with_suffix('.json.compacting')
            temporary.write_text(json.dumps(metadata, indent=2)+'\n')
            os.replace(temporary, result)
            worlds += 1
            print(f'Compressed {directory.relative_to(root)}', flush=True)
        injected = directory/'cpu.injected.data'
        if (injected.is_file() and (directory/'cpu.perf.data').is_file()
                and (directory/'profile.json').is_file()):
            injected.unlink()
            intermediates += 1
    return worlds, intermediates


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    args = parser.parse_args()
    with VerificationLease():
        before = shutil.disk_usage(args.root).free
        worlds, intermediates = compact(args.root)
        after = shutil.disk_usage(args.root).free
        print(json.dumps({'compressed_worlds': worlds, 'removed_profile_intermediates': intermediates,
                          'reclaimed_gib': (after-before)/1024**3, 'free_gib': after/1024**3}))


if __name__ == '__main__':
    main()
