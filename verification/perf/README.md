# Lua/Wasm game measurements

Open the [HTML benchmark explorer](../../docs/benchmarks/2026-10-26/index.html)
with `bash verification/perf/serve.sh` and visit `http://127.0.0.1:8784/`.
To serve it to your Tailscale devices, run
`bash verification/perf/serve.sh "$PWD/docs/benchmarks/2026-10-26" 8784 "$(tailscale ip -4)"`
and open `http://<this-machine's-Tailscale-IP-or-DNS-name>:8784/`.
The arguments are the site directory, port and bind address; the default address is localhost.
It includes paired intervals and individual runs, exact frame traces, synchronized
world recordings, CPU flame graphs, source-backed analysis and follow-up experiments.
The generated site also opens directly from disk, with no CDN dependencies.

`dashboard.py` rebuilds it from saved runner evidence; `capture.sh` saves actual
unit/projectile observations for dots playback, `capture-profiles.sh` samples CPU
stacks without that observer, and `capture-video.sh` records the real GPU fire
renderer through the existing screenshot action. Capture runs never enter timing
aggregates. The observer records every six simulation frames, rounds coordinates
and health to two decimals, and changes no game state or RNG.

Use `dashboard.py --supplemental-timings /path/to/replacement-root` to replace
named campaigns with fresh runs while retaining earlier evidence. Later roots
take precedence; their own provenance, traces and game hashes are used.

The scene lab compares exclusive sampled CPU costs from a complete profile
pair with matching engine, game code, renderer, jobs setting and worker count.
Main-thread and other-thread totals stay separate from elapsed frame times.
Frozen game copies carry `source-commits.json`; replay/video selection checks
these revisions and module hashes so newer timings cannot select older code.

World recordings are stored as `world.jsonl.gz`, with a verified uncompressed
SHA-256 in `result.json`. The dashboard accepts both this format and older raw
JSONL. It streams snapshots rather than retaining all diagnostic fields in RAM.
Profiling uses perf's native compression. After export, the derived
`cpu.injected.data` is removed; the raw capture and JIT inputs remain available.
Video capture removes PNGs after verifying the 200-frame MP4; use `--keep-frames`
to retain them.
When recording a frozen effects campaign, pass its `--games-dir`,
`--effects-module` and `--worker-threads` to `capture-video.sh` so the video
uses the same game code, probe module and worker count as its timings.

To compact completed older runs without removing measurements or logs:

```bash
python3 verification/perf/compact.py perf-runs
```

This uses the verification lock, compresses and verifies world recordings,
removes their redundant write-directory copies, and drops reproducible profile
intermediates. New runs require 40 GiB free by default (`--min-free-gib`), and
stop their own engine if free space falls below 20 GiB during capture.

The idle gate checks both CPU pressure and actual background CPU utilization.
Pressure alone can stay low when other work has available cores. New captures
require ten quiet seconds with at most 0.5 logical cores of background CPU use
(`--max-background-cpu-cores`), and abort if that limit is exceeded while running.
The runner and its child processes are excluded using Linux process CPU counters,
including live children and reaped-child time. Samples and the guard's source
hash are recorded; missing or inconsistent counters reject a capture. Older
runs without this guard remain labeled with their original pressure policy.

CPU activity is guarded from launch through the first CPU sample after the
recorded final-frame marker, including the interval that straddles that marker.
Later shutdown samples remain saved but do not reject already completed frames.
A missing or incomplete marker retains the full-process CPU guard. Complete
frames, draws, timing markers and a clean engine exit are still required.

`profile_export.py --buildid-dir ...` resolves the pinned engine's matching debug
symbols and injects Wasmtime JIT names. Its flame graph retains actual sampled
stacks and explicit unresolved frames. It does not invent a complete call hierarchy
when unwinding stops. Sampler/recorder work is kept separate from timing baselines.

GPU runs always use the idle guard, including world recordings and videos.
The guard requires ten quiet seconds before launch and monitors NVIDIA clients
throughout the run. Competing compute clients, other Spring renderers, or active
graphics clients (including the desktop) interrupt the capture; the pair is excluded. Global
and selected-cgroup CPU pressure must both stay below the contention threshold.
Idle waits release the verification lock so other work can proceed. No user
interaction, minimized applications or engine changes are required.

