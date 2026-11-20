# Engine compatibility, 1 November 2026

Engine tag `2026.11.0103` resolves to
`858328c47a04ec1ed33547e9682367fd4840a625`. It fails to load To the Last Drop's
UI and the Parts Needed candidate with restored cloud rendering. The engine
repair is committed and pushed to `gajop/spring-rust`'s public `rust-wip` branch.
The replacement
[pre-release, `2026.11.0104`](https://github.com/gajop/spring-rust/releases/tag/2026.11.0104),
is published with Linux and Windows binaries, from
`96574c7e80eac7898f0738c2abebff0c1a38b2aa`.

## Confirmed missing API

The upstream merge removed `GameApi.GetWindVector` and the published Wasm import
`spring:game/get-wind-vector`. The existing integration suites report:

```text
Failed to initialize Core Wasm module ttld-ui:
unknown or unavailable Core Wasm import: spring:game.get-wind-vector
```

The Parts Needed candidate reports the same error for `partsneeded-ui`.
TTLD uses the vector for fire drift; Parts Needed uses it for cloud movement.
`get_wind()` supplies wind strength, not its direction, so it cannot replace this
call while preserving the effects.

[The engine fix](https://github.com/gajop/spring-rust/commit/96574c7e80eac7898f0738c2abebff0c1a38b2aa)
restores the native function, generated SDK/import definitions and native API
snapshots. It adds `get_wind_vector` to the existing Lua/native/Wasm parity
framework, comparing all three components against `Spring.GetWind`. The existing
wind tolerance is unchanged. The earlier standalone restoration patch is retained
as historical evidence; use the actual engine fix instead.

All nine local checks passed, including strict generated-code reproducibility,
SDK Clippy, 284 Rust unit/doc tests, 13 parity-framework tests and the native
parity module build. Both automatic source workflows passed, including the
Windows native Rust checks. A separate
[CI guard](https://github.com/gajop/spring-rust/commit/46c917e63a959726febca8337cf58d845c447a60)
now compiles the existing native parity fixture during automatic Wasm API checks;
that workflow also passed. The official
[Linux/Windows release build](https://github.com/gajop/spring-rust/actions/runs/41297823122)
succeeded. Both downloaded runtime archives match GitHub's release-asset SHA-256
digests; the tested Linux workflow archive matches the final published archive.

The official Linux `2026.11.0104` binary passes both focused parity runs:
Lua/native comparisons with three cases, and the typed Core Wasm comparison.
The native reference contains nonzero X/Z wind values; the Wasm comparison reports
no missing results, mismatches or vacuous results. Parts Needed's existing
no-render integration suite now passes. TTLD initializes its UI and passes all 58
gameplay assertions; its no-render suite still exits unsuccessfully because the
headless engine warns that shadows are unsupported. That raw failure remains
recorded and does not count as a graphics pass.

## Other changes reviewed

| Change | SpringCabal result |
| --- | --- |
| GLTF piece axes, upstream #3321 | No `.glb` or `.gltf` assets occur in the 14 Lua/Wasm game trees. No asset conversion was changed. |
| One-based weapon numbers, `32b6c0ffb4` | Already present in the previous engine pin, `782c0e8a`. Audited setters use one-based slots. Projectile `weapon_num: 0` is the documented sentinel for no firing weapon instance. |
| Weapon-definition IDs | Remain zero-based. Keep the separate fixes for collectors that skipped definition zero. |
| Write-directory fallback, `4a2e322a19` | Already present in `782c0e8a`; existing verification supplies an explicit isolated write directory. Windows fallback checks remain pending. |
| Near plane, `19910b9dac` | Already present in `782c0e8a`. Rendered scenario checks remain pending. |
| Headless draw throttle, `4e04bef331` | Already present in `782c0e8a`. Reran the existing no-render integration checks on the new official binary. |

## Existing checks rerun

The initial `2026.11.0103` campaign completed 12 no-render checks: native host tests (144), performance-runner
unit tests (60), unit-script source comparison, Flove integration, MyCube Rust
integration and Gravitas Lua rules passed. Parts Needed and TTLD failed at the
missing import. Area17 and Gravitas reported RmlUi texture warnings; MyCube Lua
reported unavailable `gl.UseShader` in the no-render engine. The texture-warning
checks still require their rendered suites; their raw warnings were retained.

The MyCube Lua error was traced to a private optimization candidate removing the
original shaderless map-edge fallback. The same removal existed in the Hunted
Lua candidate. Both original fallbacks are restored in committed QA candidates;
the MyCube no-render check and all 22 Hunted Lua regression assertions now pass
against `2026.11.0103`.
These complete rendering candidates remain private until their NVIDIA output
checks pass. Their public Lua branches already retain the original fallbacks.
The existing four-worker checked-jobs integration checks for Hunted and Flove
also pass as no-render correctness checks.

Hunted exposed a separate test error. Its recoil assertion assumed that every
shot recoils upward. Traces on both engine versions show that an uphill shot
correctly recoils downward. The existing assertion now checks speed 20 and
alignment opposite the actual muzzle-to-target vector. All 40 assertions passed
on `2026.10.3103` and `2026.11.0103`. The test-only snapshot is excluded from normal builds;
normal fmt, Clippy and module builds also passed. The fix is committed on
[Hunted's public rust branch](https://github.com/SpringCabal/Hunted/commit/45fe6ebb143288a4021aa9ad04f3c14e72a8b9c5).

The 20 November runs used the official Linux `2026.11.0104` headless binary
and the existing candidate checkouts. They staged temporary files on the project
drive because the pinned engine warns when looking up the host's RAM-backed
`/tmp` as a block device.

| Game | Result |
| --- | --- |
| Flove | Serial and four-worker checked-jobs suites passed. Each run passed 66 rules, 10 UI input and 13 scenario assertions. The checked-jobs run exercised mushroom targeting. |
| Hunted | Serial and four-worker checked-jobs suites passed, each with 22 Lua regression checks and 40 Rust assertions. The checked-jobs run exercised rabbit lighting. |
| My Cube | Rust passed all 32 integration assertions. The Lua archive reached the existing startup check's frame limit with zero engine warnings or errors. |
| Area 17 | All 23 Rust and six Lua gameplay assertions ran successfully. The suite failed on five RmlUi texture warnings. All five files exist in the candidate archive. |
| Gravitas | The Lua rules and B.O.B. suites passed. Rust's level spawned all 543 units and initialized the HUD. Its smoke test failed on the RmlUi warning for the existing `heart.png` asset. |

The release's no-render RmlUi backend returns an empty texture handle for every
request. The Area 17 and Gravitas failures remain recorded under the existing
warning checks. Both still need their rendered suites.
[Engine source](https://github.com/gajop/spring-rust/blob/96574c7e80eac7898f0738c2abebff0c1a38b2aa/rts/Rml/Backends/RmlUi_Renderer_Headless.h)

The 43 existing checks in the `2026.11.0104` NVIDIA plan remain pending. Its
dedicated worker ended while the machine stayed busy. Rendered checks still
require the CPU/GPU quiet guards and global verification lock. The active Flove
visual checks and Gravitas timings use the `2026.10.3103` benchmark engine.

Detailed inputs, logs and receipts are retained locally under
`codex-work/engine-2026.11.0103/` and `codex-work/engine-2026.11.0104/`.
The current candidate view uses the existing
private optimization worktrees; it does not adopt their unreviewed rendering
changes onto the public game branches.
