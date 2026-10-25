# Lua/Wasm game measurements

`just verify perf mycube autonomous --output /absolute/run/path` stages private
copies of both games, uses one engine binary, one map, fixed seeds and settings,
and runs alternating Lua/Wasm pairs. Five repeats are the default. Source game
checkouts are never changed. `all` selects all seven game pairs. Run one campaign
at a time through `verify`, which owns the existing verification lock.

For Hunted, Flove, To the Last Drop and Area 17, plus **only fire effects**
from Gravitas, use:

```bash
SPRING_BAR_DIR=/path/to/matching/engine/checkout \
SPRING_ENGINE_DIR=/path/to/released/engine/install \
verification/perf/compare.sh "$PWD/perf-runs/my-comparison" \
    --frames 900 --warmup 300 --repeats 5
```

This runs the four normal game pairs, 10× initial-scene loads, and Gravitas
with 0, 1 and 10 fire emitter pairs. MyCube and Parts Needed are excluded.
The Area 17 10× case runs once: the full scene currently exceeds its Lua
memory and unit limits, so repeating that failure adds no timing evidence.
The script continues to the remaining cases and exits nonzero if any failed.
`summary.csv` and `summary.json` include only successful runs in timing
aggregates; attempted/completed counts retain the failures. Individual logs
and results preserve the reasons. Run directories must be empty to prevent
mixing old and new evidence.

Individual cases:

```bash
just verify perf comparison autonomous --frame-step --output /absolute/normal
just verify perf ttld autonomous --frame-step --unit-multiplier 10 --output /absolute/ttld-10x
just verify perf gravitas effects --effects-multiplier 10 --output /absolute/fire-10x
python3 verification/perf/report.py /absolute/campaign
just verify perf tests
```

`comparison` selects the four game pairs. `--frame-step` uses the same engine
capture mechanism as the golden galleries: one simulation step per rendered
frame with interpolation fixed. It runs as fast as the engine can draw; it
does not record a video. This keeps the number of renders comparable across
backends. The runner verifies exactly one draw for every measured simulation
frame. Five repeats alternate Lua-first and Rust-first order. `verify all`
includes the perf runner's seven regression tests, without launching benchmarks.

`--unit-multiplier N` clones each unit present at frame 60, including its
health and up to 32 queued orders. Normal creation handlers, scripts and AI
remain active. Counts by unit definition and team are recorded before cloning,
after cloning, and at the measurement window's start. Missing creations or an
unexpected immediate population fail the run. Later population changes remain
visible in CSV counters. The source games and their installed modules are not
changed. This is a crowded-scene stress test; copying a building can start its
spawner, and copying a player does not duplicate human input.

Gravitas reuses the existing fire parity fixture and Rust `fire-probe` feature.
It builds only into `verification/cache/target/gravitas-fire-probe`, then stages
the test UI module. Each emitter pair burns every frame and emits the original
flame/distortion effect every 15 frames, starting at frame 30. No units or
scenario run. The Lua particle classes and Rust renderer use the parity probe's
fixed inputs and seeds. The empty case measures each renderer's background
cost (the Rust gallery also draws map edges). This measures the isolated fire
renderer, rather than message transport or the entire Gravitas port.

Read times as **CPU-side elapsed milliseconds**, not GPU timestamps or FPS.
`frame.cpu_us` joins simulation and drawing for the same frame; it matters for
Gravitas because Lua emits inside simulation and the Rust probe emits during
UI update. The log also separates inclusive Lua/Wasm callin time and Wasm
import time/counts; those nested times must not be added together. Sampled peak
RSS includes loading and belongs to the whole engine process, not just the
language runtime. p50/p95 values in the campaign summary are medians of the
individual runs' p50/p95 values.

In engine 2026.10.25, the Wasm callin counter wraps `WasmCoreHost::Dispatch`,
but does not wrap the CUS `TickGuest` execution path. Whole simulation/draw
times still include it. Use the callin counters to locate work, rather than
subtracting them from total frame time to infer native-versus-guest cost.

The normal runs exercise autonomous startup gameplay. They are useful for
finding differences, but a language speedup requires matching active work.
The next gameplay scenarios should reuse the existing input/integration
fixtures: sustained rabbit waves in Hunted; all six firing mushroom types and
the spire in Flove; a fixed TTLD horde with the same Adrenaline state and held
attack; and an Area 17 UFO crossing the same defended base. Record population,
shots, damage, CEGs and API calls alongside timings. For laptop rendering/FPS
questions, add GPU timings and a representative camera path; simulation time
alone cannot identify a grass or fill-rate bottleneck.
For API/transport attribution, reuse the engine's existing
`test/native_api_parity/run_benchmarks_sdk.py` and its fixed Lua/native/Wasm
workloads (documented in `rts/wasm/docs/benchmarking.md`). Those already cover
dispatch, spatial queries, lists, commands, drawing, allocation and GC.

The default is GPU rendering through SDL offscreen at 100× simulation speed, with no desktop window. `--speed` controls simulation speed independently of the renderer. `--mode headless` selects CPU-only diagnostics. Errors and warnings make a run fail.

