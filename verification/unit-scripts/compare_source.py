#!/usr/bin/env python3
"""Check that the Parts Needed Rust gait tables match the Lua animations.

This is intentionally an offline check.  It compares the source animation
commands and keyframe times directly, so it can validate the portable CUS
translation without starting Spring or depending on a graphical runtime.
The final empty Lua keyframe is represented by the Rust loop's wrap-around
sleep and is therefore excluded from the command-table comparison.
"""

from __future__ import annotations

import argparse
import math
import re
import sys
from pathlib import Path


LUA_FRAME = re.compile(
    r"\{\s*\['time'\]\s*=\s*(?P<time>\d+),\s*"
    r"\['commands'\]\s*=\s*\{(?P<commands>.*?)\}\s*\},",
    re.S,
)
LUA_COMMAND = re.compile(
    r"\{\['c'\]='(?P<kind>turn|move)'.*?"
    r"\['p'\]=(?P<piece>\w+).*?"
    r"\['a'\]=(?P<axis>\w+).*?"
    r"\['t'\]=(?P<target>[-+0-9.eE]+).*?"
    r"\['s'\]=(?P<speed>[-+0-9.eE]+).*?\}",
)
RUST_FRAME = re.compile(
    r"\(\s*(?P<time>\d+)\s*,\s*&\[\s*"
    r"(?P<commands>.*?)\]\s*,?\s*\),",
    re.S,
)
RUST_COMMAND = re.compile(
    r"TurnCommand\s*\{\s*"
    r"piece:\s*WispAnimationPiece::(?P<piece>\w+),\s*"
    r"axis:\s*Axis::(?P<axis>\w+),\s*"
    r"target:\s*(?P<target>[-+0-9.eE]+),\s*"
    r"speed:\s*(?P<speed>[-+0-9.eE]+),\s*\}",
    re.S,
)

AXES = {"x_axis": "X", "y_axis": "Y", "z_axis": "Z"}


Command = tuple[str, str, float, float]
Frame = tuple[int, list[Command]]


def lua_frames(path: Path) -> list[Frame]:
    frames: list[Frame] = []
    for frame in LUA_FRAME.finditer(path.read_text()):
        commands: list[Command] = []
        for command in LUA_COMMAND.finditer(frame["commands"]):
            if command["kind"] != "turn":
                continue
            commands.append(
                (
                    command["piece"],
                    AXES[command["axis"]],
                    float(command["target"]),
                    float(command["speed"]),
                )
            )
        frames.append((int(frame["time"]), commands))
    if not frames:
        raise ValueError(f"no animation frames found in {path}")
    return frames


def rust_frames(source: str, function: str, next_function: str) -> list[Frame]:
    start = source.index(f"async fn {function}")
    end = source.index(next_function, start)
    body = source[start:end]
    body = body[body.index("const FRAMES"):]
    frames: list[Frame] = []
    for frame in RUST_FRAME.finditer(body):
        commands = [
            (
                command["piece"],
                command["axis"],
                float(command["target"]),
                float(command["speed"]),
            )
            for command in RUST_COMMAND.finditer(frame["commands"])
        ]
        frames.append((int(frame["time"]), commands))
    if not frames:
        raise ValueError(f"no Rust animation frames found for {function}")
    return frames


def same_command(left: Command, right: Command) -> bool:
    return (
        left[:2] == right[:2]
        and math.isclose(left[2], right[2], abs_tol=1e-6)
        and math.isclose(left[3], right[3], abs_tol=1e-6)
    )


def check_animation(
    label: str,
    lua_path: Path,
    source: str,
    rust_function: str,
    next_function: str,
) -> int:
    lua = lua_frames(lua_path)
    rust = rust_frames(source, rust_function, next_function)
    if lua[-1][1]:
        raise ValueError(f"{lua_path}: terminal keyframe is expected to be empty")
    lua = lua[:-1]

    if len(lua) != len(rust):
        raise ValueError(
            f"{label}: keyframe count differs: Lua={len(lua)} Rust={len(rust)}"
        )
    for index, (lua_frame, rust_frame) in enumerate(zip(lua, rust)):
        lua_time, lua_commands = lua_frame
        rust_time, rust_commands = rust_frame
        if lua_time != rust_time:
            raise ValueError(
                f"{label}: keyframe {index} time differs: "
                f"Lua={lua_time} Rust={rust_time}"
            )
        if len(lua_commands) != len(rust_commands):
            raise ValueError(
                f"{label}: keyframe {lua_time} command count differs: "
                f"Lua={len(lua_commands)} Rust={len(rust_commands)}"
            )
        for command_index, (left, right) in enumerate(
            zip(lua_commands, rust_commands)
        ):
            if not same_command(left, right):
                raise ValueError(
                    f"{label}: keyframe {lua_time} command {command_index} "
                    f"differs: Lua={left!r} Rust={right!r}"
                )

    command_count = sum(len(commands) for _, commands in lua)
    print(
        f"PASS: {label}: {len(lua)} keyframes and "
        f"{command_count} Turn commands match Lua"
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("lua_animations", type=Path)
    parser.add_argument(
        "rust_source",
        type=Path,
        help="the Rust unit_scripts.rs file or the split unit_scripts directory",
    )
    args = parser.parse_args()
    try:
        if args.rust_source.is_dir():
            source = "\n".join(
                path.read_text()
                for path in (
                    args.rust_source / "wisp" / "walk_legs.rs",
                    args.rust_source / "wisp" / "walk_arms.rs",
                    args.rust_source / "wisp" / "float_arms.rs",
                )
            )
        else:
            source = args.rust_source.read_text()
        check_animation(
            "walk legs",
            args.lua_animations / "wisp_walk_legs.lua",
            source,
            "wisp_walk_legs",
            "async fn wisp_walk_arms",
        )
        check_animation(
            "walk arms",
            args.lua_animations / "wisp_walk_arms.lua",
            source,
            "wisp_walk_arms",
            "async fn wisp_float_arms",
        )
    except (OSError, ValueError, KeyError) as error:
        print(f"unit-script-source-compare: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
