#!/usr/bin/env python3
"""Describe the current Cargo inputs and warn about older installed WASM modules."""

import argparse
import functools
import json
import subprocess
import sys
from pathlib import Path

SOURCE_SUFFIXES = {".rs", ".rml", ".rcss", ".vert", ".frag", ".glsl", ".wgsl"}
SOURCE_NAMES = {"Cargo.toml", "Cargo.lock", "rust-toolchain.toml", "manifest.txt", "manifest.json"}


def git(directory, *arguments):
    return subprocess.run(
        ["git", "-C", str(directory), *arguments],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
    ).stdout.strip()


@functools.cache
def checkout(directory):
    try:
        root = Path(git(directory, "rev-parse", "--show-toplevel"))
    except subprocess.CalledProcessError:
        return None
    return root


@functools.cache
def revision(root):
    branch = git(root, "rev-parse", "--abbrev-ref", "HEAD")
    commit = git(root, "rev-parse", "HEAD")
    dirty = " +uncommitted changes" if git(root, "status", "--porcelain") else ""
    return f"{branch} {commit}{dirty}"


@functools.cache
def source_files(root):
    files = git(root, "ls-files", "-z", "--cached", "--others", "--exclude-standard")
    return {
        root / name for name in files.split("\0") if name
        and (Path(name).suffix in SOURCE_SUFFIXES or Path(name).name in SOURCE_NAMES)
    }


def inspect(workspace, modules):
    metadata = json.loads(subprocess.check_output([
        "cargo", "metadata", "--offline", "--locked", "--format-version", "1",
        "--manifest-path", str(workspace / "Cargo.toml"),
    ], cwd=workspace))
    inputs = {workspace / "Cargo.toml", workspace / "Cargo.lock"}
    for package in metadata["packages"]:
        source = package["source"]
        if source and source.startswith("registry+"):
            continue
        directory = Path(package["manifest_path"]).parent
        if source:
            description = source
        else:
            root = checkout(directory)
            description = f"local {directory}"
            if root:
                description += f" ({revision(root)})"
                inputs.update(source_files(root))
            else:
                inputs.update(
                    path for path in directory.rglob("*")
                    if "target" not in path.parts and
                    (path.suffix in SOURCE_SUFFIXES or path.name in SOURCE_NAMES)
                )
        if package["id"] not in metadata["workspace_members"]:
            print(f"  dependency {package['name']}: {description}")

    # Cargo also reads ancestor configuration; Area 17 generates code from spawn.lua.
    for parent in (workspace, *workspace.parents):
        inputs.update(parent / ".cargo" / name for name in ("config", "config.toml"))
    inputs.add(workspace.parent / "LuaRules/Configs/spawn.lua")
    if workspace.parent.name == "wasm-menu":
        project = workspace.parent.parent
        for name in ("launch/games", "game-info"):
            inputs.update((project / name).rglob("*"))

    oldest_module = min(module.stat().st_mtime_ns for module in modules)
    newer = [path for path in inputs if path.is_file() and path.stat().st_mtime_ns > oldest_module]
    if newer:
        newest = max(newer, key=lambda path: path.stat().st_mtime_ns)
        print(
            f"warning: {workspace.parent.name}: source input {newest} is newer than "
            "the installed WASM modules; rebuild before shipping",
            file=sys.stderr,
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("workspace", type=Path)
    parser.add_argument("modules", nargs="+", type=Path)
    args = parser.parse_args()
    inspect(args.workspace.resolve(), [module.resolve() for module in args.modules])


if __name__ == "__main__":
    try:
        main()
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        sys.exit(f"WASM source inspection failed: {error}")
