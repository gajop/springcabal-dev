The menu uses `spring-sdk` on both backends. Its RML, navigation, launch settings
and game catalogue are shared. Cargo pins the public engine SDK revision in
`wasm-menu/wasm-src/Cargo.toml`. Run `./setup.sh --no-dev-engine` before a release
build so a local engine path patch cannot replace that revision.

Build `wasm-menu/wasm-src` with `just build` and `just build-native`.
`just copy` installs Wasm; `just copy-native` installs the Linux native menu.
The engine prefers native when both files are present. Remove the generated
`WasmMenu/libNativeMenu.so` to select Wasm again.

`run.py` takes `--engine`, `--target-dir` and a new `--output` directory. It stages
copies of the menu and engine resources, renders both backends under Xvfb,
navigates with actual keyboard input, and quits through Escape. Every screenshot
must match between native and Wasm; navigation must change the screen.

Add `--content-root /path/to/spring-linux` to copy Lua Gravitas, its dependencies,
map and project into that test directory. The test launches through the menu,
waits for the real game, returns with Escape and compares the restored menu to
the first screenshot. Source content is read only. This does not assert that the
seven Wasm game implementations behave correctly; their own suites cover that.
All seven game-code ports are now committed in their dedicated worktrees.

Use `--packaged --engine /path/to/bundle/SpringCabal --output NEW_DIRECTORY`
to test the released bundle itself. This copies the bundle, adds only the usual
test window/sound settings, then runs its executable with no arguments from a
different working directory. Menu selection, Lua Gravitas launch/return and
Escape-to-quit are checked using the packaged WASM menu and content. This mode
does not need `--target-dir`. Add `--wine` for a Windows `SpringCabal.exe` bundle.
Game and map archives are hardlinked when possible; settings, caches and logs
remain separate for each attempt. The harness creates its Fontconfig cache
before starting the engine, including the first launch in a fresh Wine prefix.

The official `2026.10.3001` Linux and Windows binaries passed this packaged
check with the public game sources in the local
`1.0.3-rc.3-runtime-check` bundles: NVIDIA rendering, no-argument launch from
outside the bundle, keyboard navigation, Lua Gravitas launch, return to the
same menu image, and exit status zero. Windows was checked under Wine, not on
native Windows. These bundles are unpublished compatibility checks; final Lua
performance choices are still pending.

Passed on 2026-10-17 against SDK commit `81cfe66192`: both backends launched and
returned from Gravitas, rendered identical initial/navigation/return screenshots,
and exited with zero status and no engine warnings or errors. Eight existing
menu tests and native/Wasm Clippy also pass.

Passed on 2026-10-18 under Wine with the Windows SDK engine: both backends
launched Lua Gravitas, returned to the menu, and quit with exit status zero.
Initial, navigation and return images match between backends. The logs contain
no warnings or errors. Native Windows hardware remains untested.

For Windows, build the menu for `x86_64-pc-windows-gnu` and pass `--wine` with
the loader path. Set `WINEPREFIX` to a dedicated test prefix and supply the
runtime's `WINELOADER`/`WINEDLLPATH` if it is not installed system-wide.
The harness compiles `wine-input.c` with `x86_64-w64-mingw32-gcc` and uses
Windows `SendInput` for real keyboard events, including scan codes and extended
arrow keys. X11 injection alone did not deliver reliable Wine keyboard input.