All primary comparisons use NVIDIA OpenGL rendering. CPU flame graphs measure
CPU execution, including driver submission and waiting; they do not measure GPU
execution time. Gravitas jobs controls separately update particle curves on the
CPU while retaining GPU graphics. Its primary Lua/Rust comparison uses GPU
particle updates in both languages.

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

This runs the four normal game pairs, 10× initial-scene loads for Hunted,
Flove and TTLD, Area 17 at 2×, Flove's mushroom combat input, TTLD with
shadows enabled on both versions at 1×/10×, and Gravitas with 0, 1 and 10
fire emitter pairs. MyCube and Parts Needed are excluded. Area 17's full
10× scene exceeded its Lua memory and Rust unit limits in the earlier campaign;
the default matrix uses the working 2× case. The script continues to the
remaining cases and exits nonzero if any failed.
`summary.csv` and `summary.json` include only successful runs in timing
aggregates; attempted/completed counts retain the failures. Individual logs
and results preserve the reasons. Run directories must be empty to prevent
mixing old and new evidence.

`--repeats` is a minimum number of attempted pairs, rather than an attempt
limit. For five clean pairs, use `--repeats 5 --clean-pairs 5`; the runner can
retry interrupted pairs. Separate profiles or world captures need
`--repeats 1 --clean-pairs 1` when one complete matching pair is sufficient.


For a before/after optimization comparison within one backend, use
`--backend lua` or `--backend wasm` and `--games-dir /path/to/frozen/games`.
The default remains both backends and the normal checkout directory. Run one
repeat from each revision, reverse revision order on the next pair, and keep
the engine, map, settings and scene parameters identical. The staged content
and module hashes identify each revision even before its changes are committed.
Source A/B manifests default to both languages; set `"backends": ["lua"]`
or `["wasm"]` for a change affecting only that language. Only its complete,
clean before/after rounds enter the optimization table.

For Rust fire changes, build each `--features fire-probe` revision from the
same checkout/compiler path, then preserve the two Wasm files separately.
Use `--effects-module /absolute/frozen-probe.wasm` to measure those exact
artifacts instead of rebuilding from a source tree that may have changed.
The probe SHA-256 and staged module hashes remain in the saved provenance.

The mushroom combat input used for the optimization campaign is included:

```bash
just verify perf flove scripted --frame-step --repeats 5 \
    --input "$PWD/verification/perf/scenarios/flove-mushrooms.txt" \
    --output /absolute/flove-combat
```

It adds 150 normal, 150 small and 50 big enemy mushrooms at frame 60, with
normal AI and combat active. The runner freezes a copy of the input file in
the output directory and records its hash before starting the first engine.

Jobs comparisons use the same staged modules in both modes:

```bash
just verify perf hunted autonomous --backend wasm --rust-jobs compare \
    --worker-threads 4 --frame-step --repeats 5 --output /absolute/hunted-jobs
verification/perf/compare-jobs.sh /absolute/jobs-campaign --repeats 5
```

`--rust-jobs compare` alternates `off` and `on` order, keeps their timing
aggregates separate and compares their frame state and event counters. It
requires `--backend wasm`. `on` selects the jobs path; `check` also compares
each worker output with inline computation and is excluded from timing
comparisons. A request fails if the staged game has no jobs API import.
`jobs_active` records whether a run actually dispatched work. The default
remains `off`.

`--worker-threads N` sets the total engine ThreadPool width, including the
main thread; the runner checks the effective width in the engine log. Compare
jobs enabled/disabled at the same width. Pool width also affects native
engine work in Lua games. `compare-jobs.sh` measures jobs at widths 1 and 4,
adds Lua/serial-Rust controls at width 4, and includes dense mushroom combat
and 100 fire emitter pairs to test larger pure workloads. TTLD and Area 17
have pool-width controls without a game job kernel. `--wait-for-idle` waits
before a run while the existing CPU-pressure threshold is exceeded; the
jobs campaign enables it. Runs that become contended are still marked and
excluded as before.

