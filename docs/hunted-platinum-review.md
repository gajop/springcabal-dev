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
| Gravitas | `47a5280` | Cohesive cleanup `922f75c` plus the repeated-jump/middle-button input fix. |
| MyCube | `a4250c1` | One cohesive cleanup commit above the prior history. |
| PartsNeeded | `73bb0e4` | One cohesive cleanup commit above the prior history. |
| ToTheLastDrop | `b082f1a` | One cohesive cleanup commit above the prior history. |

Every pre-cleanup tip is preserved as `codex/before-wasm-structure-cleanup` (Hunted: `codex/hunted-before-structural-review`). The completed source snapshots remain at `codex/wasm-structure-cleanup-checkpoint`; the public dependency pin checkpoints also remain reachable. The current cleanup checkpoints include the follow-up Sol review, and the reconstructed final trees match those checkpoints. All three first-stage ports pass independently with their original Lua scripts unchanged.

The RML row test exposed an SDK memory-safety bug: the generated call supplied a flattened value count as a row count. `spring-bar` `c77a8b7054` changes the native query to a value count, checks divisibility by the schema width and derives the row count. Native Rust wrappers and generated bindings are updated. The same engine commit exposes weapon projectile parameters. The engine builds, its native RML test and codegen reproducibility check pass; Hunted exercises the new weapon query and the multi-field/shrinking/invalid row paths.

`gajop/springcabal-rs` and `gajop/springcabal-dev` are public, verified anonymously. The shared code was published on `gajop/springcabal-rs` branch `main` at `a8755627eb8451cad1010f4d3ce012e1b1367a51`; the latest helper cleanup is published on personal `main` at `a83ec8e5fde35d9143f7c080ad456c9a8a7baf3d`. All seven game manifests now pin this new revision. The SDK is published on `gajop/spring-rust` branch `main` at `c77a8b7054`. The temporary personal review branches have been deleted. The earlier published dependency pins were verified by building an extracted Hunted archive outside the development workspace, fetching all four dependencies from public Git revisions without local Cargo patches. The new helper pin was independently verified on October 16: an extracted Hunted archive outside the development workspace built both WASM modules using only public dependency revisions, without local Cargo patches; all 41 helper host tests also passed against the published SDK. No SpringCabal organization repository was pushed.

All seven release workspaces pass Clippy/build, all seven headless suites pass, and 114 shared/game host tests pass. Hunted's five frames and three HUD crops pass unchanged goldens with zero errors/warnings. Its interaction checks cover the bound event list and restart. Area17 retains headless texture warnings, and Flove's screenshot scenario logs nine capture-quality warnings; their suites pass. The broader visual galleries and Windows playtesting were not repeated for this structural pass. Evidence is under `codex-work/wasm-structure-evidence/`.

## Sol follow-up review

Three Sol agents checked the other six WASM games against the same structural review. Their changes restore original versions/descriptions, move the remaining unshared implementations under owning gadgets/widgets, and name MyCube constants without changing their values. Launcher and verification game names follow the restored versions. Existing project chat links are preserved. No additional Lua mechanics cleanup was introduced.

All six games pass their headless suites after these changes; the reconstructed first Flove and Area17 commits also pass with Lua unit scripts. The existing headless texture/capture warnings remain; Area17 now also instantiates the hidden technology template at startup, producing one additional headless wireframe texture warning. The rendered run has no RML texture warnings. Area17 also replaces generated loadout/technology markup, coordinate hover fallback, descendant traversal and markup caches with external templates, native typed rows, indexed click/hover/leave callbacks and engine pointer ownership. Its regression test verifies rendered tooltip text, hover, close/reopen and leave behavior.

Area17's three visual goldens pass unchanged (0.4%, 4.6% and 3.8% RMSE). Its native tooltip/reopen regression and technology toggle/weapon/ability callbacks pass. No game or SpringCabal organization branches were pushed. The shared and SDK personal repositories publish these revisions on `main`.

The Area17 screenshots show only the world, including in the existing goldens, despite the expected open technology panel and passing native UI checks. This is not an intentional test setting. Accordingly those screenshots validate world rendering, not HUD pixel parity; the unresolved rendering issue is recorded in `docs/open-problems.md`.

## Final readability pass

The additional WASM cleanup is folded into the existing commits above. Hunted, Flove and Area17 retain exactly two port commits, with the unit-script delta unchanged. The other four games retain one cohesive cleanup commit above their earlier history. The shared helpers keep movement key aliases independent, remove unused APIs and release message state before engine calls. All seven games and the menu build, 115 host tests pass, Hunted passes 35 seeded assertions, and TTLD passes 54 assertions. The menu uses one typed catalogue and external RML data bindings; native Tab navigation and a Hunted launch were checked in-engine with no errors or warnings. Launcher and release checks pass fixture tests. These changes are committed locally and remain unpushed.

