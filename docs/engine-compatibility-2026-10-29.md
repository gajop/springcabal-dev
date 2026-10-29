# Engine compatibility for the next SpringCabal prerelease

Previous prerelease: `v1.0.3-rc.2`, engine `dd05f8647458ff5541a8aee8d43b6218a64eaef8`.
Candidate: [`0f0ee80fa0ee620bc2988c64559feb3cbd163e10`](https://github.com/gajop/spring-rust/tree/0f0ee80fa0ee620bc2988c64559feb3cbd163e10).
The [previous review](engine-compatibility-2026-10-25.md) covers changes from stable `v1.0.2`.

All 15 intervening commits, including the merge, are accounted for below.

| Commit | Change | SpringCabal action |
| --- | --- | --- |
| `a42967c` | Canonicalize arithmetic NaNs at observable sinks; fall back to full canonicalization for unsupported modules. | Keep the production default. Rebuild and run game suites on this runtime; retain the same mode for both sides of every comparison. |
| `189fb1a` | Keep the loading screen drawing during long loading steps. | Exercise normal menu-to-game loading; no game API change. |
| `f8d9e3a` | Log slow loading-screen draws. | Logging only; no game migration. |
| `86c4d3b` | Add stable camera-fit shadow projection mode 3. | Keep existing shipped graphics profiles. Compare Lua/Rust using the same shadow settings. Modes 0–2 retain their behavior. |
| `d99df64` | Update cached speed after native velocity setters. | Required for movement parity with Lua; rebuild games against this engine's SDK. |
| `689ef7e` | Allow callback timers to be disabled while frame logging remains enabled. | Primary timings use timers off and require the CSV acknowledgement. Profiles remain separate from timings. |
| `8a1d2d2` | Match Lua cylinder-query broad phase and result order. | Preserve Lua query order in Rust consumers; rerun game and world comparisons. |
| `b5e56eb` | Filter cylinder queries using Lua's midpoint and visibility error. | Retain midpoint semantics in both implementations; no game-side center-position shortcut. |
| `8c767fc` | Match midpoint/radar bounds in additional spatial queries. | Same spatial API contract as Lua; rerun query consumers. |
| `4defddb` | Add regression coverage for cached speed after native writes. | Test-only follow-up to `d99df64`. |
| `5b9b469` | Give explicit unsynced seeds a reproducible PCG stream; isolate script draws from engine visual RNG. | Fix synced/unsynced seeds in comparisons; seed Lua fire and Rust fire equivalently. Repeat native particle counts and fixed-age images. Ordinary unseeded startup keeps its existing stream selection. |
| `2444282` | Add `GetWindVector`, matching the first three Lua `Spring.GetWind` results. | TTLD uses this vector for lights/effects. `GetWind` still returns min/max/current strength and must not be interpreted as XYZ. This new import requires the candidate engine. |
| `19910b9` | Derive the camera near plane from the active far plane; expose `ViewNearFarRatio`. | Keep the default ratio and check existing game cameras and images. No API migration. |
| `f9337c9` | Hide static C++ runtime symbols from system libraries; continue when OpenAL cannot open a sound device. | Package the CI Linux executable containing the linker fix. Keep normal audio enabled in shipped settings. |
| `0f0ee80` | Merge the current runtime/rendering branch with the movement, spatial-query, RNG and wind fixes. | Pin the seven Rust games, menu and shared crate to this exact SDK revision; package the matching Linux/Windows CI binaries. |

Weapon-control arguments remain one-based, as migrated for rc.2. CUS weapon
callbacks and array offsets remain zero-based. This candidate introduces no
additional weapon-number migration.

CI [40839526289](https://github.com/gajop/spring-rust/actions/runs/40839526289)
built both platforms successfully at the candidate commit. The local engine
passed 39,775 assertions across the RNG, NaN-sink and synced-jobs tests. Existing
game suites, fixed-image proofs and the final benchmark/capture matrix are
tracked separately; CI build success alone does not mark those complete.

Benchmark evidence records the engine executable SHA-256 as well as its commit.
The local profiling executable and stripped CI executables have different hashes;
all members of a timing pair use the same executable. Published bundles use the
CI archives, whose checksums are recorded during release preparation.
