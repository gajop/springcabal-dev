# Engine compatibility review for SpringCabal 1.0.3-rc.2

Baseline: v1.0.2 / engine `2026.10.21` (`0a67e181ceae991aa4cbfa64339f92c3cbc8a6e6`).
Target: engine `2026.10.25` (`dd05f8647458ff5541a8aee8d43b6218a64eaef8`).

All 24 engine commits between these revisions were reviewed against the game and shared-crate call sites.

| Commit | Change | Game impact / action |
| --- | --- | --- |
| `82da492807` | Report world points behind the camera as having no screen position | Check projection validity in TTLD lighting and its existing visual driver; MyCube already checks it. |
| `2ef8032e73` | Add GPU timestamp queries (gfx.QueryCounter) to the native and Wasm APIs | Additive GPU query call; no SpringCabal caller. |
| `9873798cd7` | Add TextureMipSkip: leave out the finest levels of large mipmapped DDS textures | Optional texture setting; retain the existing default. |
| `e16a050b05` | Read BC4 and BC5 DDS textures (ATI1/BC4U, ATI2/BC5U as RGTC) | Additional DDS formats; existing assets remain supported. |
| `5f013fab7e` | Start next-frame synced Wasm jobs right after GameFrame | Job dispatch starts earlier; no SpringCabal job submissions. |
| `3b6d184550` | Tick each CUS module once a simulation frame | CUS runs once per frame; rerun script animation and gameplay suites. |
| `e9535f7f21` | Build the PNG-linked Rml tests only where PNG and zlib are found | Engine test build configuration only; no game migration. |
| `cd944405f1` | Base content archives start afresh on every rebuild | Engine base-content packaging fix; use matching published platform binaries. |
| `7170bd3d43` | Wasm unit queries honour Lua's my, ally and enemy allegiance; spring::allegiance names them | All production spatial queries use all units (-1) or explicit teams; retain those semantics. |
| `1002f2fff1` | ResultExt: log_err_with and log_err_once_with build their context only on failure | Additive lazy logging methods; existing methods remain supported. |
| `e7d250d7fe` | Wasm game API TODO: drop finished items, narrow the rules param getter | TODO documentation only. |
| `335c82d47c` | Icons added at runtime build their atlas | Runtime icon atlas fix; no game API migration. |
| `a1474a8e1d` | IconsAsUIDraw: a game can keep UI icon state and leave their drawing to itself | Optional UI-icon drawing switch; existing default remains enabled. |
| `32b6c0ffb4` | Weapon numbers count from 1 in every native and Wasm call | Migrate Area17, Gravitas and TTLD setters to one-based numbers; keep zero-based CUS callbacks and array indices. Use zero for projectiles without a live firing weapon in Flove, Hunted and TTLD. |
| `b9254753bd` | Minimap: units neither in sight nor on radar draw no icon | Minimap visibility and invalid-icon fix; no game API migration. |
| `24629034a4` | Wasm modules start when they load: addon init runs before the first callin | Addon initialization now happens while the module loads. Area17 now creates its scene on the first simulation frame, when UnitCreated delivery can attach scripts and configure every initial unit. The integration suite checks all initial scripts before its gameplay checks. |
| `4b2e01b1b2` | spring-addons: CusHostGadget attaches a CusHost's unit scripts, as unit_script.lua does | Additive CusHostGadget helper; current per-game host gadgets remain supported. |
| `7960d9cd54` | Wasm game API TODO: Wait* completions already resume in the completion frame | TODO documentation only; wait completion behavior predates the previous release. |
| `08220f389f` | Wasm game API TODO: the string game rules param getter already exists; list finished | TODO documentation only; rules string getter predates the previous release. |
| `91449027c2` | rustfmt spring-sdk-internal: the Wasm API and native Rust workflows stopped at formatting | SDK formatting correction only. |
| `24b6c59f87` | Wasm jobs: log a failed job's status and trap diagnostic locally | Worker failure logging; no SpringCabal job submissions. |
| `5f71b36cec` | Wasm jobs: Tracy zones test the active batches with empty(); the Tracy build failed since active became a list | Tracy build correction only. |
| `3c293a1647` | Wasm runtime: SPRING_WASM_NAN_CANONICALIZATION=0 turns NaN canonicalization off, a diagnostic opt-out to measure its cost (Ship Game's dense battle kernels take about twice as long with it); never for a match | Diagnostic opt-out only; leave NaN canonicalization enabled. |
| `dd05f86474` | Wasm sync log: a sim checksum of the engine's own state, without the modules' identity, memory sizes and job digests, so two module builds or jobs against their fallback can be compared (wasm_sync_replay.py compare --engine-state); the network checksum is unchanged | Diagnostic engine-state checksum only; normal network checksum unchanged. |

CUS `WeaponId` callback values and weapon-definition array offsets still count
from zero. Only Spring weapon-control arguments change to one-based numbers.
Area 17 keeps its shared slot constants zero-based and converts at the setter;
Gravitas uses its existing one-based weapon constants directly. TTLD's attribute
code now uses one-based numbers for both reads and writes, and converts its CUS
callback slot before setting reload state. Manually spawned projectiles use `0`
when they have no live firing weapon instance.

The engine keeps the old import names with their original zero-based meaning.
New SDK modules import the one-based calls under `*-v2` names, which engines
before `2026.10.2402` cannot load. Rebuild all modules against the SDK from the
same engine revision as the bundled binaries. `1.0.3-rc.1` deliberately uses
`2026.10.21` and its matching SDK; `1.0.3-rc.2` uses `2026.10.25` and its SDK.
