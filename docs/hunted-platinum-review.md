# Hunted Lua review and two-stage WASM port

The user approved the eight-commit proposal and its keep/remove decisions,
confirmed that analytics and the leaderboard are retired, and asked whether
lighthouse fear was existing behavior. FX work remains out of scope. This work
never edits `TODO.md`; ratings remain the user's decision.

## Current history

Lua is checked out on `master` at `096bae3`, exactly nine
commits above `origin/master` (`14f5bc9`):

| Commit | Reviewed scope |
| --- | --- |
| `4555758` | Current-engine loading, definition warnings, referenced sounds, local-only metadata and archive exclusions. |
| `3593bfd` | Rabbit/material and map-edge rendering fixes; move the unchanged volume helper outside the widget scan. |
| `ca7745c` | Preserve engine bindings and Pause/F12, return exits to the launcher, remove command-color overrides. |
| `dcbf0c9` | Repair victory/end-screen state, restart cheat state and HUD streak reset; retire leaderboard and analytics hooks. |
| `c04351f` | Keep carrot reservations and ownership consistent while stealing, dropping and destroying food. |
| `f0de6da` | Correct lighthouse beam registration coordinates and remove destroyed lights from their update index. |
| `2b5fb8d` | Let reload finish during aiming and return shotgun recoil to neutral. |
| `38e57c0` | Restore the rabbit resting pose and pass the idle tail speed correctly. |
| `096bae3` | Bound wave-size and burrow-pick growth by the existing 600-rabbit limit. This shared bug was fixed in Lua before Rust. |

WASM is checked out on `rust` at `0c5f25f`, exactly two
commits directly above that Lua tip:

1. `6be9846` — gameplay/UI port, including all five approved Rust review fixes.
   `Scripts/` is unchanged from reviewed Lua.
   The temporary named-call bridge registers the existing environment functions;
   the redundant `script.Fire`/`script.SetPitch` aliases are unnecessary.
2. `0c5f25f` — CUS unit scripts and their lifecycle wiring, replacing Lua scripts
   and removing the temporary bridge.

The earlier `codex/hunted-platinum-lua` and `codex/hunted-platinum-wasm` review refs are preserved as checkpoints of the earlier reviewed trees.

The final WASM tree includes the five fixes below and the subsequent structural review. Unit-script cleanup remains in the second port commit. The RmlUI port already retired the leaderboard, and replaces the
removed Lua widgets and rendering helpers.

## Approved Rust review fixes

All five findings were approved for implementation and folded into the first
port commit:

1. Restart retains the cursor target along with the surviving gun. A stationary
   mouse sends no duplicate MOVE, so clearing that target used to disable the
   synced flashlight's effect on rabbits until the mouse moved.
2. Lua and Rust cap both nominal wave size and burrow picks at 600. Early waves
   retain their existing growth. Rust stops recomputing growth once both caps
   are reached, preventing excessive work and integer overflow in long hunts.
3. A wave finishes after all scheduled spawn attempts, even if CreateUnit
   fails. This matches Lua's policy; failures remain logged. The redundant
   successful-creation counter and callbacks were removed.
4. HUD initialization requires all data bindings. Bind/load/show failure removes
   the partial context before retrying; stale documents also remove their old
   context. The nonexistent direct-update fallback was removed.
5. End-screen content remains in the document and updates through bindings. The structural review replaced the initial cache with static RML templates and native data events; status packets no longer rebuild its elements.

## Approved cleanup

The prior 32-commit Lua history was too fragmented and retained changes without
sufficient justification. The approved result:

- Removes the unconditional movement diagnostics; restores the original unused
  jump configuration instead of editing its commented contents.
- Removes the redundant shotgun script-table aliases. Lua callers and the first
  WASM bridge use `env.Fire` and `env.SetPitch` directly.
- Moves `glVolumes.lua` unchanged into `LuaUI/Utilities/`, updates its include,
  and removes the extra widget-registration workaround.
- Removes the unused External VR Grid and `WG.crude` menu integrations.
- Preserves explicit Pause/F12 bindings, keeps the removal of `unbindall`, and
  removes `play_mode` detection because Hunted defines no such modoption.
