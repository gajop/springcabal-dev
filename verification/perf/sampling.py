"""Opt-in perf recording for the existing runner, excluded from timing reports.

The engine stays unchanged. perf's FIFO control enables sampling after the
existing warmup echo and disables it at the stop echo. Poll latency is retained
in metadata; sampled on-CPU time is never presented as elapsed frame time.
"""
import os
from pathlib import Path
import time


class Capture:
    def __init__(self, directory, warmup, stop):
        self.directory = directory
        self.warmup, self.stop = warmup, stop
        self.fifo = directory/'perf-control.fifo'
        os.mkfifo(self.fifo)
        self.fd = os.open(self.fifo, os.O_RDWR | os.O_NONBLOCK)
        self.metadata = {'event': 'cpu-clock:u', 'frequency_hz': 499,
                         'call_graph': 'dwarf,16384', 'poll_seconds': .02,
                         'warmup_frame': warmup, 'stop_frame': stop,
                         'control': []}
        self.offset = 0
        self.tail = ''

    def command(self, command):
        return ['perf', 'record', '--compression-level=1', '-k', '1', '-e', 'cpu-clock:u', '-F', '499',
                '--call-graph', 'dwarf,16384', '--delay=-1',
                '--control=fifo:'+str(self.fifo), '-o',
                str(self.directory/'cpu.perf.data'), '--', *command]

    def poll(self, log):
        with log.open() as stream:
            stream.seek(self.offset)
            self.tail += stream.read()
            self.offset = stream.tell()
        lines = self.tail.split('\n')
        self.tail = lines.pop()
        for line in lines:
            for kind, frame, action in [('begin', self.warmup, 'enable'),
                                         ('end', self.stop, 'disable')]:
                if f'[PerfWindow] {kind} frame={frame}' in line:
                    os.write(self.fd, (action+'\n').encode())
                    self.metadata['control'].append({
                        'action': action, 'observed_monotonic': time.monotonic(),
                        'marker': line})

    def finish(self, log):
        self.poll(log)
        os.close(self.fd)
        self.fifo.unlink()
