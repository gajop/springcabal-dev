"""Lossless storage for completed diagnostic artifacts."""
import gzip
import hashlib
import os
from pathlib import Path
import shutil


def open_world(path):
    path = Path(path)
    if not path.exists() and path.with_suffix(path.suffix + '.gz').exists():
        path = path.with_suffix(path.suffix + '.gz')
    return gzip.open(path, 'rt') if path.suffix == '.gz' else path.open()


def compress_world(source, destination):
    """Verify a gzip round trip before replacing the uncompressed recording."""
    source, destination = Path(source), Path(destination)
    if destination.exists():
        raise FileExistsError(destination)
    temporary = destination.with_suffix(destination.suffix + '.partial')
    digest = hashlib.sha256()
    try:
        with source.open('rb') as incoming, temporary.open('xb') as outgoing:
            with gzip.GzipFile(filename='', mode='wb', fileobj=outgoing,
                               compresslevel=1, mtime=0) as compressed:
                for block in iter(lambda: incoming.read(4 << 20), b''):
                    digest.update(block)
                    compressed.write(block)
        verified = hashlib.sha256()
        with gzip.open(temporary, 'rb') as incoming:
            for block in iter(lambda: incoming.read(4 << 20), b''):
                verified.update(block)
        if digest.digest() != verified.digest():
            raise ValueError('World recording compression changed its contents')
        os.replace(temporary, destination)
        source.unlink()
    finally:
        temporary.unlink(missing_ok=True)
    return {'world_recording': destination.name, 'world_recording_encoding': 'gzip',
            'world_recording_sha256': digest.hexdigest()}


def require_space(path, minimum_gib):
    free = shutil.disk_usage(path).free
    if free < minimum_gib * 1024**3:
        raise ValueError(f'Only {free / 1024**3:.1f} GiB free; '
                         f'{minimum_gib:g} GiB reserve required before another run')
