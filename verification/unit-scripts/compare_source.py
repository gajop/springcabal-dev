#!/usr/bin/env python3
"""Check that the Parts Needed Rust gait tables match the Lua animations.

Covered: the walk (legs and arms), the hover arms and the idle pose.  This is
intentionally an offline check.  It compares the source animation
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


def rust_frames(source: str, function: str, next_function: str | None) -> list[Frame]:
    start = source.index(f"async fn {function}")
    end = source.index(next_function, start) if next_function else len(source)
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
    next_function: str | None,
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


RUST_CALL = re.compile(
    r"(?P<kind>turn|move_piece)\(&?ctx,\s*p\.(?P<piece>\w+),\s*Axis::(?P<axis>\w),\s*"
    r"(?P<target>[-+0-9.eE]+),\s*(?P<speed>[-+0-9.eE]+)\)",
)

Call = tuple[str, str, str, float, float]


def pascal(snake: str) -> str:
    """Rust's `arm_r` is Lua's `ArmR` (compared case-insensitively: `forearm_l`
    is `ForeArmL`)."""
    return "".join(part[:1].upper() + part[1:] for part in snake.split("_"))


def lua_keyframes(path: Path) -> dict[int, list[Call]]:
    frames: dict[int, list[Call]] = {}
    for frame in LUA_FRAME.finditer(path.read_text()):
        frames[int(frame["time"])] = [
            (command["kind"], command["piece"], AXES[command["axis"]],
             float(command["target"]), float(command["speed"]))
            for command in LUA_COMMAND.finditer(frame["commands"])
        ]
    return frames


def rust_calls(source: str, function: str) -> list[Call]:
    start = source.index(f"fn {function}(")
    end = source.index("\n}\n", start)
    return [
        ("move" if call["kind"] == "move_piece" else "turn", pascal(call["piece"]), call["axis"],
         float(call["target"]), float(call["speed"]))
        for call in RUST_CALL.finditer(source[start:end])
    ]


def by_piece_axis(calls: list[Call]) -> dict[tuple[str, str, str], list[tuple[float, float]]]:
    """Commands on different piece axes in one keyframe run in the same frame,
    so only the order per piece axis matters."""
    result: dict[tuple[str, str, str], list[tuple[float, float]]] = {}
    for kind, piece, axis, target, speed in calls:
        result.setdefault((kind, piece.lower(), axis), []).append((target, speed))
    return result


def check_idle(lua_path: Path, source: str) -> int:
    """wisp_idle.lua's keyframes 0 and 20 against apply_wisp_idle_frame and
    apply_wisp_idle_frame_20.  Turns must match exactly.  The port's moves are
    relative to each piece's authored offset (constructSkeleton made Lua's
    values absolute), so each piece axis may differ from Lua's by one constant
    offset, the same in both keyframes, with the same speed."""
    lua = lua_keyframes(lua_path)
    if lua.get(30):
        raise ValueError(f"{lua_path}: terminal keyframe is expected to be empty")
    offsets: dict[tuple[str, str], float] = {}
    counts = {"turn": 0, "move": 0}
    for time, function in ((0, "apply_wisp_idle_frame"), (20, "apply_wisp_idle_frame_20")):
        if time not in lua:
            raise ValueError(f"idle: Lua has no keyframe {time}")
        left, right = by_piece_axis(lua[time]), by_piece_axis(rust_calls(source, function))
        if left.keys() != right.keys():
            raise ValueError(
                f"idle: keyframe {time} commands differ: only in Lua {sorted(left.keys() - right.keys())}, "
                f"only in Rust {sorted(right.keys() - left.keys())}")
        for key in sorted(left):
            if len(left[key]) != len(right[key]):
                raise ValueError(f"idle: keyframe {time} {key}: Lua has {len(left[key])} commands, Rust {len(right[key])}")
            for (lua_target, lua_speed), (rust_target, rust_speed) in zip(left[key], right[key]):
                if not math.isclose(lua_speed, rust_speed, abs_tol=1e-6):
                    raise ValueError(f"idle: keyframe {time} {key}: speed Lua={lua_speed} Rust={rust_speed}")
                if key[0] == "turn":
                    if not math.isclose(lua_target, rust_target, abs_tol=1e-6):
                        raise ValueError(f"idle: keyframe {time} {key}: target Lua={lua_target} Rust={rust_target}")
                else:
                    offset = lua_target - rust_target
                    known = offsets.setdefault(key[1:], offset)
                    if not math.isclose(known, offset, abs_tol=1e-4):
                        raise ValueError(
                            f"idle: {key[1]} {key[2]} move offset differs between keyframes: "
                            f"{known:.6f} then {offset:.6f} (keyframe {time})")
                counts[key[0]] += 1
    print(f"PASS: idle: 2 keyframes, {counts['turn']} Turn commands match Lua and "
          f"{counts['move']} Move commands match up to {len(offsets)} per-piece offsets")
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
            wisp = args.rust_source / "wisp"
            source = "\n".join(
                (wisp / name).read_text()
                for name in ("walk_legs.rs", "walk_arms.rs", "float_arms.rs")
            )
            idle_source = (wisp / "idle.rs").read_text()
        else:
            source = idle_source = args.rust_source.read_text()
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
        check_animation(
            "hover arms",
            args.lua_animations / "wisp_hover_arms.lua",
            source,
            "wisp_float_arms",
            None,
        )
        check_idle(args.lua_animations / "wisp_idle.lua", idle_source)
    except (OSError, ValueError, KeyError) as error:
        print(f"unit-script-source-compare: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
