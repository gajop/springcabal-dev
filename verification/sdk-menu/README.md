The menu uses `spring-sdk` on both backends. Its RML, navigation, launch settings
and game catalogue are shared. This port branch currently points Cargo at the
sibling `spring-sdk-unified` worktree; use its engine build for these checks.

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
seven Wasm game implementations have been ported.

Passed on 2026-10-17 against SDK commit `81cfe66192`: both backends launched and
returned from Gravitas, rendered identical initial/navigation/return screenshots,
and exited with zero status and no engine warnings or errors. Eight existing
menu tests and native/Wasm Clippy also pass. Native Windows remains to be tested
under Wine.