`report.py` writes `jobs-summary.csv`/`.json` separately from Lua/Rust pairs.
The job summaries contain `off`/`on` timing columns and paired job-on time
changes, rather than relabeling them as languages. The default backend
summaries also keep the two job modes separate.

Existing game assertion and screenshot suites can exercise jobs with
`VF_RUST_JOBS=check VF_WORKER_THREADS=4` and can select alternate checkouts
with the existing `VF_GAMES_DIR`. These options only affect staged verification
scripts/settings. Production launch profiles are unchanged.

The pressure guard defaults to the machine-wide `/proc/pressure/cpu`.
`--cpu-pressure-scope cgroup` instead uses the runner's unified cgroup
`cpu.pressure`, inherited by its engine children. It records both readings
and the selected file path. The same threshold of 5 applies; a missing scoped
reading fails closed. This is useful when an unrelated task oversubscribes
its restricted CPU set while the benchmark's scope has no CPU wait. It
does not change CPU affinity, scheduler priority or the threshold.

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
includes the perf runner's 35 regression tests, without launching benchmarks.

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
cost. Both emit locally in UI Update and use the same stepped frame schedule;
the performance fixture disables map borders and Rust gallery walls. This
measures the isolated fire renderer, rather than message transport or the entire
Gravitas port.

The current report uses `--require-current-effects-fixtures` to exclude older
fire harnesses. Their captures remain historical evidence. Source A/B rounds
require identical saved fixture hashes, and fire videos must match those hashes
as well as the engine, game revision and Wasm modules.

The per-frame simulation/draw distributions are **CPU-side elapsed milliseconds**,
not GPU timestamps or FPS. Stepped GPU runs also record
`window_wall_ms_per_frame`: elapsed time between engine log markers at the
start and end of the measured window, divided by its frame count. This includes
main-loop work, buffer swaps and waits outside the simulation/draw scopes;
it excludes loading and shutdown. The existing engine input/echo commands
supply these markers, and the effective input and its hash are preserved.
`frame.cpu_us` joins simulation and drawing for the same frame.
The log also separates inclusive Lua/Wasm callin time and Wasm
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

The default is GPU rendering through SDL offscreen at 100× simulation speed, with no desktop window. GPU runs fail if the engine does not report a renderer or selects llvmpipe, softpipe, swrast, SwiftShader or Software Rasterizer. Each result records the actual renderer. `--speed` controls simulation speed independently of the renderer. `--mode headless` selects CPU-only diagnostics. Errors and warnings make a run fail.

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

`report.py` writes `paired-summary.csv` and `.json` alongside the backend
summaries. A pair enters these aggregates only if both runs succeeded and
neither reported CPU contention. It reports simulation, drawing, combined CPU
and full-window elapsed time, with paired Rust/Lua changes and bootstrap
intervals. An excluded or missing partner excludes the whole pair.

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

## Optimized Lua/Rust with GPU rendering

This compares the optimized source commits listed above directly, using the
released engine **2026.10.25** (`dd05f8647458ff5541a8aee8d43b6218a64eaef8`).
Its executable SHA-256 is
`d28e6c2f0cb889f7b7ab148ae9c80e1c3480d1c6b5c3425aec284f783af0193d`.
The renderer reported by every run is **NVIDIA GeForce GTX 1660 Ti/PCIe/SSE2**,
NVIDIA 580.178.04, through SDL offscreen. No software rendering enters these
timings. The engine and production game sources were unchanged during this
comparison.

Each case has five alternating Lua/Rust pairs: 300 warmup frames, then exactly
600 simulation/render steps at 1024×736, VSync off and one ThreadPool worker.
The table measures complete elapsed time for that window, including main-loop
work and buffer swaps outside the narrower CPU timers. Values are medians of
the five runs' mean milliseconds per frame. The change column is the median
of paired Rust/Lua time changes; negative means Rust takes less time.