- Removes the Command Colours widget and its shared-file overrides, rather than
  retaining the file-lifecycle patches. The Ctrl+Q hint now says Menu.
- Removes retired leaderboard controls, submission code and analytics event
  hooks, plus the already-inactive analytics loader stub.
- Removes the flashlight gadget's global Shadows configuration writes. The
  launcher's existing per-game `Shadows = 0` profile remains. A shadows-on
  engine run verifies that rendering and restart still work.

These choices supersede the earlier provisional preserve-everything and
conditional-leaderboard decisions; they were presented before being applied.
No unrelated assets or FX work were removed.
The complete approved cleanup diff is saved at
`codex-work/hunted-approved-stages/approved-lua-cleanup.patch`.

## Lighthouse behavior

Lighthouse fear is already implemented upstream. `Scripts/lighthouse.lua`
registers a torch beam with `GG.AddScaryArea`, and `rabbit_ai.lua` includes it
when calculating environmental fear and avoidance. Its light multiplier fades
as a rabbit carries food for longer. This review adds no fear source, radius,
strength or new mechanic.

The coordinate change fixes `z = x` to `z = z` in the registration calls. The
spin loop already updates both coordinates correctly, generally correcting the
initial position immediately. This is a registration typo correction, not a
claim that lighthouse fear was previously absent or wholly broken.

## Preservation

All old histories remain reachable in the Hunted repository:

- `codex/hunted-original-lua-master`: original Lua master `d71d869`, preserved
  before moving `master` to the approved eight-commit history.
- `codex/hunted-32-commit-lua`: complete prior Lua review at `fcb7ab7`.
- `codex/hunted-before-approved-cleanup-wasm`: prior port at `88668b0`.
- `hunted-wasm-port` and `codex/hunted-pre-platinum-wasm`: original WASM
  `a3e379b`, unchanged.
- `codex/hunted-pre-platinum-wasm-with-osd`: exact original working tree plus
  the OSD fix, `86106eb`. Its named stash and
  `codex-work/hunted-osd-before-platinum.patch` also remain.
- `codex/hunted-platinum-wasm-before-lua-ui-fix`: preceding draft pair ending
  at `14de903`.
- `codex/hunted-before-rust-review-lua`: approved eight-commit Lua tip `38e57c0`.
- `codex/hunted-before-rust-review-fixes`: previous two-commit WASM tip `d58cae2`.
- `codex/hunted-rust-review-fixes-checkpoint`: tested five-fix checkpoint
  `95806ea`, with exactly the current final WASM tree before history folding.

The older regrouping checkpoint `ba28432` has the exact original Lua tree of
`d71d869`. All FX refs retain their original hashes. No game branches or SpringCabal organization repositories were pushed.

## Verification

- Thirteen focused Lua regression cases pass: carrot theft and ownership,
  lighthouse lifetime/registration, streak reset, aiming/reload, rabbit idle,
  and victory/loss restart with both initial cheat states. The end-screen
  tests reject any retired analytics call or leaderboard control. A 1,000-wave
  check verifies bounded Lua growth and unchanged first three waves.
- All 159 other tracked Lua files parse. The original, unused
  `LuaRules/Configs/jump_defs.lua` retains its pre-existing nested-long-comment
  parse failure, as explicitly proposed; no active loader references it.
- The short Lua engine probe checks drawing, shooting, mine placement, loss
  and restart. Restart restores 100 carrots, resets shot/mine counts and
  preserves cheats. Both the normal launcher profile and Shadows=1 are checked
  on the GPU with zero engine errors/warnings and test-owned UI settings. The
  screenshots were inspected. The initial run inherited stale user widget
  registrations and warned about removed widgets; the probe now isolates these
  settings without changing the player's profile.
- Both updated WASM stages pass all 35 integration assertions, including the
  new stationary-target restart check, with zero errors or warnings. The first
  stage's latest logs are preserved under
  `codex-work/wasm-structure-evidence/`.
