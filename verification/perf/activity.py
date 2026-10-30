"""Measure background CPU use, excluding this runner and its child processes."""
import os
from pathlib import Path
import re
import time


WINDOW_POLICY = 'launch through first CPU sample after final frame marker'


def end_marker(line, frame):
    if not isinstance(line, str):
        return False
    return bool(re.fullmatch(
        r'\[t=\d+:\d+:\d+\.\d+\]\[f=0*'+str(frame)+
        r'\] \[PerfWindow\] end frame='+str(frame), line))


class CaptureWindow:
    """Keep the sample straddling the final marker inside the CPU guard.

    Shutdown remains recorded, but cannot interrupt frames already completed.
    A missing, partial or wrong-frame marker keeps the whole process guarded.
    """
    def __init__(self, frame):
        self.frame = frame
        self.offset, self.tail = 0, ''
        self.marker = None
        self.closed_after = None

    def poll(self, log):
        if self.marker is not None:
            return
        with log.open(errors='replace') as stream:
            stream.seek(self.offset)
            self.tail += stream.read()
            self.offset = stream.tell()
        lines = self.tail.split('\n')
        self.tail = lines.pop()[-4096:]
        self.marker = next((line for line in lines if end_marker(line, self.frame)), None)

    @property
    def guarded(self):
        return self.closed_after is None

    def after_sample(self, index):
        if self.marker is not None and self.closed_after is None:
            self.closed_after = index

    def metadata(self):
        if self.closed_after is None:
            return None
        return {'policy': WINDOW_POLICY, 'end_frame': self.frame,
                'end_marker': self.marker, 'closed_after_sample_index': self.closed_after}


def cpu_guard_samples(samples, window=None):
    """Review old captures in full; require a complete boundary for new ones."""
    if not isinstance(window, dict) or window.get('policy') != WINDOW_POLICY:
        return samples
    frame, index = window.get('end_frame'), window.get('closed_after_sample_index')
    if (type(frame) is not int or frame < 0 or type(index) is not int or
            not 0 <= index < len(samples) or not samples[index].get('cpu_activity') or
            not end_marker(window.get('end_marker', ''), frame)):
        return samples
    return samples[:index+1]


def own_cpu_ticks(pid=None, proc=Path('/proc')):
    """Include live children and reaped-child time without counting threads twice."""
    pending = [os.getpid() if pid is None else pid]
    visited = set()
    total = 0
    while pending:
        current = pending.pop()
        if current in visited:
            continue
        visited.add(current)
        directory = proc/str(current)
        try:
            fields = (directory/'stat').read_text().rsplit(')', 1)[1].split()
            # /proc/PID/stat aggregates the process's threads. Its child times
            # cover children already reaped; live children are visited below.
            total += sum(int(fields[i]) for i in (11, 12, 13, 14))
            for task in (directory/'task').iterdir():
                try:
                    pending.extend(map(int, (task/'children').read_text().split()))
                except (FileNotFoundError, ProcessLookupError):
                    pass
        except (FileNotFoundError, ProcessLookupError):
            if len(visited) == 1:
                raise ValueError('CPU activity guard cannot read its own process')
    return total


def snapshot(proc=Path('/proc'), pid=None):
    try:
        line = (proc/'stat').read_text().splitlines()[0].split()
        if line[0] != 'cpu' or len(line) < 9:
            raise ValueError('CPU activity guard received an invalid /proc/stat')
        values = list(map(int, line[1:9]))
        # user, nice, system, irq, softirq, steal; guest is already in user.
        busy = sum(values[:3]) + sum(values[5:8])
        return busy, own_cpu_ticks(pid, proc)
    except OSError as error:
        raise ValueError('CPU activity guard is unavailable: '+str(error)) from error


class CpuActivity:
    def __init__(self, read=snapshot, now=time.monotonic, ticks=None):
        self.read, self.now = read, now
        self.ticks = os.sysconf('SC_CLK_TCK') if ticks is None else ticks
        self.previous = read()
        self.previous_time = now()

    def sample(self):
        current = self.read()
        now = self.now()
        elapsed = now-self.previous_time
        busy, own = [a-b for a, b in zip(current, self.previous)]
        self.previous, self.previous_time = current, now
        # A child exiting between the parent and child reads can temporarily
        # lower the sum. Do not interpret that observation as an idle system.
        valid = elapsed >= .05 and busy >= 0 and own >= 0
        scale = self.ticks*elapsed if valid else None
        return {'valid': valid, 'interval_seconds': elapsed,
                'total_busy_cores': busy/scale if valid else None,
                'own_process_tree_cores': own/scale if valid else None,
                'background_cpu_cores': max(0, busy-own)/scale if valid else None}


def busy(sample, limit):
    if limit is None:
        return False
    return not sample or not sample['valid'] or sample['background_cpu_cores'] > limit