| Scene | Lua ms/frame | Rust ms/frame | Rust time change |
| --- | ---: | ---: | ---: |
| Hunted, normal | 1.109 | 0.993 | -10.5% |
| Hunted, 10× initial scene | 8.728 | 3.879 | -55.1% |
| Flove, normal | 1.638 | 1.723 | +5.2% |
| Flove, 350 mushrooms | 5.566 | 4.703 | -16.6% |
| Flove, 10× initial scene | 5.375 | 4.870 | -10.7% |
| TTLD, shipping defaults | 4.862 | 6.631 | +36.4% |
| TTLD, 10×, shipping defaults | 57.697 | 58.019 | +0.5% |
| TTLD, shadows on in both | 5.586 | 6.336 | +13.4% |
| TTLD, 10×, shadows on in both | 60.113 | 57.042 | -4.5% |
| Area 17, normal | 3.319 | 2.980 | -9.1% |
| Area 17, 2× initial scene | 8.391 | 7.679 | -7.4% |
| Gravitas, empty fire background | 0.409 | 0.386 | -4.8% |
| Gravitas, 1 emitter pair | 0.632 | 0.605 | -4.3% |
| Gravitas, 10 emitter pairs | 3.433 | 1.803 | -48.1% |

Hunted and Area 17 favor Rust in both measured loads. Flove favors Lua in its
quiet scene, then Rust in mushroom combat and at 10×. TTLD favors Lua normally;
with shadows matched at 10×, Rust takes 4.5% less time. The shipping-default
10× TTLD result is effectively tied: its paired mean-ratio bootstrap interval
includes 1 (0.986–1.013). Heavy Gravitas fire favors Rust by 48% in complete
elapsed time.

These are the current game implementations with their features retained.
Flove has 182 Lua versus 193 Rust units normally, and 1,820 versus 1,930 at
10×; Rust retains its animated outlines and mouse hover. Hunted's startup
sequence and the ports' combat decisions can diverge. TTLD's first normal pair
records 2,944 versus 2,421 weapon fires. The matched-shadow rows align that
setting without removing Rust's shadows from the shipping profile. These
scene results do not isolate language execution from those workload differences.

All **140 runs / 70 pairs** in this table pass the existing frame, error and
hardware-renderer checks, with exactly 600 measured renders apiece. No pair
was flagged for CPU contention (maximum sampled CPU-pressure avg10: 2.30,
threshold: 5). NVIDIA telemetry was recorded throughout; GPU utilization
reached 100%, and temperature peaked at 63°C. The original 40 preliminary GPU
runs, which had only the narrower CPU timers, are retained separately within
the same output tree and excluded from this table.

[The comparison CSV](gpu-comparison-2026-10-25.csv) records source commits,
simulation/draw p50 and p95, combined CPU timing, full-window timing, pair
counts, populations and paired bootstrap intervals. Full logs, frame CSVs,
effective inputs, provenance and `gpu-samples.csv` remain locally under
`perf-runs/2026-10-25-optimized-gpu/`. `final-comparison.json` and
`gpu-audit.json` contain the final table and renderer audit.

`verification/perf/compare.sh` now reproduces this matrix through the existing
verification runner. Its report excludes both members of a failed, incomplete
or contended pair. Ten performance-framework regression tests pass, including
input/marker ordering, wall-window boundaries and pair exclusion. No game or
engine source change was needed for this comparison.

## Optional Rust jobs with GPU rendering

At pool width 4, these job kernels produce no clear whole-frame win. The
default remains serial Rust (`rust_jobs=off`). The table gives complete-window
milliseconds per frame; lower is faster. Off/on are the same Rust build at the
same pool width. The last column is the median paired on/off time change.