- The final WASM tree passes all eight visual golden comparisons (five full
  frames and three HUD/end-screen crops); the HUD and loss screenshot were
  inspected. Logs are preserved under
  `codex-work/wasm-structure-evidence/hunted-visual/`.
  Thirty AI unit tests, native test Clippy, release WASM Clippy and the release
  build pass. New unit tests exercise very large wave numbers and exhausted
  attempts without successful creations. Default release modules are installed.
  HUD initialization cleanup was reviewed in source. The visual scenario now checks multi-field rows, rejection of an incomplete row, row expiry, the native restart button event and the new round's HUD. That test also caught and fixed retention of the previous survival time after the first restart status.
- With shared runtime fix `spring-bar` `ca1985b144`, all nine Lua/CUS gallery
  unit types match exactly. All 15 Hunted pose/image goldens pass after the
  targeted rabbit move-f30 correction; other tiles and tolerances are unchanged.

## Shared CUS correction and limits

The shared `spring` crate resumes animation waiters during AnimFinished
completion dispatch, after releasing the typed state borrow. Ordinary timers
and wakers retain their once-per-frame guard. All 25 crate tests pass, including
new completion, timer isolation, task order, state access, following-sleep and
cancellation checks. Two regression tests fail on the old runtime. Native Clippy
passes with `type_complexity` allowed for two pre-existing `commands.rs` errors;
the WASM target checks successfully.

All seven CUS animation galleries were rerun using rebuilt staged release
modules. Six pass; Area17's 51 poses pass but 17 image failures reproduce with
its previously installed modules. Its unrelated goldens were not changed.

This is a focused Linux source/history and runtime review, not exhaustive
playtesting or Windows certification. The engine changes are available in the public personal SDK repository and are pinned by the games. Local development also uses the generated Cargo patch. No ratings were edited.

## Structural review

The user's second Rust review is addressed in the two port commits. The inherited sound entries and loader attribution are restored. `modinfo.lua` keeps Lua's version and description; only the game names/short names differ. The top README uses unwrapped prose, a small module table and a link to the public development repository. The redundant `wasm-src/README.md` is removed.

`ai` is now `common` (`hunted-common`): message keys live in `protocol.rs`, ammunition defaults in `weapons.rs`, and rabbit calculations in `rabbit.rs` and `movement.rs`. `RabbitData`, movement vectors and named coefficients replace the port's `Mood`, `heeds_goal` and `Pull` terminology without rebalancing Lua's formulas. The engine movement setters accept Lua's zero speed; only the negative-power calculation guards a zero input to keep the turn value finite.

Game-specific implementations now live with the owning gadgets/widgets, including rabbit AI, weapons, waves, input, restart, visibility and HUD handling. Code-bearing `mod.rs` files use named module files. Port-authored Rust narration is removed. Hunted's external `endgame.rml` and `events.rml` are included once; normal updates use scalar/row bindings and native data-event callbacks. There is no manual click-target traversal or generated floating-message markup.

The port reads lighthouse rules params as Lua/UI do, removes the redundant carried-carrot movement, restores shotgun playback in rules, and uses the engine's weapon definition for pellet count/spread. The initial flashlight source matches Lua's map-corner source. The README retains only the actual HUD and restart/input presentation differences.

Shared `springcabal-rs` changes rename the verification-only `Gallery` builder to `WorldWidgets` and move the existing ground-volume renderer into `springcabal::volumes`. All seven games use the new API, public HTTPS dependencies, concise top-level documentation, named module files and the comment cleanup. Unshared controller implementations were moved under their respective owners where applicable; shared protocol/state/helpers remain shared. No additional Lua cleanup was applied to the games without an earlier Lua pass.

| Game | Current WASM tip | History |
| --- | --- | --- |
| Hunted | `0c5f25f` | Two commits above Lua `096bae3`; gameplay/UI first `6be9846`. |
| Flove | `dc12a0f` | Two commits above Lua `e93965f`; gameplay/UI first `c553b9c`. |
| Area17 | `6333d3e` | Two commits above Lua `e9d9410`; gameplay/UI first `5110211`. |
| Gravitas | `922f75c` | One cohesive cleanup commit above the prior history. |
| MyCube | `a4250c1` | One cohesive cleanup commit above the prior history. |
| PartsNeeded | `73bb0e4` | One cohesive cleanup commit above the prior history. |
| ToTheLastDrop | `b082f1a` | One cohesive cleanup commit above the prior history. |