## October 16: audit of missed integrations

The Gravitas jump regression was a missed integration. `fix-jump-once` and the cleanup both branched from `6fd2d55`; fixes `ea1aa3a` and `1bda7b0` existed before the cleanup, but were left outside the playable checkout. `47a5280` integrates their behavior into the moved input widget and the installed production modules were rebuilt. Real input verifies repeated Space jumps, E, middle-button jumping, then push/pull. The full play suite still fails its separately documented beyond-range assertion.

The audit compared behavior across branches, preserved checkpoints, stashes, reflog candidates and registered worktrees. Rewritten port history means lack of ancestry alone does not establish a lost fix. No other completed ordinary gameplay fix was found waiting for integration.

| Game | Fixes specifically reconciled against the playable source |
|---|---|
| Hunted | The preserved OSD stash's rabbit/carrot/streak colors remain wired through event kinds, bound rows and RCSS. Restart keeps the gun and stationary cursor target. Wave growth remains bounded and failed creations consume their spawn attempts. HUD bind/load failures remove the partial context before retrying. End-screen values use data bindings instead of rebuilding markup. |
| Flove | `cb15a29` held-command separators and corrected spire branch counts remain in `Encoder::rest` and the shared branch formula. The older no-depth-clear outline patch was superseded by sway-aware depth clearing in both Lua and Rust. |
| Area17 | Preserved pre-Platinum edits and review checkpoints retain their meaningful corrections in the reviewed Lua base and current port. The old unavailable-leaderboard guard targets UI the port retired. Missing HUD pixels remain unresolved, not an identified branch fix. |
| Gravitas | Jump release tracking and middle-button capture are now integrated. Collision/level commits `80f397f` and `94d0534` were already included; no existing fix for the remaining range, collision or boss failures was found on the other branches. |
| MyCube | The older dirty worktree's RNG, iglu decoration and drill icecube changes are superseded by included `960aef0` and `ed14ca9`, followed by burner placement correction `9bd0575`. |
| Parts Needed | `e46f17a` limb masks and arm-only swimming, non-animated ending completion, input cooldown guards, glide and trigger behavior remain present. |
| To The Last Drop | `6aedc58` Buff/Stun/CastAnimation delivery remains through typed direct/deferred CUS calls. Immediate rules-unsynced scaling replaced the older enlarger; unregistered healthbars were deliberately removed. |

FX branches remain preserved and excluded. Flove's GamePreload change on its FX branch addresses heavy FX initialization; it was not pulled into the ordinary port without evidence of a current startup regression. Existing Lua worktree edits in Parts Needed and MyCube are whitespace only and were preserved.

The audit also found that all seven manifests referenced the unpublished helper `a83ec8e`, hidden by local path patches. That existing commit is now published to `gajop/springcabal-rs` personal `main`; a standalone Hunted WASM build fetched the exact revisions successfully. `content.tsv` now selects Flove's reviewed Lua branch `main`, matching the actual local checkout. Game branches remain unpublished by request; fresh upstream clones cannot contain their local review work yet.

Routine Gravitas coverage previously pressed jump only once; the direct jump tests bypassed input polling and the scripted pointer bypassed native mouse-button capture. Passing those checks did not establish repeated jumping. The separate real-input play suite exercised it but was outside `verify all` because of the unresolved range assertion.

The readiness-log filter correction had also reached only the Gravitas smoke runner. Its E2E and screenshot runners now enable the same required INFO sections after installing the verification quit entry point; previously their case/result markers were suppressed. This was a runner integration omission, separate from the gameplay fix.

The strengthened input case now releases, lands and jumps again through the UI polling path, preserving the previous total travel distance. All 19 Gravitas E2E cases pass at 100× under offscreen GPU rendering with no runtime errors or warnings; default/feature Clippy and the feature-free test-code exclusion check pass. A temporary source copy with only the old latch expression restored fails the new input case while the other 18 pass. The installed production modules were not overwritten by these staged tests.

## October 16: shared controls and sustained B.O.B fire

