# Engine compatibility: 2026.10.3103

Engine and SDK commit: [`782c0e8a6837ec0b8ecf5f38a4d4815debc8119a`](https://github.com/gajop/spring-rust/tree/782c0e8a6837ec0b8ecf5f38a4d4815debc8119a).
[Official Linux and Windows prerelease](https://github.com/gajop/spring-rust/releases/tag/2026.10.3103) · [successful build](https://github.com/gajop/spring-rust/actions/runs/41162664369).

The [29 October review](engine-compatibility-2026-10-29.md) covers rc.2 through
engine `0f0ee80`. All 16 additional commits through this release are listed below.
The merge retains the nine earlier SpringCabal fixes absent from the other
current development branch.

| Commit | Change | SpringCabal action |
| --- | --- | --- |
| [`a64fa38`](https://github.com/gajop/spring-rust/commit/a64fa3832aac61df13fc6f9d6e7bf5ed46ce8639) | GPU memory diagnostics | Diagnostic command only; no game migration. |
| [`505d85d`](https://github.com/gajop/spring-rust/commit/505d85d816895c474a306d84bed97d436a3bedc8) | Model LOD and shattered-index storage controls | Keep existing defaults; do not remove model detail from either benchmark side. |
| [`3c7153e`](https://github.com/gajop/spring-rust/commit/3c7153e7f4a4fd6e2dcccd98583ac0a7b5890eb8) | Mip skipping for named images | Keep TextureMipSkip at zero in both versions. |
| [`b17feaa`](https://github.com/gajop/spring-rust/commit/b17feaa7332df9aa90e2bd53b74046b88f1b0ad6) | Opaque-model depth prepass and overdraw diagnostics | Prepass remains off; retain the existing material paths. |
| [`c13fea1`](https://github.com/gajop/spring-rust/commit/c13fea14dc77fbfaf74f088b5e98b6d6eac2f483) | Thread-pool completion returns when the submitted work is done | Use the new default; rerun jobs off/on at native pool widths 1 and 4. Thread-pool tests pass 2,035,923 assertions. |
| [`9a18e93`](https://github.com/gajop/spring-rust/commit/9a18e9346688a180d19a5683ecbe5bab952f5a92) | Prelinked Wasm job programs with InstancePre | Keep fresh stores and ordered results. Retest packet sizes on this runtime; use its built-in job clock for separate diagnostics. |
| [`7278faf`](https://github.com/gajop/spring-rust/commit/7278faf7cc7eeb01d2b956e422674e696f4ca2d6) | RmlUi damage rectangles, program reuse and configurable MSAA | Keep default damage rectangles and MSAA=2. Existing game images and real-input controls pass. |
| [`250ef4f`](https://github.com/gajop/spring-rust/commit/250ef4f10c9e3e5a0fd2fb0d2c010d65d319cce3) | Shadow-caster LOD and receiver culling options | New culling options stay off. Retain the same shadows and geometry in both versions. |
| [`55747b9`](https://github.com/gajop/spring-rust/commit/55747b9b375e97ce9c5ee5d60674fc215d824c9a) | Cache transforms and draw positions for resting features | Use the new default; existing game golden images pass. |
| [`4a2e322`](https://github.com/gajop/spring-rust/commit/4a2e322a196e06392a8eb28927be85f71b71254f) | Windows write-directory checks, UTF-8 file paths and menu errors | Retain the isolated portable layout. Check the official Windows executable under Wine during final packaging. |
| [`4e04bef`](https://github.com/gajop/spring-rust/commit/4e04bef331eb61fb067ae75ebb3b86fbbf934d5b) | Headless-only drawing and simulation pacing | No rendered-build change. All performance runs and in-game verification here use the NVIDIA rendering build. |
| [`365b448`](https://github.com/gajop/spring-rust/commit/365b44813b83257769968cf76a168de30a1e65ff) | Bulk unit-property API and SDK columns | Pin the SDK to the merged commit. Test scalar versus bulk reads at both loads; do not assume fewer calls improve frame time. |
| [`9c1ba39`](https://github.com/gajop/spring-rust/commit/9c1ba392280fc68721b77cdb5d9a404a65d6bcd6) | Columns ABI and performance documentation | Documentation only. |
| [`961cacb`](https://github.com/gajop/spring-rust/commit/961cacb807c27d0593d53a003d212f6d87a24c58) | Document the engine version required by columns | Collection instructions select the tested 2026.10.3103 release. |
| [`1f6ad86`](https://github.com/gajop/spring-rust/commit/1f6ad86067a82e6aaa63061135d9aca354f2a103) | Refresh the spatial index after native midpoint/radius changes | Match Lua RemoveUnit/MovedUnit conditions. Fourteen ordered-query checks and normal/10x detailed world comparisons pass. |
| [`782c0e8`](https://github.com/gajop/spring-rust/commit/782c0e8a6837ec0b8ecf5f38a4d4815debc8119a) | Merge current changes with the previous SpringCabal parity fixes | Preserve the prior movement, spatial-query, RNG, wind and weapon fixes instead of replacing them with the other development branch. |

Weapon-control arguments remain one-based; CUS weapon callbacks and array
offsets remain zero-based. No additional weapon-number migration is introduced.

Native damage delivery calls `WorldHitByWeapon`. Lua's unit-script adapter
forwards that call to the game's `HitByWeapon` handler; the Rust house must
register the world callback directly. TTLD's previous Rust registration missed
ordinary damage and therefore never set `on_fire`. The game fix registers
`WorldHitByWeapon` and retains the Lua threshold and unchanged damage return.
The existing gameplay suite now applies 400 and 401 damage through the real
engine API, checking that only the latter ignites the house. This fix requires
no additional engine change.

The optimized local engine passes 2,075,698 assertions in the RNG, NaN-sink,
synced-jobs and thread-pool tests. All 31 existing game/host/installed/input/pose
and golden-image checks pass with NVIDIA rendering. Local profiling and official
CI executables have distinct recorded hashes; every timing pair uses one exact
executable. Published game bundles use the official CI archives.

The current normal and 10x Hunted and Flove worlds match across Lua, scalar Rust,
bulk reads and jobs; the bulk-read width-4 checks also pass. Source A/B trials
and the final matrix retain their own module and binary identities. Full engine
review, check receipts and archive digests are exported in the benchmark
report's `engine-current-audit.json`.