Every pre-cleanup tip is preserved as `codex/before-wasm-structure-cleanup` (Hunted: `codex/hunted-before-structural-review`). The completed source snapshots remain at `codex/wasm-structure-cleanup-checkpoint`; the public dependency pin checkpoints also remain reachable. The current cleanup checkpoints include the follow-up Sol review, and the reconstructed final trees match those checkpoints. All three first-stage ports pass independently with their original Lua scripts unchanged.

The RML row test exposed an SDK memory-safety bug: the generated call supplied a flattened value count as a row count. `spring-bar` `c77a8b7054` changes the native query to a value count, checks divisibility by the schema width and derives the row count. Native Rust wrappers and generated bindings are updated. The same engine commit exposes weapon projectile parameters. The engine builds, its native RML test and codegen reproducibility check pass; Hunted exercises the new weapon query and the multi-field/shrinking/invalid row paths.

`gajop/springcabal-rs` and `gajop/springcabal-dev` are public, verified anonymously. The shared code was published on `gajop/springcabal-rs` branch `main` at `a8755627eb8451cad1010f4d3ce012e1b1367a51`; the latest helper cleanup is committed locally at `a83ec8e5fde35d9143f7c080ad456c9a8a7baf3d` and is not pushed. All seven game manifests now pin this new revision. The SDK is published on `gajop/spring-rust` branch `main` at `c77a8b7054`. The temporary personal review branches have been deleted. The earlier published dependency pins were verified by building an extracted Hunted archive outside the development workspace, fetching all four dependencies from public Git revisions without local Cargo patches. Repeating that check for the new helper pin requires publishing that commit first; the local development setup uses its path patch. No SpringCabal organization repository was pushed.

All seven release workspaces pass Clippy/build, all seven headless suites pass, and 114 shared/game host tests pass. Hunted's five frames and three HUD crops pass unchanged goldens with zero errors/warnings. Its interaction checks cover the bound event list and restart. Area17 retains headless texture warnings, and Flove's screenshot scenario logs nine capture-quality warnings; their suites pass. The broader visual galleries and Windows playtesting were not repeated for this structural pass. Evidence is under `codex-work/wasm-structure-evidence/`.

## Sol follow-up review

Three Sol agents checked the other six WASM games against the same structural review. Their changes restore original versions/descriptions, move the remaining unshared implementations under owning gadgets/widgets, and name MyCube constants without changing their values. Launcher and verification game names follow the restored versions. Existing project chat links are preserved. No additional Lua mechanics cleanup was introduced.

All six games pass their headless suites after these changes; the reconstructed first Flove and Area17 commits also pass with Lua unit scripts. The existing headless texture/capture warnings remain; Area17 now also instantiates the hidden technology template at startup, producing one additional headless wireframe texture warning. The rendered run has no RML texture warnings. Area17 also replaces generated loadout/technology markup, coordinate hover fallback, descendant traversal and markup caches with external templates, native typed rows, indexed click/hover/leave callbacks and engine pointer ownership. Its regression test verifies rendered tooltip text, hover, close/reopen and leave behavior.

Area17's three visual goldens pass unchanged (0.4%, 4.6% and 3.8% RMSE). Its native tooltip/reopen regression and technology toggle/weapon/ability callbacks pass. No game or SpringCabal organization branches were pushed. The shared and SDK personal repositories publish these revisions on `main`.

The Area17 screenshots show only the world, including in the existing goldens, despite the expected open technology panel and passing native UI checks. This is not an intentional test setting. Accordingly those screenshots validate world rendering, not HUD pixel parity; the unresolved rendering issue is recorded in `docs/open-problems.md`.

## Final readability pass

The additional WASM cleanup is folded into the existing commits above. Hunted, Flove and Area17 retain exactly two port commits, with the unit-script delta unchanged. The other four games retain one cohesive cleanup commit above their earlier history. The shared helpers keep movement key aliases independent, remove unused APIs and release message state before engine calls. All seven games and the menu build, 115 host tests pass, Hunted passes 35 seeded assertions, and TTLD passes 54 assertions. The menu uses one typed catalogue and external RML data bindings; native Tab navigation and a Hunted launch were checked in-engine with no errors or warnings. Launcher and release checks pass fixture tests. These changes are committed locally and remain unpushed.
