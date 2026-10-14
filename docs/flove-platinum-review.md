# Flove Lua review and WASM history reconstruction

Reviewed on 2026-10-15. `TODO.md` was not edited by this work. No game repository
was pushed.

## Checked-out results

- Lua: `spring-linux/games/Flove.sdd`, `codex/flove-platinum-lua`, `21c1bed`.
  There are 14 cohesive commits above upstream `0e6e705`. They contain the exact
  same final files as the previous 38-commit history, with related fixes grouped together.
- WASM: `spring-linux/games/Flove-wasm.sdd`, `codex/flove-platinum-wasm`,
  `e2af26a`. Its parent history contains that exact Lua tip, followed by exactly
  two commits:
  1. `6782c7b`: gameplay, input, UI, graphics, assets and existing port improvements.
     `Scripts/` and the Lua unit-script dispatcher are unchanged from the Lua tip.
     A temporary gadget bridges spire branch targets and creation-frame state.
  2. `e2af26a`: CUS unit scripts, their lifecycle wiring, removal of the Lua scripts
     and temporary adapter, and replacement of Lua's eye flare with the rules flare.

The three installed WASM modules were rebuilt without test features after the
checks. The first commit is a runnable intermediate version, not just a source split.

## Preserved originals and changes

In the Lua repository:

- `master` and `codex/flove-pre-platinum-lua`: original six local commits, `2572ce1`.
- `codex/flove-preserved-lua`: `4f13821`, including the three original uncommitted
  files: key bindings, end-game menu exit and `onlyLocal` metadata.
- `codex/flove-38-commit-lua`: `62aa627`, the complete history before the 14-commit
  consolidation. The new tip has exactly the same Git tree.
- `codex/flove-reviewed-lua-wip`: the intermediate review history before consolidating
  the restart repair into one coherent final commit.
- `codex-work/flove-preserved/lua-working-tree.patch`: the original uncommitted patch.

In the WASM repository, `flove-wasm-port` and `codex/flove-pre-platinum-wasm` preserve
`a297dad`; `codex/flove-wasm-review` additionally preserves the mouse-message and
branch-count repairs before reconstructing the two-commit history.
`codex/flove-before-lua-consolidation-wasm` preserves `bb7a302` and its previous
Lua prefix. Both rewritten WASM commits retain their previous Git trees exactly.

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

## Necessity and consolidation review

The old commit count was too large for the size of the code change. Relative to
upstream, the complete Lua delta is 2,307 added and 3,942 removed lines; excluding
Collada `.dae` model assets, it is only 361 added and 174 removed lines, including
comments and formatting. These are Git diff line counts, not a count of independent
bugs or executable statements.

The changes do not all represent necessary gameplay repairs:

- **Direct repairs:** removed startup APIs, broken rendering helper/GLSL calls,
  early aiming and effect-name failures, stale upgrade targets, unit-lifetime
  records, branch/power initialization, and retained restart state have concrete
  failure modes. These are worth keeping.
- **Compatibility and hygiene:** definition warnings, absent default sounds,
  empty feature/effect placeholders, local-only metadata, disabled analytics
  registration, archive exclusions and stale development artifacts are sensible
  maintenance. They should not inflate the apparent count of major game bugs.
- **Inherited visual revisions:** the golden-love effect and model exports were
  already present before this review. They are preserved as visual choices,
  not claimed as mandatory fixes. The model delta includes Collada unit conversion
  from `0.01875` to `1`, transform/geometry scaling, and re-export changes; it is
  not just whitespace. `LittleBrownMushroom.dae` is not referenced by the current
  unit definitions. Its revision remains preserved with the other inherited assets.
- **Launcher and controls:** returning exits to the bundled launcher and blocking
  ordinary RTS selection/orders fit the game's direct controls. The original
  outstanding key-binding edits are retained; restart and end-game UI corrections
  are grouped with the same player flow.

No change was removed in this consolidation. The assessment supports keeping the
functional repairs and maintenance, while treating the visual revisions as
separate choices whose necessity has not been established. No new behavior was
introduced merely to make the regrouping easier.

| Commit | Scope |
| --- | --- |
| `2bf2a16` | Load Flove cleanly on the current engine |
| `edb6dda` | Keep unit, weapon and effect definitions valid for the engine |
| `4d6d9c9` | Preserve the revised model exports and trigger texture |
| `4f85092` | Preserve the revised golden-love visuals |
| `b27c512` | Make material and wisp rendering survive shader compilation and reload |
| `5d42b76` | Resolve projectile lights by weapon definition ID |
| `b10327a` | Ignore units that disappear during drawing or mouse picking |
| `1261aa8` | Repair mushroom aiming and muzzle and death effects |
| `f526e60` | Reject stale upgrade targets before spending mana |
| `d03e2ad` | Initialize grove power and grow exactly the requested spire branches |
| `311a2ce` | Remove poison and flower-expiry records when units are destroyed |
| `f6f6701` | Block player RTS commands while retaining scripted AI and tree picking |
| `dcd7f89` | Restore story state and difficulty on restart and return exits to the launcher |
| `21c1bed` | Exclude development files from archive checksums and remove stale artifacts |

The consolidation checks prove byte-for-byte equality of the Lua final tree and
both WASM trees before and after rewriting. The first WASM commit still leaves
`Scripts/` unchanged, and the second still sits exactly two commits above Lua.
The eight Lua regression cases were rerun successfully; the existing runtime and
image results remain applicable because no tested file changed. Engine suites
were not repeated solely for changed commit IDs. The recorded image provenance
continues to identify the preserved pre-consolidation commits that actually ran.

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
