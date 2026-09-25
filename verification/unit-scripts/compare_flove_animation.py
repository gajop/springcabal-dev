#!/usr/bin/env python3
"""Compare deterministic Lua and CUS Flove animation traces."""

from __future__ import annotations

import argparse
import math
import re
import sys
from dataclasses import dataclass
from pathlib import Path


SKELETON = re.compile(
    r"\[FloveAnimTrace\] SKELETON case=(?P<case>\S+) piece=(?P<piece>\S+) "
    r"parent=(?P<parent>\S*) offset=(?P<offset>[-+0-9.eE,]+)"
)
POSE = re.compile(
    r"\[FloveAnimTrace\] POSE frame=(?P<frame>\d+) case=(?P<case>\S+) "
    r"piece=(?P<piece>\S+) m=(?P<matrix>[-+0-9.eE,]+)"
)
EVENT = re.compile(r"\[FloveAnimTrace\] EVENT frame=(?P<frame>\d+) name=(?P<name>\S+)")
SHOT = re.compile(r"\[FloveAnimTrace\] SHOT frame=(?P<frame>\d+) case=(?P<case>\S+)")
DEATH = re.compile(r"\[FloveAnimTrace\] DEATH frame=(?P<frame>\d+) case=(?P<case>\S+)")
DONE = re.compile(r"\[FloveAnimTrace\] DONE")
ERROR = re.compile(r"\[FloveAnimTrace\] ERROR")


@dataclass(frozen=True)
class Trace:
    skeleton: dict[tuple[str, str], tuple[str, tuple[float, ...]]]
    poses: dict[tuple[int, str, str], tuple[float, ...]]
    events: tuple[tuple[int, str], ...]


def floats(value: str) -> tuple[float, ...]:
    return tuple(float(item) for item in value.split(","))


def read_trace(path: Path) -> Trace:
    skeleton: dict[tuple[str, str], tuple[str, tuple[float, ...]]] = {}
    poses: dict[tuple[int, str, str], tuple[float, ...]] = {}
    events: set[tuple[int, str]] = set()
    errors: list[str] = []
    done = False

    for line in path.read_text(errors="replace").splitlines():
        if ERROR.search(line):
            errors.append(line.strip())
        if DONE.search(line):
            done = True

        match = SKELETON.search(line)
        if match:
            offset = floats(match["offset"])
            if len(offset) != 3:
                raise ValueError(f"{path}: malformed skeleton offset: {line}")
            skeleton[(match["case"], match["piece"])] = (match["parent"], offset)
            continue

        match = POSE.search(line)
        if match:
            matrix = floats(match["matrix"])
            if len(matrix) != 16:
                raise ValueError(f"{path}: malformed pose matrix: {line}")
            key = (int(match["frame"]), match["case"], match["piece"])
            poses[key] = matrix
            continue

        match = EVENT.search(line)
        if match:
            events.add((int(match["frame"]), match["name"]))
            continue

        match = SHOT.search(line)
        if match:
            events.add((int(match["frame"]), f"shot_{match['case']}"))
            continue

        match = DEATH.search(line)
        if match:
            events.add((int(match["frame"]), f"death_{match['case']}"))

    if errors:
        raise ValueError(f"{path}: probe reported error(s):\n" + "\n".join(errors))
    if not done:
        raise ValueError(f"{path}: probe did not reach DONE")
    if not skeleton:
        raise ValueError(f"{path}: probe exported no skeleton")
    if not poses:
        raise ValueError(f"{path}: probe exported no poses")

    return Trace(skeleton, poses, tuple(sorted(events)))


def max_delta(
    left: dict[object, tuple[float, ...]], right: dict[object, tuple[float, ...]], label: str
) -> tuple[float, object | None]:
    keys_left = set(left)
    keys_right = set(right)
    if keys_left != keys_right:
        missing_left = sorted(keys_right - keys_left)
        missing_right = sorted(keys_left - keys_right)
        if missing_left:
            print(f"{label}: missing from Lua: {len(missing_left)}; first={missing_left[:5]}")
        if missing_right:
            print(f"{label}: missing from Rust: {len(missing_right)}; first={missing_right[:5]}")
        raise ValueError(f"{label}: trace key sets differ")

    worst = (-1.0, None)
    for key in sorted(keys_left, key=str):
        delta = max(abs(a - b) for a, b in zip(left[key], right[key]))
        if delta > worst[0]:
            worst = (delta, key)
    return worst


def compare_skeleton(lua: Trace, rust: Trace, tolerance: float) -> tuple[float, object | None]:
    if set(lua.skeleton) != set(rust.skeleton):
        missing_left = sorted(set(rust.skeleton) - set(lua.skeleton))
        missing_right = sorted(set(lua.skeleton) - set(rust.skeleton))
        if missing_left:
            print(f"skeleton: missing from Lua: {len(missing_left)}; first={missing_left[:5]}")
        if missing_right:
            print(f"skeleton: missing from Rust: {len(missing_right)}; first={missing_right[:5]}")
        raise ValueError("skeleton: trace key sets differ")

    worst = (-1.0, None)
    for key in sorted(lua.skeleton, key=str):
        lua_parent, lua_offset = lua.skeleton[key]
        rust_parent, rust_offset = rust.skeleton[key]
        if lua_parent != rust_parent:
            raise ValueError(
                f"skeleton parent differs for {key}: Lua={lua_parent!r} Rust={rust_parent!r}"
            )
        delta = max(abs(a - b) for a, b in zip(lua_offset, rust_offset))
        if delta > worst[0]:
            worst = (delta, key)
    return worst


def compare(lua: Trace, rust: Trace, tolerance: float) -> int:
    if lua.events != rust.events:
        print(f"events differ:\n  Lua:  {lua.events}\n  Rust: {rust.events}")
        return 1

    try:
        skeleton_worst = compare_skeleton(lua, rust, tolerance)
        pose_worst = max_delta(lua.poses, rust.poses, "poses")
    except ValueError as exc:
        print(f"FAIL: {exc}")
        return 1

    print(
        "skeleton_entries=%d pose_samples=%d events=%d "
        "skeleton_max_delta=%.9g skeleton_worst=%s "
        "pose_max_delta=%.9g pose_worst=%s"
        % (
            len(lua.skeleton),
            len(lua.poses),
            len(lua.events),
            skeleton_worst[0],
            skeleton_worst[1],
            pose_worst[0],
            pose_worst[1],
        )
    )
    if skeleton_worst[0] > tolerance or pose_worst[0] > tolerance:
        print(f"FAIL: trace delta exceeds tolerance {tolerance:.9g}")
        return 1
    print(f"PASS: skeletons and poses match within tolerance {tolerance:.9g}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("lua_trace", type=Path)
    parser.add_argument("rust_trace", type=Path)
    parser.add_argument("--tolerance", type=float, default=2e-3)
    args = parser.parse_args()
    try:
        return compare(read_trace(args.lua_trace), read_trace(args.rust_trace), args.tolerance)
    except (OSError, ValueError, OverflowError) as exc:
        print(f"flove-animation-compare: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
