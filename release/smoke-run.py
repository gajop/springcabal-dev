#!/usr/bin/env python3
"""Run one release smoke case with the existing verification resource guards."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "verification/perf"))
import run as verification


def stop(process):
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
    # A launcher can exit before a child. Only this command's session is owned.
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def execute(command, seconds, guard_path, max_minutes=1440):
    # This checks startup correctness, not timings. Use the same GPU/pressure
    # gate as the keyboard menu suite; performance captures additionally limit
    # background CPU utilization in the perf runner.
    options = argparse.Namespace(wait_for_idle=True, wait_for_gpu_idle=True)
    pressure_path = verification.cpu_pressure_path("cgroup")
    samples, preflight, error = [], [], None
    process = monitor = None
    status = 125
    try:
        with verification.VerificationLease() as lease:
            _, _, preflight = verification.wait_for_resources(
                options, pressure_path, time.monotonic() + max_minutes * 60,
                "release smoke", lease)
            process = subprocess.Popen(command, start_new_session=True)

            def sample(group):
                data = verification.gpu_processes(group)
                data["cpu_pressure"] = verification.pressure(verification.host(pressure_path))
                return data

            try:
                monitor = verification.GpuMonitor(process.pid, sampler=sample)
                deadline = time.monotonic() + seconds
                while process.poll() is None:
                    if monitor.error or any(s["foreign"] or s["cpu_pressure"] > 5
                                            for s in monitor.samples):
                        raise RuntimeError("CPU/GPU contention interrupted the smoke case")
                    if time.monotonic() >= deadline:
                        status = 124
                        break
                    time.sleep(.1)
                else:
                    status = process.returncode
            finally:
                # Keep the lease until this engine and monitor have stopped.
                stop(process)
                process = None
                if monitor is not None:
                    monitor.stop()
                    samples = monitor.samples
            if monitor.error:
                raise RuntimeError(str(monitor.error))
            if any(s["foreign"] or s["cpu_pressure"] > 5 for s in samples):
                raise RuntimeError("CPU/GPU contention interrupted the smoke case")
    except Exception as failure:
        error = str(failure)
        print("Smoke guard: " + error, file=sys.stderr, flush=True)
        status = 125
    finally:
        guard_path.write_text(json.dumps({"preflight": preflight, "samples": samples,
                                         "error": error, "exit": status}, indent=2) + "\n")
    return status


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=float, required=True)
    parser.add_argument("--guard", type=Path, required=True)
    parser.add_argument("--max-minutes", type=float, default=1440)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command or args.seconds <= 0 or args.max_minutes <= 0:
        parser.error("a command and positive timeout values are required")
    return execute(command, args.seconds, args.guard, args.max_minutes)


if __name__ == "__main__":
    sys.exit(main())