| Scene | Off, pool 1 | On, pool 1 | Off, pool 4 | On, pool 4 | Jobs change, pool 4 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Hunted, normal | 1.026 | 1.137 | 1.066 | 1.177 | +10.1% |
| Hunted, 10× initial scene | 3.708 | 3.979 | 3.459 | 3.560 | +3.1% |
| Flove, 350 mushrooms | 4.924 | 4.858 | 4.483 | 4.541 | +1.3% |
| Flove, 3,500 mushrooms | 85.345 | 85.429 | 70.568 | 70.697 | +0.0% |
| Gravitas, 1 emitter pair | 0.557 | 0.831 | 0.582 | 0.766 | +31.0% |
| Gravitas, 10 emitter pairs | 1.689 | 2.544 | 1.691 | 1.707 | +1.2% |
| Gravitas, 100 pairs (32K cap) | 5.993 | 8.607 | 5.885 | 6.180 | +6.9% |

Each row has five alternating pairs per width, except the dense Flove pool-1
case: one CPU-pressure exclusion leaves four accepted pairs. [The jobs CSV](jobs-comparison-2026-10-26.csv)
contains simulation/draw p50 and p95, full-window timing, paired intervals,
state/event agreement, source commits and counts. Hunted retains the startup
variation described above; Flove records identical frame states and events
between off/on in every accepted pair.

In Hunted's normal pool-4 case, median simulation import time rises from
13 to 105 microseconds per frame with jobs. Most of the added time is inside
the host calls, consistent with worker-store and packet overhead outweighing
the savings from parallel light calculations here.

The October 26 comparison adds opt-in same-tick jobs to Hunted's rabbit light
sensing, Flove's mushroom target statistics and Gravitas's fire billboards.
`rust_jobs=off` remains the production default. `on` dispatches pure work;
`check` additionally checks every returned packet against inline computation.
Read-only state is snapshotted on the calling thread; workers make no engine
calls. RNG, commands and mutations retain their original order. Gravitas's
check mode also compares the final expanded vertices with its serial renderer,
float bit for float bit.

Each batch targets four chunks, with ordered results; Gravitas splits further
when needed to fit both input and output packet limits. Small dedicated
worker modules have no imports and fixed 8 MiB memories. Flove reuses worker
scratch storage and reads weights lazily from shared output packets.
Gravitas encodes fixed float records in bulk, transfers 13 floats per billboard
and expands its six vertices on the calling thread. This avoids transferring
the 54-float expanded geometry.
The released API copies packets and creates a fresh private store for each
job, so dispatching a small calculation can cost more than doing it inline.

The comparison pins the same released engine, SDK and NVIDIA GPU as the
preceding table. It alternates five off/on pairs at total engine pool widths
1 and 4, and five Lua/serial-Rust pairs at width 4. Width includes the main
thread. Every run uses 300 warmup steps and 600 measured simulation/render
steps, 1024×736, VSync off. Complete-window elapsed time includes main-loop
work and swaps. Check-mode runs never enter timing aggregates. Both members
of a pair are excluded if either fails or exceeds the existing CPU-pressure
threshold.

`verification/perf/compare-jobs.sh` reproduces the matrix through the existing
verification runner. Hunted and Flove include 10× initial scenes; the Flove
combat input creates 350 mushrooms before scaling. Gravitas uses 1, 10 and
100 fire emitter pairs. TTLD with shadows enabled in both ports, and Area 17,
are Lua/Rust controls at pool width 4; neither receives an artificial game
job kernel for work already performed by the native engine.

The 100-emitter stress case exceeds Rust's existing 32,768-particle ceiling;
both Rust job modes retain that ceiling. The Lua effects fixture has no such
ceiling, so its 100-emitter row includes a particle-budget difference. The
1- and 10-emitter scenes stay below the ceiling.

This matrix selects `--cpu-pressure-scope cgroup`: both global and application
cgroup readings are retained, and the threshold remains 5. Another task's
restricted CPU set drove global pressure high while this scope had zero CPU
wait. A deliberate three-second contention check raised this scope's avg10
from 0 to 15.76, proving the guard detects actual scoped wait. CPU affinity,
scheduler priority and engine configuration are unchanged by this selection.

```bash
verification/perf/compare-jobs.sh /absolute/jobs-campaign \
    --cpu-pressure-scope cgroup --repeats 5 --frames 900 --warmup 300 \
    --timeout 180 --max-minutes 40
```

