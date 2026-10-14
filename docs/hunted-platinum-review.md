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

WASM is checked out on `rust` at `a7ac9a1`, exactly two
commits directly above that Lua tip:

1. `919daca` — gameplay/UI port, including all five approved Rust review fixes.
   `Scripts/` is unchanged from reviewed Lua.
   The temporary named-call bridge registers the existing environment functions;
   the redundant `script.Fire`/`script.SetPitch` aliases are unnecessary.
2. `a7ac9a1` — CUS unit scripts and their lifecycle wiring, replacing Lua scripts
   and removing the temporary bridge.

The earlier `codex/hunted-platinum-lua` and `codex/hunted-platinum-wasm` review
refs remain as aliases of these tips.

The final WASM tree includes the five fixes below; the second port's patch is
unchanged. The RmlUI port already retired the leaderboard, and replaces the
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
5. End-screen markup is cached by visibility and displayed score/time/kills.
   Gameplay status messages no longer clear the hidden panel, and identical
   end-screen statuses preserve its existing elements. Rebuilt documents
   invalidate the cache.

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
`d71d869`. All FX refs retain their original hashes. Nothing was pushed.

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
- Both updated WASM stages pass all 34 integration assertions, including the
  new stationary-target restart check, with zero errors or warnings. The first
  stage's latest logs are preserved under
  `codex-work/hunted-approved-stages/evidence/lua-unitscripts-review-fixes/`.
- The final WASM tree passes all eight visual golden comparisons (five full
  frames and three HUD/end-screen crops); the HUD and loss screenshot were
  inspected. Logs are preserved under
  `codex-work/hunted-approved-stages/evidence/cus-review-fixes-visual/`.
  Thirty AI unit tests, native test Clippy, release WASM Clippy and the release
  build pass. New unit tests exercise very large wave numbers and exhausted
  attempts without successful creations. Default release modules are installed.
  HUD failure cleanup and DOM caching were reviewed in source; no engine fault
  injection was added for those paths.
- With shared runtime fix `spring-bar` `ca1985b144`, all nine Lua/CUS gallery
  unit types match exactly. All 15 Hunted pose/image goldens pass after the
  targeted rabbit move-f30 correction; other tiles and tolerances are unchanged.

## Shared CUS correction and limits

The local shared `spring` crate resumes animation waiters during AnimFinished
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
playtesting or Windows certification. The shared engine commit is local and
selected through the workspace's generated Cargo patch. No ratings were edited.
