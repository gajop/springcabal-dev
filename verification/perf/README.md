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


For a before/after optimization comparison within one backend, use
`--backend lua` or `--backend wasm` and `--games-dir /path/to/frozen/games`.
The default remains both backends and the normal checkout directory. Run one
repeat from each revision, reverse revision order on the next pair, and keep
the engine, map, settings and scene parameters identical. The staged content
and module hashes identify each revision even before its changes are committed.

The mushroom combat input used for the optimization campaign is included:

```bash
just verify perf flove scripted --frame-step --repeats 5 \
    --input "$PWD/verification/perf/scenarios/flove-mushrooms.txt" \
    --output /absolute/flove-combat
```

It adds 150 normal, 150 small and 50 big enemy mushrooms at frame 60, with
normal AI and combat active. The runner freezes a copy of the input file in
the output directory and records its hash before starting the first engine.

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

These are the initial campaign results. The follow-up below fixes Hunted's
startup configuration and revisits TTLD's draw timing; keep that evidence
alongside this original snapshot.

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

The initial normal-scene profiling targets were Hunted simulation (0.32 ms
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

## Follow-up: Hunted startup LOS and TTLD repeatability

Hunted's Lua `LuaUI/Widgets/start_force.lua` enables global LOS for **all**
ally teams, including Gaia. The Rust port omitted that startup step. Linux
`perf` sampling with the released engine's debug symbols located substantial
Rust-run CPU time in native LOS circle/raycast updates. Those updates are
skipped when global LOS is enabled: this was additional engine work caused by
the port's configuration.

Hunted Rust commit `364d646` restores that behavior through the typed synced
control API on the first game frame. The existing flashlight/lighthouse pass
still hides and reveals rabbits. In the first 900-frame repeat, LOS raycast
cache misses drop from 11,949 to one. No engine change is required.

Using the same released engine, settings, seed, frame stepping and measurement
window, five alternating pairs per case give these medians of run p50s (ms):

| Case | Lua simulation | Rust simulation | Lua sim + draw | Rust sim + draw |
| --- | ---: | ---: | ---: | ---: |
| Hunted before fix | 0.331 | 0.664 | 1.080 | 1.491 |
| Hunted after fix | 0.312 | 0.244 | 1.008 | 0.931 |
| Hunted after fix, 10× initial units | 4.397 | 1.750 | 8.214 | 3.479 |
| TTLD repeated, unchanged | 3.708 | 3.329 | 8.149 | 7.018 |

Hunted's Rust simulation time falls 63%. Normal measured median populations
are 146 units in both ports after the fix; the stress case has 1,358 Lua and
1,350 Rust units. AI decisions and later populations still differ, so the
cross-language ratios describe these scenes rather than isolated runtimes.

TTLD's original draw slowdown does **not** repeat: Rust drawing is faster in
all five new pairs, with median draw p50s of 3.288 ms Rust and 4.277 ms Lua.
The staged content/module hashes, map hashes and settings match the initial
campaign. Both ports have 622 median units. The initial timing batch alone
does not identify a TTLD rendering regression; its production code is unchanged.

All 40 follow-up runs complete with exactly 600 measured draws and no detected
CPU pressure contention. [The follow-up CSV](optimization-2026-10-25.csv) records
simulation/draw p50/p95, populations and API counters. Full logs and provenance
remain in `perf-runs/2026-10-25-opt-{baseline-hunted,fixed-hunted,fixed-hunted-10x,baseline-ttld}/`.

The added startup LOS assertion fails on the old Hunted code and passes with
the fix. The existing suite now passes 36 integration checks, all 30 common
unit tests, strict Clippy, both Lua/Rust input checks, and installed-module
matching. The five-shot GPU visual scenario and HUD/restart assertions complete
without errors or warnings. Golden pixel comparisons are skipped through the
existing renderer-mismatch option because the references use Mesa software
rendering; this run uses NVIDIA. Goldens and tolerances are unchanged.

## Optimizing both implementations

The follow-up keeps engine **2026.10.25** and compares each backend with its
own frozen source revision. Normal cases use five alternating revision pairs;
crowded scenes use three. Every run measures frames 300–899, with exactly
600 draws. Pairs flagged by the existing CPU-pressure check are excluded from
the reported changes and repeated; their original evidence remains available.

Flove's Lua AI now gathers eligible targets once per AI tick, reuses weights
and reads command counts directly. It preserves target order and random draw
order. Both wisp renderers gather stage vertices once per draw frame and reuse
them across stage/reflection passes. Hunted's Lua movement uses scalar
coordinates instead of temporary vector tables; both implementations restrict
food searches spatially while retaining their original tie rules. Rust shares
static target snapshots until the roster changes.

Area 17 queries nearby civilians once, then keeps the original wanderer order
and strict base-position fear test. Lua's query includes a conservative model
midpoint offset. Cloak and idle handling are unchanged. TTLD rejects deferred
lights and mirrored terrain only when their full bounds are outside the
frustum; bloom, geometry and visible detail are retained.

Gravitas Lua caches compiled expression factories, returning a fresh function
for each mutable particle environment. Rust streams packed flame/smoke vertices
to reusable native buffers instead of calling the engine for every vertex.
Texture order, depth, blending, fog and the heat-distortion pass are retained.
At ten emitter pairs, median Rust drawing imports fall from 35,558 to 2,804 per
frame. A shape-based batching trial was slower and was discarded. A separate
Hunted iterator rewrite also showed no gain and was discarded.

The five Rust workspaces use whole-program release LTO and one code generation
unit. The isolated build trial reduced module sizes by 13–19% and Hunted's
normal combined CPU time by about 5%. Flove and TTLD had no clear whole-frame
gain from that build change alone; TTLD's measured guest draw-call time fell
about 5%.

| Case | Lua CPU cost change | Rust CPU cost change |
| --- | ---: | ---: |
| Flove, 350 mushrooms: simulation p95 | -79.2% | -2.7% |
| Flove, 10×: drawing p50 | -33.0% | -2.9% |
| Hunted, 10×: simulation p50 | -30.3% | -4.4% |
| TTLD, normal: drawing p50 | -11.6% | -6.7% |
| Area 17, normal: simulation p50 | -15.7% | -7.3% |
| Gravitas, 10 emitters: sim + draw p50 | -13.6% | -29.4% |

Changes above are medians of paired percentage changes, rather than ratios of
separately aggregated medians. [The CSV](both-backends-2026-10-25.csv) records
both raw medians, pair counts, pressure exclusions, API counts and bootstrap
intervals. Rows starting with `final-` include the final Rust release profiles;
other rows retain the earlier algorithm/rendering stage.

Flove, TTLD and Area 17 before/after runs preserve every recorded simulation
state digest, population and event counter in their measurement windows.
Hunted's autonomous startup mouse message can arrive on different frames even
with unchanged code, changing the first wave's random sequence. Its added Lua
movement/RNG and spatial tie/removal cases pass against both original and
optimized code; autonomous timings remain scene measurements.

TTLD's Rust lighting widget enables shadows while Lua starts with the shared
profile's shadows disabled. The included `ttld-shadows.txt` and
`ttld-shadows-off.txt` inputs measure that setting independently in staged
copies. In five alternating on/off pairs, enabling shadows raised drawing CPU cost by
27% in Lua and 42% in Rust; all five on/off pairs in each backend retained the same recorded state
digests, populations and event totals. Production visuals remain unchanged.

The final builds pass all 22 existing verification runs, including 120 host
unit tests, installed-module matching for all seven games, both versions’
real-input controls, 19,760 Flove pose samples and 105 exact TTLD pose samples.
The targeted Lua review probes pass 20 Hunted, 12 Flove and 13 Area 17 checks.
Flove's nine GPU goldens pass. The other scenario suites complete their
assertions and skip old Mesa pixels through the existing renderer-mismatch
option; goldens and tolerances are unchanged.

The existing five-frame fire comparison passes on Linux/NVIDIA and the
released Windows executable under Wine/Mesa, below its 0.1% threshold in every
frame. All six mushroom weapons fire and damage their targets in both versions.
The shared music probe verifies continued audio through at least three loops in both
versions. The wisp capture fixture now keeps camera/screenshot work unsynced,
and the fire fixture clears its platform-specific archive index between runs.

Raw timing, profiles, hashes and logs remain locally under
`perf-runs/2026-10-25-both-opt/`; verification artifacts remain under
`verification/out/`. The engine binary and SDK worktree were pinned throughout.

Source commits for this optimization pass:

| Game | Lua | Rust |
| --- | --- | --- |
| Hunted | [80615da](https://github.com/SpringCabal/Hunted/commit/80615da2c9b65dae8cef2b3d9f5ea614bdbd4a01) | [5bc1475](https://github.com/SpringCabal/Hunted/commit/5bc14750293b668ee1f94047fba1f57dfd22bcba) |
| Flove | [50f6ca6](https://github.com/SpringCabal/Flove/commit/50f6ca64bee6b499ada9f04e953ee2007361d51f) | [03d572c](https://github.com/SpringCabal/Flove/commit/03d572ca98b2c0277157be927db4726294cc7416) |
| Area 17 | [cf17232](https://github.com/SpringCabal/Area-17/commit/cf172327d24f3a65ab330cf4eb37ca0c594fcc7d) | [b99b0a1](https://github.com/SpringCabal/Area-17/commit/b99b0a1dfeb5cb47a7aad34e1e991c8c9169843b) |
| To the Last Drop | [e0a3605](https://github.com/SpringCabal/LD43/commit/e0a36052f911252a8d87bdf198ee8f541ef1f369) | [88193d5](https://github.com/SpringCabal/LD43/commit/88193d52c4c35ad3aee1a97e5d6cbfcb1aa6107d) |
| Gravitas | [3d6aea2](https://github.com/SpringCabal/Gravitas/commit/3d6aea2bac0ae38b644307cd988c5a6fbf1b72ed) | [41aa0b9](https://github.com/SpringCabal/Gravitas/commit/41aa0b92e5b14b2dd0468169a1a7d3cb06e2af26) |
