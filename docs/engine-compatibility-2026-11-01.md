# Engine 2026.11.0103

Engine tag `2026.11.0103` resolves to
`858328c47a04ec1ed33547e9682367fd4840a625`. It currently fails to load To the Last
Drop's UI. The Parts Needed candidate with restored cloud rendering fails for
the same reason. This engine has not passed SpringCabal compatibility checks.

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

[The restoration patch](patches/engine-2026.11.0103-restore-wind-vector.patch)
restores the native function and its generated SDK/import definitions. It passes
`git apply --check` against `858328c47a`. The patch has not been built into a new
engine; the engine checkout and published release are unchanged.

## Other changes reviewed

| Change | SpringCabal result |
| --- | --- |
| GLTF piece axes, upstream #3321 | No `.glb` or `.gltf` assets occur in the 14 Lua/Wasm game trees. No asset conversion was changed. |
| One-based weapon numbers, `32b6c0ffb4` | Already present in the previous engine pin, `782c0e8a`. Audited setters use one-based slots. Projectile `weapon_num: 0` is the documented sentinel for no firing weapon instance. |
| Weapon-definition IDs | Remain zero-based. Keep the separate fixes for collectors that skipped definition zero. |
| Write-directory fallback, `4a2e322a19` | Already present in `782c0e8a`; existing verification supplies an explicit isolated write directory. Windows fallback checks still require the Windows runtime. |
| Near plane, `19910b9dac` | Already present in `782c0e8a`. Rendered scenario checks remain pending. |
| Headless draw throttle, `4e04bef331` | Already present in `782c0e8a`. Reran the existing no-render integration checks on the new official binary. |

## Existing checks rerun

The 12 no-render checks completed: native host tests (144), performance-runner
unit tests (60), unit-script source comparison, Flove integration, MyCube Rust
integration and Gravitas Lua rules passed. Parts Needed and TTLD failed at the
missing import. Area17 and Gravitas reported RmlUi texture warnings; MyCube Lua
reported unavailable `gl.UseShader` in the no-render engine. Those checks remain
failed and require their rendered suites; their warnings were retained.

Hunted exposed a separate test error. Its recoil assertion assumed that every
shot recoils upward. Traces on both engine versions show that an uphill shot
correctly recoils downward. The existing assertion now checks speed 20 and
alignment opposite the actual muzzle-to-target vector. All 40 assertions passed
on both engine versions. The test-only snapshot is excluded from normal builds;
normal fmt, Clippy and module builds also passed. The fix is committed on
[Hunted's public rust branch](https://github.com/SpringCabal/Hunted/commit/45fe6ebb143288a4021aa9ad04f3c14e72a8b9c5).

The new-engine NVIDIA queue reuses the existing `verify all`, `verify visual`,
Lua gameplay reviews and checked-jobs suites. It retains the CPU/GPU quiet guards
and global verification lock. These rendered checks are pending; no no-render
result is used as rendering or performance evidence. Existing benchmark results
remain pinned to their original engine, `2026.10.3103`.

Detailed inputs, logs and receipts are retained locally under
`codex-work/engine-2026.11.0103/`. The current candidate view uses the existing
private optimization worktrees; it does not adopt their unreviewed rendering
changes onto the public game branches.
