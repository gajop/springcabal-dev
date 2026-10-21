#!/usr/bin/env python3
"""Compare the actual Cabal menu on native and Wasm, including keyboard input."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]


def capture(window, path):
    subprocess.run(["import", "-window", window, str(path)], check=True)
    with Image.open(path) as image:
        return hashlib.sha256(image.convert("RGB").tobytes()).hexdigest()


def keys(args, *values):
    if args.wine:
        codes = {"Down": 40, "Right": 39, "Up": 38, "Return": 13, "Escape": 27}
        subprocess.run([str(args.wine), "Z:" + str(args.output.resolve() / "wine-input.exe").replace("/", chr(92)), *[str(codes[value]) for value in values]], check=True)
        return
    for value in values:
        subprocess.run(["xdotool", "keydown", value], check=True)
        time.sleep(0.1)
        subprocess.run(["xdotool", "keyup", value], check=True)
        time.sleep(0.1)


def window_for(process, wine):
    command = ["xdotool", "search", "--onlyvisible"]
    command += ["--name", ".*"] if wine else ["--pid", str(process.pid)]
    found = subprocess.run(command, capture_output=True, text=True)
    for window in reversed(found.stdout.splitlines()):
        geometry = subprocess.run(["xdotool", "getwindowgeometry", "--shell", window], capture_output=True, text=True).stdout
        if "WIDTH=1280\n" in geometry and "HEIGHT=720\n" in geometry:
            return window
    return None


def worker(args):
    run = args.output.resolve()
    env = os.environ.copy()
    if args.packaged:
        for name in ["SPRING_ISOLATED", "SPRING_WRITEDIR", "SPRING_DATADIR"]:
            env.pop(name, None)
    def path_arg(path):
        return "Z:" + str(path).replace("/", chr(92)) if args.wine else str(path)
    # Absolute POSIX paths also reach Wine's host-side Fontconfig.
    env.update(LIBGL_ALWAYS_SOFTWARE="1", LP_NUM_THREADS="2", RAYON_NUM_THREADS="2", FONTCONFIG_FILE=str(run / "fonts.conf"))
    command = [*([str(args.wine)] if args.wine else []), path_arg(args.engine.resolve())]
    if not args.packaged:
        command += ["--window", "--isolation", f"--isolation-dir={path_arg(run)}",
                    f"--write-dir={path_arg(run / 'write')}", "--config", path_arg(run / "write/springsettings.cfg"),
                    "--menu=WasmMenu 1.0"]
    with (run / "stdout.log").open("w") as log:
        process = subprocess.Popen(command, cwd=run.parent if args.packaged else run, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            deadline = time.monotonic() + 60
            window = None
            while time.monotonic() < deadline and process.poll() is None:
                candidate = window_for(process, args.wine)
                library = "NativeMenu.dll" if args.wine else "libNativeMenu.so"
                marker = f"Successfully loaded native module WasmMenu/{library}" if args.backend == "native" else "Wasm manifest loaded from WasmMenu/manifest.json"
                if candidate and marker in (run / "stdout.log").read_text(errors="replace"):
                    window = candidate
                    break
                time.sleep(0.1)
            if window is None:
                raise RuntimeError("menu did not initialize and open a window")
            subprocess.run(["xdotool", "windowfocus", window], check=True)
            subprocess.run(["xdotool", "mousemove", "--window", window, "1279", "719"], check=True)
            time.sleep(2)
            initial = capture(window, run / "initial.png")
            keys(args, "Down", "Right")
            time.sleep(0.5)
            selected = capture(window, run / "selected.png")
            if initial == selected:
                raise RuntimeError("keyboard navigation did not change the rendered menu")
            returned = None
            if args.content_root or args.packaged:
                keys(args, "Up", "Return")
                deadline = time.monotonic() + 90
                while time.monotonic() < deadline and process.poll() is None:
                    if "finished loading and is now ingame" in (run / "stdout.log").read_text(errors="replace"):
                        break
                    time.sleep(0.1)
                else:
                    raise RuntimeError("menu launch did not reach the real game")
                time.sleep(1)
                window = window_for(process, args.wine)
                subprocess.run(["xdotool", "windowfocus", window], check=True)
                capture(window, run / "game.png")
                before = (run / "stdout.log").read_text(errors="replace").count("[LuaMenuController::Activate(msg=")
                keys(args, "Escape")
                deadline = time.monotonic() + 45
                while time.monotonic() < deadline and process.poll() is None:
                    if (run / "stdout.log").read_text(errors="replace").count("[LuaMenuController::Activate(msg=") > before:
                        break
                    time.sleep(0.1)
                else:
                    raise RuntimeError("game did not return to the menu")
                time.sleep(2)
                window = window_for(process, args.wine)
                subprocess.run(["xdotool", "mousemove", "--window", window, "1279", "719"], check=True)
                time.sleep(0.2)
                returned = capture(window, run / "returned.png")
                if returned != initial:
                    raise RuntimeError("returned menu differs from initial menu")
            keys(args, "Escape")
            code = process.wait(timeout=15)
            if code:
                raise RuntimeError(f"menu exited with {code}")
            text = (run / "stdout.log").read_text(errors="replace")
            failures = [line for line in text.splitlines() if any(word in line.lower() for word in ["panicked", "trap:", "callin failed", "module fault", "could not load", "warning:", "error:"])]
            if failures:
                raise RuntimeError("\n".join(failures))
            if args.packaged and "[DataDirLocater::Check] Isolation Mode!" not in text:
                raise RuntimeError("packaged launch did not enable isolation")
            result = {"ok": True, "initial": initial, "selected": selected, "returned": returned, "exit": code}
            if args.packaged:
                result.update(command=command, cwd=str(run.parent), isolation=True)
            (run / "result.json").write_text(json.dumps(result, indent=2) + "\n")
            return result
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--target-dir", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--content-root", type=Path, help="existing Cabal spring-linux directory; copies Lua Gravitas and its dependencies for a launch/return test")
    parser.add_argument("--wine", type=Path, help="Wine loader for a Windows engine; use a dedicated prefix")
    parser.add_argument("--packaged", action="store_true", help="test the actual bundle executable with no arguments, from outside its directory")
    parser.add_argument("--backend", choices=["native", "wasm"], help=argparse.SUPPRESS)
    parser.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if not args.packaged and args.target_dir is None:
        parser.error("--target-dir is required unless --packaged is used")
    if args.worker:
        worker(args)
        return 0
    if args.output.exists():
        raise RuntimeError("output must be a new directory")
    results = {}
    for transport in (["wasm"] if args.packaged else ["native", "wasm"]):
        run = args.output.resolve() / transport
        if args.packaged:
            shutil.copytree(args.engine.resolve().parent, run, symlinks=True)
            engine = run / args.engine.name
        else:
            stage_development(args, run, transport)
            engine = args.engine.resolve()
        (run / "fonts.conf").write_text('<fontconfig><dir prefix="relative">fonts</dir><cachedir prefix="relative">fontcache</cachedir></fontconfig>')
        write = run if args.packaged else run / "write"
        write.mkdir(exist_ok=True)
        if args.wine:
            subprocess.run(["x86_64-w64-mingw32-gcc", "-Wall", "-Wextra", "-Werror", "-O2", str(ROOT / "verification/sdk-menu/wine-input.c"), "-o", str(run / "wine-input.exe")], check=True)
        with (write / "springsettings.cfg").open("a" if args.packaged else "w") as config:
            config.write("\nSound = 0\nFullscreen = 0\nWindowBorderless = 1\nXResolutionWindowed = 1280\nYResolutionWindowed = 720\nVSync = 0\n")
        subprocess.run(["xvfb-run", "-a", sys.executable, str(Path(__file__).resolve()), "--worker", "--engine", str(engine), "--output", str(run), "--backend", transport,
                        *(["--target-dir", str(args.target_dir.resolve())] if args.target_dir else []),
                        *(["--packaged"] if args.packaged else []),
                        *(["--wine", str(args.wine.resolve())] if args.wine else []),
                        *(["--content-root", str(args.content_root.resolve())] if args.content_root else [])], check=True)
        results[transport] = json.loads((run / "result.json").read_text())
    if not args.packaged and results["native"] != results["wasm"]:
        raise RuntimeError(f"native and Wasm menu rendering differs: {results}")
    (args.output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(results, indent=2))
    return 0


def stage_development(args, run, transport):
    menu = run / "games/WasmMenu.sdd"
    shutil.copytree(ROOT / "wasm-menu", menu, ignore=shutil.ignore_patterns("wasm-src", "*.wasm", "*.so", "*.dll", "*.dylib"))
    if transport == "native":
        source = "x86_64-pc-windows-gnu/release/wasm_menu.dll" if args.wine else "release/libwasm_menu.so"
        library = "NativeMenu.dll" if args.wine else "libNativeMenu.so"
        shutil.copy2(args.target_dir / source, menu / "WasmMenu" / library)
    else:
        shutil.copy2(args.target_dir / "wasm32-unknown-unknown/release/wasm_menu.wasm", menu / "WasmMenu/wasm-menu.wasm")
    for name in ["base", "fonts"]:
        shutil.copytree(args.engine.parent / name, run / name)
    if args.content_root:
        for name in ["Interfaces", "Skirmish/NullAI"]:
            shutil.copytree(args.engine.parent / "AI" / name, run / "AI" / name, ignore=shutil.ignore_patterns("*.dbg", "*.a", "*.lib"))
        for name in ["Gravitas.sdd", "Scenario-Editor-Core.sdd", "Scenario-Editor-Gravitas.sdd"]:
            shutil.copytree(args.content_root / "games" / name, run / "games" / name, ignore=shutil.ignore_patterns(".git", "target", "wasm-src"))
        shutil.copytree(args.content_root / "maps/Gravitas-map.sdd", run / "maps/Gravitas-map.sdd", ignore=shutil.ignore_patterns(".git"))
        shutil.copytree(args.content_root / "projects/Gravity-Enterprise", run / "projects/Gravity-Enterprise", ignore=shutil.ignore_patterns(".git"))


if __name__ == "__main__":
    raise SystemExit(main())