Every Lua and WASM game now uses common utility controls: physical Pause toggles pause, F12 takes a screenshot and Ctrl+Q returns to the menu, while default RTS keyboard orders are cleared. Lua includes `LuaHandler/Utilities/game_controls.lua` from the rebuilt engine content archive; WASM registers `springcabal::controls::GameControls` before game widgets. These handlers consume repeated utility-key events without repeating the action. Gravitas retains its P alias and Hunted its Space alias; game-specific movement, aiming, spells, mouse handling and manual cameras remain in their widgets. Removed legacy formation widgets' Alt+A engine attack bindings so they cannot restore an RTS shortcut later.

Gravitas WASM had passed `bind` and its arguments as separate commands, so its bindings did not install. Testing also exposed native `SendCommands` treating newline-separated command batches as one action. Engine `2e3b082728` splits both command fields into ordered lines, with binding readback regressions; the shared controls send individual complete commands. Engine `a0d7652ad9` provides the Lua utility and SDL Pause symbol, and helper `dcb1a9b` is published on personal `main`. All seven manifests use these public revisions; a standalone extracted Hunted build without local patches passes.

Physical Pause freeze/resume, F12 screenshot creation and early/late binding inspection pass in all 14 Lua/WASM editions on a private virtual display. The final matrix exits cleanly with no runtime errors or warnings; simulations run at 100× outside the short wall-clock input checks. `verify controls all` is now part of `verify all`. The Area17 checks use the same patched map as normal launch.

The strict runs also exposed three incorrect float literals in Flove's Lua deferred shader and engine shader validation occurring before restored sampler assignments. The Lua literals are fixed in `d81143a`; engine `8474691811` restores uniforms before validation. Mesa reproduces the original mixed-sampler failure and validates successfully after restoration. Both engine builds and the native API regression fixture pass. Obsolete local widget-order entries and deprecated includes in the local Scenario Editor content were fixed without replacing the rest of those files; the exact changes are preserved in `patches/local-content-compat.patch` (`git apply --check` before applying to unpatched local content). No user key-binding file is written.

The reported firing robot is B.O.B. Lua's extra five-second script gate produced 10 shots in the first ten-second window, five in the next, with a 153-frame maximum gap. Lua `2f822a3` removes that gate, corrects the stale aiming-type check and uses the existing WASM spin-stop behavior. Fixed Lua and unchanged WASM both produce 100 shots per ten-second window with a maximum three-frame gap. `verify gravitas lua-bob` and `bob` reproduce this under the offscreen GPU at 100× with clean logs and are included in `verify all`. The older burst expectation in the combined rules observer now checks continuous firing; the separate combined WASM scenario still fails and remains documented in `open-problems.md`.

Game changes are committed locally and remain unpushed. The Lua controls are one focused commit per game; Flove's shader correction and Gravitas's B.O.B correction are separate Lua commits. Hunted, Flove and Area17 remain exactly two port commits above their current reviewed Lua tips, with their unit-script deltas byte-for-byte preserved. Their previous port tips remain reachable at `refs/codex/before-shared-controls`; FX refs were not changed.

| Game | Reviewed Lua | First port commit | Unit-script port commit |
|---|---|---|---|
| Hunted | `a6ec920` | `dc04367` | `b41b2c5` |
| Flove | `d81143a` | `4ce79d0` | `4432d91` |
| Area17 | `4fd1469` | `5e58bc2` | `65012b0` |

## October 16: remove rectangular bunny-explosion particles

The screenshot's hard rectangles came from the `unitpoofs` component of the four `genericbunnyexplosion-*-red` effects. Its `randomdots` texture contains bright RGB at nearly transparent border pixels; the engine's additive particle color path displays that RGB, exposing the square sprite boundary. Lua and WASM use identical definitions and source textures, so the issue affects both. Lua `6e85f05` changes only the four poof texture references to the existing `explofade` sprite, whose RGB fades to black at its edges. Particle counts, motion, timing and the other components remain unchanged. No texture assets or FX branches were edited.

Before/after offscreen GPU CEG captures confirm the rectangular burst boundaries are gone. Lua and WASM captures of the corrected small explosion finish in about three seconds each at 100× with no errors or warnings. Captures are preserved locally in `codex-work/hunted-burst-fix/`; existing goldens were not overwritten. The targeted run also corrected two harness false alarms: `fault` no longer matches the word `Default` in a module's widget list, and a gallery with fewer than eight requested jobs no longer reports the requested spot count as an error. The runtime pattern still matches actual traps, errors, faults and borrow failures.

The current Hunted Lua tip is `6e85f05`; Rust has first port `22b95c9` and unit-script port `e11bea0` above it. The unit-script delta is byte-for-byte unchanged; the previous Rust tip is preserved at `refs/codex/before-bunny-effect-fix`. Game changes remain local and unpushed.
