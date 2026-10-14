# Flove Lua review and WASM history reconstruction

Reviewed on 2026-10-15. `TODO.md` was not edited by this work. No game repository
was pushed.

## Checked-out results

- Lua: `spring-linux/games/Flove.sdd`, `codex/flove-platinum-lua`, `62aa627`.
  There are 38 focused commits above upstream `0e6e705`: 29 regroup the existing
  changes, and nine fix bugs found in this review.
- WASM: `spring-linux/games/Flove-wasm.sdd`, `codex/flove-platinum-wasm`,
  `bb7a302`. Its parent history contains that exact Lua tip, followed by exactly
  two commits:
  1. `9fd8201`: gameplay, input, UI, graphics, assets and existing port improvements.
     `Scripts/` and the Lua unit-script dispatcher are unchanged from the Lua tip.
     A temporary gadget bridges spire branch targets and creation-frame state.
  2. `bb7a302`: CUS unit scripts, their lifecycle wiring, removal of the Lua scripts
     and temporary adapter, and replacement of Lua's eye flare with the rules flare.

The three installed WASM modules were rebuilt without test features after the
checks. The first commit is a runnable intermediate version, not just a source split.

## Preserved originals and changes

In the Lua repository:

- `master` and `codex/flove-pre-platinum-lua`: original six local commits, `2572ce1`.
- `codex/flove-preserved-lua`: `4f13821`, including the three original uncommitted
  files: key bindings, end-game menu exit and `onlyLocal` metadata.
- `codex/flove-reviewed-lua-wip`: the intermediate review history before consolidating
  the restart repair into one coherent final commit.
- `codex-work/flove-preserved/lua-working-tree.patch`: the original uncommitted patch.

In the WASM repository, `flove-wasm-port` and `codex/flove-pre-platinum-wasm` preserve
`a297dad`; `codex/flove-wasm-review` additionally preserves the mouse-message and
branch-count repairs before reconstructing the two-commit history.

The Lua preservation checkpoint (`378529e`, after the first 29 regrouped commits)
has exactly the same Git tree as `4f13821`. This includes the revised mushroom,
tree and grass models, golden-love effect, shader fixes, sound changes, archive
exclusions, disabled analytics placeholder, command policy and menu edits.
The historical Cannon rewrite and its later MissileLauncher restoration remain
in the preserved history; the regrouped tree keeps the final working definition.

The final WASM tree differs from the original port in only seven paths:

- The UI encodes nested held commands correctly.
- The shared branch formula and its Lua comparison reflect the Lua fix.
- Custom material rebuilds use gadget methods instead of nonexistent globals.
- `greymuzzle` uses the identical standalone definition inherited from Lua;
  its duplicate entry in `barf.lua` is removed.
- The test scenario excludes dead units still playing Lua death animations.
- The README explains the corrected behavior and updated Lua restart behavior.

All other original port files, including assets, diagnostics, animated outlines,
hover highlighting, UI features, model revisions and unit-script implementation,
are preserved. The existing poison kill-credit behavior is preserved.

## Lua fixes and port equivalents

| Lua repair | WASM behavior |
| --- | --- |
| Unregister destroyed poison mushrooms. | Existing poison gadget unregisters them. |
| Remove flower expiry records on destruction; remove an expiry before calling destruction callbacks. | Existing flower manager removes records; queued destruction runs after expiry removal. |
| Request exactly the desired spire branches, guard branch bounds, initialize the count before sleeping. | Corrected shared branch formula; CUS already bounds and initializes its count. |
| Rebuild tree power once; stop the spire script resetting global power. | Tree manager owns power; CUS does not reset it. |
| Rebuild custom materials through their actual gadget methods. | Same retained rendering gadget repaired. |
| Refresh uniform locations when the shader changes. | Existing port material callbacks resolve locations from the active shader. |
| Ignore disappeared upgrade-cursor units. | Existing pick/target resolution handles missing units. |
| Compile the wisp shader using float literals. | Existing port's wisp shader already has the corrected expressions. |
| Reset retained story controls and keep difficulty after the rules reload actually finishes. | Existing in-place restart retains UI and difficulty, verified through the UI actions. |

The flower/upgrade cooldown name is also corrected to a local variable in the Lua
spire repair. Timing, wave balance and unrelated original growth behavior were
left as they were.

## LMB regression

The UI formerly used `Encoder::field` to nest a shot inside `hold`. That escapes
its separators: `hold|zap\|x\|y\|z`. The rules expect `hold|zap|x|y|z` and reject
an escaped command name. RMB went through the same broken path.

Using `Encoder::rest` preserves the nested command. The physical input probe
starts a normal game, skips the tutorial, ray-traces a playable position, sends
real SDL LMB/RMB events through Xvfb, and requires both zap and flower projectiles.
It does not inject shot messages or call the input widget directly.

## Focused verification

- All 115 Lua files in the reviewed game-owned directories parse with `luac -p`.
- Eight Lua regression cases pass; seven fail against the preserved pre-review game.
- `./verification/verify probe flove-lua-review` verifies Lua LMB, upgrades, loss,
  restart with cheats already enabled, one replacement spire, intro state and
  retained Hard difficulty. All three screenshots were inspected.
- Both WASM commits pass the 66 rules, nine UI and eight scenario assertions,
  with no engine/runtime errors in the headless check.
- Physical LMB/RMB pass in both WASM versions. The final repeat uses
  `./verification/verify probe flove-mouse-input`.
- Six shared host tests pass, including the corrected Lua branch comparison.
- Mushroom animation comparison passes: 19,760 pose samples, maximum difference
  `0.000008`, tolerance `0.002`.
- WASM builds pass formatting and release clippy with warnings denied.
- Flove animation reference images were recorded twice on the GPU, visually reviewed,
  and checked against a fresh run after correcting the spire branch count.

The software-rendered runs still log the engine's existing llvmpipe grass shader
validation error; there were no Lua errors or WASM failures. This was a focused
Linux review, not a full ten-minute playthrough or Windows check. No rating was changed.

Evidence is under `verification/out/flove-lua-platinum/`, `flove-port-first/`,
`flove-port-final/`, `flove-input-platinum/`, and `flove-animation-{lua,rust}/`.
