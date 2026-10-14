# Flove Lua review and WASM history reconstruction

Reviewed on 2026-10-15. `TODO.md` was not edited by this work. No game repository
was pushed.

## Checked-out results

- Lua: `spring-linux/games/Flove.sdd`, `main`, `e93965f`.
  There are 15 cohesive commits above upstream `0e6e705`: the consolidated 14,
  with the spire-loss growth guard folded into unit lifetimes, plus one commit for
  hover highlighting and animated outlines. The earlier consolidation preserved
  the 38-commit final tree exactly; the subsequent additions are described below.
- WASM: `spring-linux/games/Flove-wasm.sdd`, `rust`,
  `3f08377`. Its parent history contains that exact Lua tip, followed by exactly
  two commits:
  1. `399d38c`: gameplay, input, UI, graphics, assets and existing port improvements.
     `Scripts/` and the Lua unit-script dispatcher are unchanged from the Lua tip.
     A temporary gadget bridges spire branch targets and creation-frame state.
  2. `3f08377`: CUS unit scripts, their lifecycle wiring, removal of the Lua scripts
     and temporary adapter, and replacement of Lua's eye flare with the rules flare.

Both game repositories have matching local `main` and `rust` refs. The Lua folder
is checked out on `main`, and the WASM folder on `rust`; both are clean. The
`codex/flove-platinum-*` aliases and historical backup branches remain available.

The three installed WASM modules were rebuilt without test features after the
checks. The first commit is a runnable intermediate version, not just a source split.

## Preserved originals and changes

In the Lua repository:

- `master` and `codex/flove-pre-platinum-lua`: original six local commits, `2572ce1`.
- `codex/flove-preserved-lua`: `4f13821`, including the three original uncommitted
  files: key bindings, end-game menu exit and `onlyLocal` metadata.
- `codex/flove-38-commit-lua`: `62aa627`, the complete history before the 14-commit
  consolidation. The initial 14-commit tip had exactly the same Git tree.
- `codex/flove-before-outline-lua`: `21c1bed`, the 14-commit state before the
  additions requested in this follow-up.
- `codex/flove-reviewed-lua-wip`: the intermediate review history before consolidating
  the restart repair into one coherent final commit.
- `codex-work/flove-preserved/lua-working-tree.patch`: the original uncommitted patch.

In the WASM repository, `flove-wasm-port` and `codex/flove-pre-platinum-wasm` preserve
`a297dad`; `codex/flove-wasm-review` additionally preserves the mouse-message and
branch-count repairs before reconstructing the two-commit history.
`codex/flove-before-lua-consolidation-wasm` preserves `bb7a302` and its previous
Lua prefix. `codex/flove-before-outline-wasm` preserves `e2af26a`.
The latest WASM commits change only their README relative to the corresponding
previous port trees; all implementation, assets and installed binaries are identical.

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
upstream, the consolidated 14-commit Lua delta was 2,307 added and 3,942 removed lines; excluding
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
- **Model compatibility:** paired GPU runs of the same isolated scene, changing
  only the Collada files, show most mushrooms and all three trees collapsing to
  tiny or invisible geometry with upstream exports. The revised exports render
  normally. Upstream exports use Collada `meter="0.01875"` and nonuniform node
  transforms; the current engine importer warns that nonuniform scaling is
  unsupported and retains only the X scale (`AssParser.cpp`, lines 199–210).
  Revised exports use unit scale and baked geometry/transforms. The upstream run
  emits five scaling warnings; the revised run emits none. This establishes a
  compatibility repair, not an optional cosmetic change. The isolated scene
  covers the referenced mushrooms, trees and several grasses; it does not prove
  every byte of every export is required. The unreferenced `LittleBrownMushroom.dae`
  revision remains preserved with the other inherited assets.
- **Golden-love effect:** `love_golden` already exists in upstream Lua. The
  2015-12-15 commit `9b74567` introduced the distinct shot visual; local commit
  `20a1276` revised its particle/heat-cloud appearance in 2026. That exact local
  revision remains in both versions. The review did not invent or remove the effect.
- **Launcher and controls:** returning exits to the bundled launcher and blocking
  ordinary RTS selection/orders fit the game's direct controls. The original
  outstanding key-binding edits are retained; restart and end-game UI corrections
  are grouped with the same player flow.

No change was removed in the consolidation or this follow-up. The latest Lua
comparison against `21c1bed` changes exactly four paths: the one-line spire-loss
check in `grove_spawner.lua`, the outline widget, the tree material shader, and a
shared deformation helper. WASM's original `rules-unsynced` implementation is
byte-for-byte unchanged. Its RmlUi UI, shortcuts, grass detail, animated outlines,
hover rim and unit scripts remain preserved.

