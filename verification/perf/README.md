# Lua/Wasm game measurements

`just verify perf mycube autonomous --output /absolute/run/path` stages private
copies of both games, uses one engine binary, one map, fixed seeds and settings,
and runs alternating Lua/Wasm pairs. Five repeats are the default. Source game
checkouts are never changed. `all` selects all seven game pairs. Run one campaign
at a time through `verify`, which owns the existing verification lock.

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

Current limits: no automatic invulnerability/scaling patches, no lockstep/load/
attribution/counting mode, no per-gadget zones or per-import names, and no full
per-definition/script-call equivalence. The seven-game pilot found Lua headless
errors and workload divergence; see `perf-runs/2026-10-15-autonomous-diagnostic`.
