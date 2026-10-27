# Fire renderer parity

Run from the workspace root:

```sh
just probe gravitas-fire lua
just probe gravitas-fire wasm
just probe gravitas-fire-compare
```

The Lua fixture stages `Gravitas.sdd` and invokes its original `EmitFlame`
and `onFireUnit` emitters, `SimpleParticles2` and `JitterParticles2` classes,
and `distortionFBO` shaders. The Rust fixture stages the same map/assets and
uses the Rust UI with the test-only `fire-probe` feature. Neither changes the
Lua source game or the engine. No fixture Lua is installed in the WASM game.

Both reconstruct trap fire (radius 500, speed 0.5, emitted every 15 frames)
and burning-unit fire/smoke (radius 25, supplied horizontal velocity
0.5/-0.25, emitted every frame). Camera, random samples, emission inputs,
particle ages, and distortion time are fixed. Five simulation states are
held long enough to avoid screenshot timing differences. The cursor is moved
away from the effects, but not to the screen edge where it would move the camera.

The fixture replaces randomness on both sides with a small-integer sequence
whose intermediate operations are exact even in Spring's float32 Lua build.
Production retains its normal RNG; the test checks how identical random
samples become rendered particles, not whether independent playthroughs
consume the same random sequence. The original Lua particle shaders are
unchanged. The test harness supplies the normal flame/heat/smoke draw order.

The comparison crops a 420x300 region containing both effects and the heat
footprint, excluding unrelated HUDs and the map edge. No pixels within that
region are masked. Normalized RGB RMSE must be below 0.1%. Artifacts are in
`verification/out/gravitas-fire-comparison/`; `pair-*.png` has Lua on the left
and Rust on the right.

Measured after the renderer fixes:

| Simulation frame | Fire-region RMSE |
| --- | --- |
| 90 | 0.03131% |
| 105 | 0.02050% |
| 120 | 0.02415% |
| 150 | 0.03308% |
| 180 | 0.01933% |

This demonstrates close renderer agreement for these controlled emissions,
not identical full-game playthroughs, all camera angles, or all GPU drivers.
The regular `gravitas.sh e2e` and `gravitas.sh shots` suites separately exercise
gameplay and the normal event path/RNG.

To install a normal, non-probe playable UI after testing:

```sh
cd spring-linux/games/Gravitas-wasm.sdd/wasm-src
cargo build -p gravitas-ui-wasm --release
cp target/wasm32-unknown-unknown/release/gravitas_ui_wasm.wasm ../LuaUI/wasm/gravitas-ui.wasm
```
# Frozen source comparisons

Set `VF_EFFECTS_MODULE=/absolute/path/to/fire-probe.wasm` when running the
Wasm fixture to compare already-built revisions from the same compiler path.
The usual build remains the default. The five fixed frames and fire-region
comparison are unchanged.