| Commit | Scope |
| --- | --- |
| `0d6ebe5` | Load Flove cleanly on the current engine |
| `d4f25a8` | Keep unit, weapon and effect definitions valid for the engine |
| `a3f5009` | Fix model units and scaling for the current Collada importer |
| `ab83495` | Preserve the revised golden-love visuals |
| `4388698` | Make material and wisp rendering survive shader compilation and reload |
| `1b8883a` | Resolve projectile lights by weapon definition ID |
| `798b4d3` | Ignore units that disappear during drawing or mouse picking |
| `29a3b66` | Repair mushroom aiming and muzzle and death effects |
| `3104ed3` | Reject stale upgrade targets before spending mana |
| `ed5c287` | Initialize grove power and grow exactly the requested spire branches |
| `10fd4df` | Handle destroyed units in poison, flower expiry and tree growth |
| `4ebe25e` | Block player RTS commands while retaining scripted AI and tree picking |
| `02c54a5` | Restore story state and difficulty on restart and return exits to the launcher |
| `78b749b` | Exclude development files from archive checksums and remove stale artifacts |
| `e93965f` | Highlight upgradeable trees and keep outlines aligned with sway and growth |

The earlier consolidation proved byte-for-byte equality of the Lua final tree and
both WASM trees. This follow-up verifies the explicit four-path Lua delta and
README-only port deltas instead. The first port leaves `Scripts/` and the Lua
unit-script dispatcher unchanged from the new Lua tip; WASM still has exactly
two commits above Lua.

## Requested Lua presentation features

Both features existed in the original WASM port but had never been brought into
Lua. They were missed during the earlier Lua review, not discarded in the rewrite.

- Hovering a live level 1 or 2 tree gives it a green rim. Level 3, dead units,
  the minimap, off-window positions and Chili-covered positions do not advertise
  an upgrade. Premultiplied colour filtering preserves the rim through blur.
- The silhouette and material shaders call the same `deformTree` function with
  matching per-unit sway, growth fraction and height. This also follows the
  spire's smaller sway. The outline pass clears its depth each frame and skips
  hidden effect markers; raw model drawing prevents material callbacks from
  overwriting outline uniforms. The line fallback retains hover highlighting.

The GPU probe captures hover on levels 1, 2 and 3 and the pointer away from trees.
Both shaders compile with zero errors. The callback regression compares the
actual material and silhouette uniforms across four sway/growth frames, including
an incompletely grown tree. This is focused rendering verification, not an
exhaustive camera/driver sweep.

![Same isolated scene with upstream exports (left) and revised exports (right)](/home/gajop/projects/spring-projects/springcabal-games/verification/out/flove-presentation-review/model-comparison.png)

## Lua fixes and port equivalents

| Lua repair | WASM behavior |
| --- | --- |
| Skip weighted tree growth when the destroyed spire has no position. | Existing growth code already returns when `ground_position` is missing. |
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

- The earlier review parsed 115 game-owned Lua files; this follow-up reparsed all
  101 files under LuaRules, LuaUI, ModelMaterials, Scripts, units, weapons and effects
  in the consolidated checkout. They pass `luac -p`.
- Nine Lua gameplay/lifetime regression cases and three outline regression groups pass.
  The earlier eight-case suite had seven failures against the preserved pre-review game.
- `./verification/verify probe flove-lua-review` verifies Lua LMB, upgrades, loss,
  restart with cheats already enabled, one replacement spire, intro state and
  retained Hard difficulty. The updated run passes after repairing tree growth
  following spire destruction. The three gameplay screenshots were inspected in
  the earlier review; the current run produces three again.
- `./verification/verify probe flove-presentation-review current` and
  `./verification/verify probe flove-presentation-review upstream-models` compare
  identical GPU scenes and produce four screenshots each. Current: zero errors,
  zero warnings. Upstream models: zero errors, five unsupported-scaling warnings.
  The level 1/2/3 hover images and the model comparison were visually inspected.
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

The unchanged WASM implementation was not rebuilt or retested solely for the
new Lua ancestry and README. Its recorded runtime, physical input and animation
results continue to apply.

Evidence is under `verification/out/flove-presentation-{current,upstream-models}/`,
`flove-presentation-review/`, `flove-lua-platinum/`, `flove-port-first/`,
`flove-port-final/`, `flove-input-platinum/`, and `flove-animation-{lua,rust}/`.
