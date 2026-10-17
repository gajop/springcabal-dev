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


def worker(args):
    run = args.output.resolve()
    env = os.environ.copy()
    env.update(LIBGL_ALWAYS_SOFTWARE="1", LP_NUM_THREADS="2", RAYON_NUM_THREADS="2", FONTCONFIG_FILE=str(run / "fonts.conf"))
    command = [str(args.engine.resolve()), "--window", "--isolation", f"--isolation-dir={run}",
               f"--write-dir={run / 'write'}", "--config", str(run / "write/springsettings.cfg"),
               "--menu=WasmMenu 1.0"]
    with (run / "stdout.log").open("w") as log:
        process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            deadline = time.monotonic() + 60
            window = None
            while time.monotonic() < deadline and process.poll() is None:
                found = subprocess.run(["xdotool", "search", "--pid", str(process.pid)], capture_output=True, text=True)
                lines = found.stdout.splitlines()
                if lines and any(marker in (run / "stdout.log").read_text(errors="replace") for marker in ["Native module initialized successfully", "Wasm manifest loaded from WasmMenu/manifest.json"]):
                    window = lines[-1]
                    break
                time.sleep(0.1)
            if window is None:
                raise RuntimeError("menu did not initialize and open a window")
            subprocess.run(["xdotool", "windowfocus", window], check=True)
            subprocess.run(["xdotool", "mousemove", "--window", window, "1279", "719"], check=True)
            time.sleep(2)
            initial = capture(window, run / "initial.png")
            subprocess.run(["xdotool", "key", "--window", window, "Down", "Right"], check=True)
            time.sleep(0.5)
            selected = capture(window, run / "selected.png")
            if initial == selected:
                raise RuntimeError("keyboard navigation did not change the rendered menu")
            returned = None
            if args.content_root:
                subprocess.run(["xdotool", "key", "--window", window, "Up", "Return"], check=True)
                deadline = time.monotonic() + 90
                while time.monotonic() < deadline and process.poll() is None:
                    if "finished loading and is now ingame" in (run / "stdout.log").read_text(errors="replace"):
                        break
                    time.sleep(0.1)
                else:
                    raise RuntimeError("menu launch did not reach the real game")
                time.sleep(1)
                window = subprocess.check_output(["xdotool", "search", "--pid", str(process.pid)], text=True).splitlines()[-1]
                capture(window, run / "game.png")
                before = (run / "stdout.log").read_text(errors="replace").count("[LuaMenuController::Activate(msg=")
                subprocess.run(["xdotool", "key", "--window", window, "Escape"], check=True)
                deadline = time.monotonic() + 45
                while time.monotonic() < deadline and process.poll() is None:
                    if (run / "stdout.log").read_text(errors="replace").count("[LuaMenuController::Activate(msg=") > before:
                        break
                    time.sleep(0.1)
                else:
                    raise RuntimeError("game did not return to the menu")
                time.sleep(2)
                window = subprocess.check_output(["xdotool", "search", "--pid", str(process.pid)], text=True).splitlines()[-1]
                subprocess.run(["xdotool", "mousemove", "--window", window, "1279", "719"], check=True)
                time.sleep(0.2)
                returned = capture(window, run / "returned.png")
                if returned != initial:
                    raise RuntimeError("returned menu differs from initial menu")
            subprocess.run(["xdotool", "key", "--window", window, "Escape"], check=True)
            code = process.wait(timeout=15)
            if code:
                raise RuntimeError(f"menu exited with {code}")
            text = (run / "stdout.log").read_text(errors="replace")
            failures = [line for line in text.splitlines() if any(word in line.lower() for word in ["panicked", "trap:", "callin failed", "module fault", "could not load", "warning:", "error:"])]
            if failures:
                raise RuntimeError("\n".join(failures))
            result = {"ok": True, "initial": initial, "selected": selected, "returned": returned, "exit": code}
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
    parser.add_argument("--target-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--content-root", type=Path, help="existing Cabal spring-linux directory; copies Lua Gravitas and its dependencies for a launch/return test")
    parser.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.worker:
        worker(args)
        return 0
    if args.output.exists():
        raise RuntimeError("output must be a new directory")
    results = {}
    for transport in ["native", "wasm"]:
        run = args.output.resolve() / transport
        menu = run / "games/WasmMenu.sdd"
        shutil.copytree(ROOT / "wasm-menu", menu, ignore=shutil.ignore_patterns("wasm-src"))
        if transport == "native":
            shutil.copy2(args.target_dir / "release/libwasm_menu.so", menu / "WasmMenu/libNativeMenu.so")
        else:
            shutil.copy2(args.target_dir / "wasm32-unknown-unknown/release/wasm_menu.wasm", menu / "WasmMenu/wasm-menu.wasm")
        for name in ["base", "fonts", "AI"]:
            shutil.copytree(args.engine.parent / name, run / name)
        if args.content_root:
            for name in ["Gravitas.sdd", "Scenario-Editor-Core.sdd", "Scenario-Editor-Gravitas.sdd"]:
                shutil.copytree(args.content_root / "games" / name, run / "games" / name, ignore=shutil.ignore_patterns(".git", "target", "wasm-src"))
            shutil.copytree(args.content_root / "maps/Gravitas-map.sdd", run / "maps/Gravitas-map.sdd", ignore=shutil.ignore_patterns(".git"))
            shutil.copytree(args.content_root / "projects/Gravity-Enterprise", run / "projects/Gravity-Enterprise", ignore=shutil.ignore_patterns(".git"))
        (run / "fonts.conf").write_text('<fontconfig><dir prefix="relative">fonts</dir><cachedir prefix="relative">fontcache</cachedir></fontconfig>')
        write = run / "write"
        write.mkdir()
        (write / "springsettings.cfg").write_text("Sound = 0\nFullscreen = 0\nWindowBorderless = 1\nXResolutionWindowed = 1280\nYResolutionWindowed = 720\nVSync = 0\n")
        subprocess.run(["xvfb-run", "-a", sys.executable, str(Path(__file__).resolve()), "--worker", "--engine", str(args.engine.resolve()), "--target-dir", str(args.target_dir.resolve()), "--output", str(run), *(["--content-root", str(args.content_root.resolve())] if args.content_root else [])], check=True)
        results[transport] = json.loads((run / "result.json").read_text())
    if results["native"] != results["wasm"]:
        raise RuntimeError(f"native and Wasm menu rendering differs: {results}")
    (args.output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(results, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