The shared helper is [09cd1d0](https://github.com/gajop/springcabal-rs/commit/09cd1d03d9fdec06c614fd29d978606096eb9378).
The public Rust game branches contain:

| Game | Source |
| --- | --- |
| Hunted | [e916b24](https://github.com/SpringCabal/Hunted/commit/e916b24080968f6fdbc7b0a3c6674e236d68163f) |
| Flove | [26869d0](https://github.com/SpringCabal/Flove/commit/26869d0) |
| Gravitas | [801119c](https://github.com/SpringCabal/Gravitas/commit/801119c) |

The initial canonical jobs builds passed all 22 existing standard verification
runs, including 123 host tests. Jobs check mode passes on the three games at
both pool widths. The targeted integration suites pass Hunted's 36 checks,
Flove's 66 rules, 10 UI and 8 scenario checks, and Gravitas's 19 end-to-end
checks. Flove's packet-reuse follow-up passes its integration suite and both
pool-width checks again. Gravitas's final packet bounds and bulk encoding pass
checks at 100 emitter pairs at both widths. Both final games pass installed-module matching.
The existing five-frame Lua/Rust fire image comparison remains below
0.025% RMSE in every frame, against the unchanged 0.1% threshold.

The independent Lua/Rust control pairs at pool width 4 give these complete
window times. These Rust values come from separate serial runs from the off/on
pairs above. The ports retain their implementation differences described earlier.

| Scene | Lua ms/frame | Serial Rust ms/frame | Rust time change |
| --- | ---: | ---: | ---: |
| Hunted, normal | 1.143 | 1.054 | -8.3% |
| Hunted, 10× initial scene | 7.211 | 3.427 | -53.5% |
| Flove, 350 mushrooms | 5.359 | 4.385 | -18.2% |
| Flove, 3,500 mushrooms | 80.688 | 70.275 | -12.9% |
| Gravitas, 1 emitter pair | 0.609 | 0.592 | -2.4% |
| Gravitas, 10 emitter pairs | 3.425 | 1.712 | -48.7% |
| TTLD, shadows on in both | 5.428 | 6.410 | +15.6% |
| TTLD, 10×, shadows on in both | 33.560 | 43.835 | +30.8% |
| Area 17, normal | 2.639 | 2.272 | -13.5% |
| Area 17, 2× initial scene | 6.510 | 5.837 | -11.6% |

Rust takes less time in these Hunted, Flove, Area 17 and fire scenes; Lua is
faster in TTLD. [The Lua/Rust CSV](jobs-lua-controls-2026-10-26.csv) includes all
11 controls and labels the separate 100-emitter particle-budget difference.

All **250 GPU runs / 125 attempted pairs** finish with 600 measured renders
each on the NVIDIA GeForce GTX 1660 Ti. One contended Flove pair is excluded,
leaving **124 accepted pairs**. All 70 job-enabled runs dispatch work. The
performance framework passes 16 regression tests. Full logs, frame CSVs,
source/module hashes, both CPU-pressure readings and `final-audit.json` remain
locally under `perf-runs/2026-10-26-jobs/scoped/`; GPU telemetry is in
`perf-runs/2026-10-26-jobs/scoped-gpu-samples.csv`. Earlier packet-encoding
measurements are preserved separately and excluded from these final tables.

The optimization audit adds diagnostic controls to the same runner:

- `--cpu-affinity 0,2,4,6,8,10,12,14` holds this i7-12700 on its eight P cores.
  Requested CPUs must be available. Process samples retain every observed thread's
  affinity; a thread escaping the requested set rejects the run. Host samples
  include CPU frequencies; GPU-process samples include clocks, power and temperature.
- GPU monitoring runs on a separate thread, keeping the one-second `nvidia-smi`
  sample out of the 20 ms perf sampling controller. Other Spring/Recoil, GL replay
  and compute clients remain exclusions. Xorg/compositor samples are retained but
  are not classified as independent workloads; presentation can charge activity
  to them. Busy other graphics clients are retained and excluded.
- `--record-world --record-details --record-every 1` adds camera state, full
  precision positions/heading/velocity, commands, movement attributes and dimensions.
  Headless mode permits these simulation-only diagnostics; performance comparisons
  still require NVIDIA rendering. Recorded/instrumented runs do not enter timings.
- `--trace-gl --apitrace /absolute/apitrace` captures the GL command stream through
  EGL in a separate diagnostic run. Tracer warnings remain errors in the result;
  they must be inspected before interpreting a replay. Never count a trace as an
  uninstrumented timing run.
- TTLD comparisons set `skip_intro=1` in both versions and require its startup
  marker. The game option skips only the intro; normal launch profiles keep it.

The pinned engine's Wasm callback counter does **not** include CUS guest ticks.
The unscoped remainder therefore includes CUS as well as native work and waits;
subtracting measured callbacks does not isolate native execution.

The world observer and stress cloning use `GameFramePost`, after Lua, Wasm,
native physics and CUS ticks finish. Recordings include this phase in their
header. Earlier `GameFrame` captures observed Lua and Wasm at different phases.
Detailed captures also retain front/up/right vectors after position, heading
and velocity.

Gravitas defaults to GPU particle curves on both sides. `--fire-renderer cpu`
selects the Rust CPU reference for a jobs off/on comparison; `--rust-jobs on`
with the GPU renderer does not move shader work to CPU workers.

`--clean-pairs 5 --repeats 5` continues alternating pairs after a contended
run until five complete uncontended pairs exist. All rejected attempts remain
in the output. The time limit and a six-times-count bound still apply. This
controls contention only; world, workload and visual equivalence require their
separate evidence. Detailed diagnostic recordings collect garbage every thirty
samples to keep uncapped headless captures within the Lua memory budget.

Primary game comparisons use one engine worker. HAPFS dispatches path requests
through the shared pool; three identical rendered Lua Flove runs at width four
already diverge in path state at frame 61 or 91. Width-one Lua/Rust Flove runs
match through frame 2400 in two pairs. Width-four Lua controls and Rust jobs
remain separate measurements, with their observed trajectories retained.

Hunted's autonomous fixture sets `benchmark_no_input=1` in both UIs. Otherwise
SDL/desktop mouse state generates gun targets, asynchronous messages and unit
creation even though the scenario supplies no input. The option defaults off
in normal gameplay. GPU runs require an acknowledgement from the UI.

`capture-video.sh OUTPUT` records all core normal/stress scenes, Gravitas
1/10/100 emitter pairs and normal My Cube/Parts Needed scenes with the existing
screenshot action. Each clip is 200 real GPU PNGs at three-frame intervals,
encoded at 10 fps; ffprobe checks the output count. `--case NAME` selects one
scene and `--encode-only` reuses saved PNGs. `--games-dir PATH` (or
`VF_GAMES_DIR`) selects the frozen game roots and is forwarded to every runner
invocation. Captures disable callback timers; `--max-minutes N` controls the
idle-wait limit. Never include these runs in timings.

For a same-behavior source comparison, pass `dashboard.py --optimizations
/path/to/experiments.json`. Each experiment lists five rounds with `before` and
`after` campaign directories (including explicit retry directories). The report
uses the first clean Lua/Rust pair from each phase, accepts only complete
four-run rounds, and rejects changed engine binaries or scene parameters.
Callback/import counters overlap: imports from direct CUS ticks are outside
the dispatch timer, so do not subtract import time from dispatch time.


Use `dashboard.py --allow-incomplete` for a snapshot while the timing campaign
is running. Unstarted scenes remain pending, with no fabricated measurements;
confidence intervals require five clean pairs. The report shows its generation
time and the number of scenes that reached five pairs. CPU profiles carry their
own engine commit, binary SHA-256 and callback-timer mode.

The exporter also resolves unknown JIT addresses from retained `jit-*.dump`
code-load records. This covers perf versions whose JIT injection passes compressed
event blocks through. Resolution requires the matching process, an unambiguous
address range and a load timestamp preceding the sample. Unsupported clocks,
moving code and overlapping registrations remain unresolved. This recovers names;
it does not invent missing unwind parents. Each profile records the dump hashes
and number of frames resolved this way.
