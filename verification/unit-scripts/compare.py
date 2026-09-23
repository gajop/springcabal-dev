#!/usr/bin/env python3
"""Compare engine-observed unit-piece transforms from two Spring runs.

The input is the combined infolog produced by unit_script_probe.lua. The
comparison uses each piece's model-space matrix, so it includes both
translation and animated rotation without depending on implementation details.
"""

from __future__ import annotations

import argparse
import math
import re
import sys
from dataclasses import dataclass
from pathlib import Path


LINE = re.compile(
    r"\[UnitScriptProbe\] frame=(?P<frame>\d+) piece=(?P<piece>\S+) "
    r"m=(?P<matrix>[-+0-9.eE,]+)"
)
DONE = re.compile(r"\[UnitScriptProbe\] DONE ")
ERROR = re.compile(r"\[UnitScriptProbe\] ERROR ")
SAMPLE_DONE = re.compile(
    r"\[UnitScriptProbe\] SAMPLE_DONE frame=(?P<frame>\d+) pieces=(?P<pieces>\d+)"
)


@dataclass(frozen=True)
class Sample:
    frame: int
    piece: str
    values: tuple[float, ...]


def read_trace(path: Path) -> dict[tuple[int, str], Sample]:
    samples: dict[tuple[int, str], Sample] = {}
    sample_counts: dict[int, int] = {}
    done = False
    errors: list[str] = []
    for line in path.read_text(errors="replace").splitlines():
        if DONE.search(line):
            done = True
        if ERROR.search(line):
            errors.append(line.strip())
        sample_done = SAMPLE_DONE.search(line)
        if sample_done:
            sample_counts[int(sample_done["frame"])] = int(sample_done["pieces"])
        match = LINE.search(line)
        if not match:
            continue
        frame = int(match["frame"])
        piece = match["piece"]
        try:
            values = tuple(float(value) for value in match["matrix"].split(","))
        except ValueError:
            # The two streams are concatenated by vf_save_logs. A timeout can
            # leave one stream's final matrix line after its trailing comma;
            # the complete copy from the other stream, or SAMPLE_DONE's count,
            # is the authoritative evidence for that sample.
            continue
        if len(values) != 16:
            # vf_save_logs combines stdout and infolog. The engine can leave
            # the final line of either stream partial, while the other stream
            # still contains the complete copy; the key-set check below will
            # catch a sample that is genuinely absent.
            continue
        samples[(frame, piece)] = Sample(frame, piece, values)
    if errors:
        raise ValueError(f"{path}: probe reported error(s):\n" + "\n".join(errors))
    if not done:
        raise ValueError(f"{path}: probe did not reach DONE")
    if not samples:
        raise ValueError(f"{path}: probe produced no transform samples")
    if not sample_counts:
        raise ValueError(f"{path}: probe produced no SAMPLE_DONE markers")
    for frame, expected in sample_counts.items():
        actual = sum(sample_frame == frame for sample_frame, _ in samples)
        if actual != expected:
            raise ValueError(
                f"{path}: frame {frame} has {actual} complete matrix samples; "
                f"probe reported {expected}"
            )
    return samples


def compare(a: dict[tuple[int, str], Sample], b: dict[tuple[int, str], Sample], tolerance: float) -> int:
    keys_a = set(a)
    keys_b = set(b)
    missing_a = sorted(keys_b - keys_a)
    missing_b = sorted(keys_a - keys_b)
    if missing_a or missing_b:
        if missing_a:
            print(f"missing from Lua: {len(missing_a)} sample(s), first={missing_a[:5]}")
        if missing_b:
            print(f"missing from WASM: {len(missing_b)} sample(s), first={missing_b[:5]}")
        return 1

    worst = (-1.0, None)
    total = 0.0
    count = 0
    for key in sorted(keys_a):
        left = a[key].values
        right = b[key].values
        delta = math.sqrt(sum((x - y) ** 2 for x, y in zip(left, right)))
        total += delta
        count += 1
        if delta > worst[0]:
            worst = (delta, key)

    mean = total / count
    print(f"samples={count} max_delta={worst[0]:.9g} mean_delta={mean:.9g} worst={worst[1]}")
    if worst[0] > tolerance:
        print(f"FAIL: max delta exceeds tolerance {tolerance:.9g}")
        return 1
    print(f"PASS: all transform deltas are within tolerance {tolerance:.9g}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("lua_log", type=Path)
    parser.add_argument("wasm_log", type=Path)
    parser.add_argument("--tolerance", type=float, default=1e-4)
    args = parser.parse_args()
    try:
        return compare(read_trace(args.lua_log), read_trace(args.wasm_log), args.tolerance)
    except (OSError, ValueError, OverflowError) as exc:
        print(f"unit-script-compare: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