Options include `--frames 900 --warmup 300 --repeats 5`, `--mode headless|gpu`,
`--engine /path/to/install`, `--timeout 120`, and `--max-minutes 20`. Only the
runner's own engine process is terminated on a timeout. Completed results survive
an interruption. GPU rendering uses SDL offscreen without limiting simulation to real time. The runner
records host pressure and does not change CPU governors or stop other programs.

`scripted --input /path/to/actions.txt` gives both versions the same engine-side
input. Entries are ordered `frame: action` lines; `frame: local action` uses the
normal local command path. Example:

```
0: cheat
60: give 10 unit_name
90: local viewfree
```

The instrumented engine accepts these diagnostic environment variables:

- `SPRING_PERF_LOG`: CSV path. Empty/unset disables the frame log and counters.
- `SPRING_PERF_STOP_FRAME`: engine-side simulation frame limit, independent of Lua.
- `SPRING_PERF_INPUT`: ordered input file; no language-specific timing gadget.
- `SPRING_PERF_UNPAUSED=1`: requests normal `pause 0` commands when story/UI code
  pauses the single-player campaign. The runner enables this for autonomous runs.

CSV rows include simulation/draw time, inclusive Lua and Wasm callin time,
generated import-guard time/counts, alive units/projectiles/features/particles,
created/destroyed units, damage, commands, weapon fires, CEG requests, and draw
calls. Backend timers avoid double-counting recursive calls of the same kind.
Counters are local to the frame thread. Worker jobs need separate attribution.
The state digest quantizes positions/health and uses unit definition names rather
than backend-specific numeric definition IDs.

Every run records start scripts/settings, engine and content hashes, module hashes,
logs, frame CSVs, host samples, distributions, first state divergence and equality
of alive counters. Ratios and bootstrap intervals are descriptive. **All results
remain diagnostic** until full work equivalence, instrumentation overhead,
contention, and guest/transport/algorithm attribution have been reviewed. The
runner does not silently accept a result after a successful process exit.

Current limits: no automatic invulnerability patches, no lockstep/
attribution/counting mode, no per-gadget zones or per-import names, and no full
per-definition/script-call equivalence. The seven-game pilot found Lua headless
errors and workload divergence; see `perf-runs/2026-10-15-autonomous-diagnostic`.

## 2026-10-25 measurements

Engine **2026.10.25** (`dd05f8647458ff5541a8aee8d43b6218a64eaef8`),
i7-12700, GTX 1660 Ti, NVIDIA 580.178.04, SDL offscreen, 1024×736,
VSync off, one ThreadPool worker (the main thread). Each successful run has
900 simulation frames, a 300-frame warmup and exactly 600 measured draws.
Five alternating pairs per case; Area 17's full-scene stress case ran once.
The isolated Rust fire workload uses Gravitas's `a591b0c` verification probe.

Median combined simulation-and-draw CPU-side time, milliseconds per frame:

| Game | Normal Lua | Normal Rust | 10× Lua | 10× Rust |
| --- | ---: | ---: | ---: | ---: |
| Hunted | 1.01 | 1.46 | 8.16 | 5.15 |
| Flove | 1.59 | 1.47 | 6.17 | 3.93 |
| To the Last Drop | 4.53 | 6.87 | 45.53 | 46.86 |
| Area 17 | 2.59 | 2.26 | memory cap | unit cap |

These are the current ports' autonomous scenes, with their own features and
AI decisions. Flove has 182 Lua versus 193 Rust units normally, and 1,820
versus 1,930 after cloning. Hunted's populations and movement diverge too.
TTLD creates 5,910 units in each version at the scaling frame, then combat
changes the populations; its normal measured weapon fires differ (2,944 Lua
versus 2,421 Rust in the first pair). These differences belong beside the
timings rather than being attributed to language overhead.

The clearest normal-scene profiling targets are Hunted simulation (0.32 ms
Lua, 0.65 ms Rust) and TTLD drawing (2.25 ms Lua, 5.52 ms Rust). At 10×, TTLD
simulation alone reaches 36.82/38.66 ms, above the 33.33 ms budget for 30 Hz.
Area 17's LuaRules allocation reaches its 1.5 GiB cap during cloning. Rust
finishes the frame window, but 2,614 creations fail: the immediate scene has
10,676 units instead of the requested 13,290. Both stress runs fail and are
excluded from timing aggregates.

Gravitas's isolated fire workload, using the same combined metric:

| Emitter pairs | Lua ms | Rust ms |
| --- | ---: | ---: |
| 0 (background) | 0.292 | 0.291 |
| 1 | 0.547 | 0.557 |
| 10 | 2.760 | 2.202 |

The original five-frame fire image comparison also passes on this GPU
(0.021–0.040% region RMSE), and the installed production modules still match
a fresh build. The final campaign contains 100 successful runs, the two
Area 17 stress failures, and no detected CPU contention. Seven runner regression
tests pass through `just verify perf tests`.

[The CSV snapshot](results-2026-10-25.csv) contains p50/p95, populations,
callin/import measurements and whole-process peak RSS. Full provenance, CSV
frames and logs remain locally under `perf-runs/2026-10-25-comparison/`.
Earlier unstepped fire runs were excluded and retained separately under
`perf-runs/2026-10-25-rejected-fire-unstepped/`.
