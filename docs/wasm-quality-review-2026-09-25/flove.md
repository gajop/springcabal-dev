# Flove review, round 3 (2026-09-25)

Paths are relative to `spring-linux/games/Flove-wasm.sdd/wasm-src/` unless stated otherwise. The Lua
original is `Flove.sdd/`. Reviewed at `0280dfe`.

## 1. Grade: B+ (was B)

Every bug and risk from round 2 is fixed, and the growth rules and victory flow now match the Lua
code line for line. The code is small, split by job and free of unsafe globals. What keeps it
below A−: the story's Skip action isn't gated. Round 2 fixed the ungated Continue; Skip has the same
problem, and it can make the trees permanently invulnerable or grant free trees without limit.
There are also a few undocumented Lua differences (spire branches, poison, zap impact sound). The
tutorial chain (stages 2 to 6) has no test at all.

## 2. Round-2 findings, status now

**Bugs**
- `set_stage` accepted any stage, so Continue on the king's story went back to the intro:
  **fixed**. `story.rs:84-89` only advances into Repel or Army Approaches. Tested at
  `integration.rs:397-412`.
- Growth differed from `grove_spawner.lua`: **fixed**. I checked interval, spread, the 1/d⁴
  weighting, the five-direction probe, the fallback spot, grass and the `IsSteep` quirks against
  Lua lines 180-364.
- Killing the king ended the game at once: **fixed**. The victory story shows first, and its
  Continue wins (`story.rs:22-30`, `hud.rs:137-139`).

**Risks**
- Spire shots on team 0: **fixed**, they now go out as Gaia (`spire.rs:174`).
- `spawn.rs:67` swallowed an error: **fixed**, it is logged now.
- A held button could keep zapping: **fixed**. The engine's mouse state wins, and the callin state
  is only a fallback (`gui_input.rs:73-81`).
- `hit_id > 0` excluded unit 0: **fixed**, units are picked with `spring::pick`.
- Reloading the document reopened the intro: **fixed** (`gui_rml.rs:40-55`).
- `GrassDetail` was saved to the player's config: **fixed**, it is session-only.
- Release builds accepted the test commands: **fixed**, they sit behind the `test-commands`
  feature.

**Cleanups**
- Trees registered twice: **still open**.
  - `growth.rs:96`, `spawn.rs:112` and `trees.rs:308` add the tree directly.
  - `gadgets/trees.rs:41-43` adds it again through `delay`, and a linear scan drops the duplicate.
  - Mushrooms are fixed.
- Per-unit piece tables: **fixed** (`unit_scripts/mod.rs:295-323`).
- Stage and event constants copied between rules and UI: **still open**. See `ui/src/state.rs:7-12`,
  `ui/src/integration.rs:8` and `ui/src/hud.rs` `PLAYER_TEAM_ID`.
- rules-unsynced finds the UI's context by name: **still open**
  (`rules-unsynced/src/outline/passes.rs:57`, `"flove-wasm"`).
- `desiredBranches` written and polled every frame: **partly fixed**.
  - The rules now publish it only when it changes.
  - The spire script's task still reads the rules param every frame (`unit_scripts/simple.rs:149`).
    CLAUDE.md's `with_cus_module` would let the rules call the script directly.
- Piece map fetched per flare: **fixed** (`spire.rs:211-222`).
- Outline pass reads rules params per unit per draw frame: **still open**. `createdFrame` is read
  for every visible tree on every draw (`outline/passes.rs:170`).

**Tests**
- The visual build included the Rust suite: **fixed**. It now builds only `test-commands`.
- Assertions that couldn't fail, and VictoryManager called directly: **fixed**. The checks are
  exact, and victory goes through the `story` message.
- `MIN_CHECKS = 20` was too loose: **fixed**. It is now 46 exact checks with `require_at_least`.
- Three drivers at once: **partly fixed**.
  - The scenario now waits for the rules suite.
  - The UI suite still runs alongside it and sends it `difficulty|1` and `story` (see N8).

## 3. New findings

### N1 (high). Skip Tutorial is offered and accepted at any story stage: invulnerable trees and unlimited free trees

- **Where**
  - `ui/src/story.rs:83-133`: `show_skip` is true for stages 1 through 6.
  - `ui/src/input.rs:136`: `S` fires `action_story_skip` whenever any story modal is open,
    including the king's (7) and the victory story (8).
  - `rules-synced/src/story.rs:91-99`: `skip_tutorial` has no guard.
- **In Lua**, the skip button exists only on the first text: `gui_story.lua:100-103` hides it on
  the first Next, and on king events (`:286-293`).
- **Consequences**
  - Skipping during Repel (stage 2): `set_stage(STAGE_ARMY_APPROACHES)` never clears
    `trees_take_no_damage`, which Repel set (`story.rs:141`, only cleared by Heal at `:145`).
    `love.rs:89` then zeroes all tree damage for the rest of the round.
  - Pressing `S` on the king's story in free play grows 3 trees, sets mana to 30 (it can also
    take mana away) and spawns wave 1 again. The next HUD poll reopens the king's story because
    `story_stage` is now 0 (`hud.rs` `is_king_approach`), so `S` can be pressed again: unlimited
    free trees.
- **Fix**
  - Rules: accept `skip_tutorial` only while `stage == STAGE_INTRO`.
  - UI: show the Skip button and handle `S` only on stage 1.
  - Test that a skip at stages 2 and 7 is rejected.

### N2 (medium). Skip Tutorial spawns wave 1; Lua only marks it spawned

- **Where:** `story.rs:98` calls `force_spawn_wave_1()` (`mushrooms.rs:134-140`), which spawns the
  wave's units at every spawn point.
- **In Lua** (`mushroom_spawner.lua:584`), skip only sets `waveConfig[1].spawned = true`. The first
  enemies arrive with wave 2, 100 + 5×33 frames later.
- **Consequence:** after a skip there is an extra wave of 3 normal mushrooms per spawn point, right
  away. `test_scenario.lua` doesn't depend on it; it spawns its own mushroom at line 148.
- **Fix:** add a `mark_wave_1_spawned()` for the skip path, and keep `force_spawn_wave_1` for
  stage 4 (Lua's `SpawnNextWave(true)`).

### N3 (medium). The spire shows one branch fewer than Lua at every power level

- **Where:** `spire.rs:34` asks for `power_level - 2` branches, clamped to 0..9.
- **In Lua** (`unit_spire_controller.lua` GameFrame), the loop `for i = branches, desiredBranches`
  is inclusive. `StartThread` runs `ShowBranch` at once (springcontent `unit_script.lua:404-409`),
  so the count settles at `desired + 1 = min(mordorLevel, 10) - 1`.
- **Consequence:** the first branch appears at power 100 in the port, against 25 in Lua (about 9
  level-1 trees). Lua also caps the level at 10, the port at 11.
- **Fix:** request `(power_level.min(10) - 1).max(0)`, and say in a comment why Lua ends up one
  higher.

### N4 (medium). The king's story blocks the player's attacks while the game keeps running

- **Where:** `input.rs:28-30`: `gameplay_active` is false while any story modal is open, and
  `gui_input.rs:66-68`/`:113-115` then drop clicks and release the held command.
- **Consequence**
  - The README says the story doesn't pause the game. It doesn't say that the player also can't
    zap while it is open.
  - Lua pauses the game.
  - The king's story opens in the middle of wave 14 (bombs, clusters, the king) and types for
    6.5 s. The player can only watch until they dismiss it.
- **Fix:** do one of:
  - pause outside `test_mode`;
  - leave spire input live while the story is up in free play (stages 7 and 8);
  - at least document this in the README.

### N5 (medium). Poison damages everything except flowers; Lua damages nothing but flowers

- **Where:** `love.rs:73-86` handles poison only against flowers. Anything else falls through to
  the tree-immunity check or to unchanged damage.
- **In Lua**, `unit_poisoner.lua` returns `0,0` for every poison hit.
- **Consequence:** each poison mushroom's once-a-second cloud (damage 1, AoE 320) now chips at
  trees, the spire and nearby mushrooms, including the poisoner itself.
- **Fix:** return `new_damage: 0.0` for every poison hit on anything that isn't a flower.

### N6 (low). Small Lua differences that aren't documented

- **The zap's impact sound is missing.** `unit_send_love.lua` ProjectileDestroyed plays
  `sounds/fairy dust.wav` (volume 5) where a zap lands. Nothing in the port plays it (no
  `fairy` anywhere in `*.rs`). Add it next to `upgrade_shots::projectile_destroyed`.
- **Extra effects.**
  - `upgrade_shots.rs:39` spawns `love_happy`, which the weapon's `explosiongenerator` already
    spawns, so it shows twice.
  - `trees.rs:306` spawns `dirtfling` on promotion; Lua has no promotion effect.
  - `love.rs:40` spawns `love_heals` on flowers for `zapecho` hits too; Lua does it only for `zap`.
- **Mushroom targeting.** In the nearest-target branch (`mushrooms.rs:322-337`), the port can pick
  the spire. Lua skips that branch when the nearest enemy is the spire (`SelectEnemy`:
  `nID~=spireID`) and falls back to the weighted pick. So mushrooms beeline for the spire more
  often than in Lua.
- **Flower-field slow.** Lua scales acceleration, braking and reverse speed as well as max speed
  (`unit_attributes.lua:219-243`). The port changes only max speed and wanted speed
  (`attributes.rs:205-223`).

### N7 (low). Silent failures that matter

- **`spire.rs:35-42`**
  - It caches `branches` before the `let _ =` rules-param write, so a failed write is never
    retried and the branches stop updating.
  - Log the error, and cache the value only once the write succeeds.
- **`story.rs:176`: the Heal stage's `set_unit_health` is `let _ =`.** If it fails, the trees stay
  at full health and Heal ends on the next frame, skipping a tutorial step. Log it.
- **`unit_scripts/simple.rs:9`: the flower collision volume write is `let _ =`.** If it fails,
  flowers block shots. Log it.
- **`ui/src/rml.rs:64-134`: `load` creates the context before the data model and document.** A
  later step can fail, or `ensure_document` can re-load after `forget`. Either way the old context
  and the bound callbacks are never destroyed, and the next attempt creates another
  `flove-wasm` context. Area17 has the same pattern.
  - Destroy the context on failure.
  - Reuse the context on reload.
  - This belongs in the shared RmlUi setup (engine TODO §4).

### N8 (low). The tests leave the tutorial chain untested and still interleave two drivers

- **The tutorial is never played.**
  - No test plays stages 2 to 6: the Repel spawns, the Heal damage, the ≤2-mushroom check, the
    upgrade gate or the per-frame mana reset.
  - The Rust suite goes from the intro straight to skip (`integration.rs:87`).
  - `test_scenario.lua:121` skips at once.
  - This is how N1 and N2 slipped through: `stage_skip_tutorial` (`integration.rs:380-394`) checks
    mana and trees, but not stage gating, wave 1 or `trees_take_no_damage`.
- **The UI suite drives the same round as the rules suite** (`ui/src/integration.rs:27-86`).
  - At its steps 5 and 30 (UI updates, not frames) it sends `difficulty|1` and `story` into the
    round the rules suite is checking.
  - That spawns five Repel mushrooms and sets `trees_take_no_damage` in the middle of the suite.
  - Its step-40 check passes only if those updates come before the rules suite's skip at start+60.
  - Run it before the rules suite, the way the scenario waits for it, or give it a round of its
    own.
- **Checks that bypass the engine.** Several rules checks call internals rather than the engine
  path:
  - `fire_zap` and `fire_flower_shot` directly, not through `zap`/`rmb` (`integration.rs:173-213`);
  - `add_upgrade_progress` directly, not through ProjectileDestroyed (`:216-241`);
  - `trigger_field_at` directly (`:357-370`).

  The landing handlers (`gadgets/upgrade_shots.rs`, `gadgets/flowers.rs:194-210`) are covered only
  by the scenario's pixel/count checks.
- **The scenario's pass line needs no minimum count** (`test_scenario.lua:262`), and
  `flove.sh headless` only prints the counts.
- **`test_scenario.lua` ships in the archive.** It is only disabled by the modoption.

### N9 (low). Structure and dead code

- **`SpireState.target_pos`** (`spire.rs:12,63,93`) is written and never read. Lua's heading/pitch
  code that would have used it is dead there too (`targetx` is never set).
- **The `!self.tutorial_skipped` check in `StoryManager::update`** (`story.rs:106`) can't be false:
  a skip sets free play, which returns early at `:102`.
- **`hud.rs` `update_story` closes the modal again on every UI update** in free play before the
  king appears. `story_stage` only follows positive stages (`hud.rs:76`), so
  `story(0) != prev_stage(6)` stays true, and it calls `set_class` every update.
- **Leftovers in `unit_scripts/mod.rs`**
  - `:212` has an animation-trace leftover, `let _ = (_ctx.unit(), _kind);`.
  - `fire_weapon` is an empty override.
  - Every unit allocates two `Rc<RefCell<…>>` mushroom states, whatever its kind.
- **Candidates for the shared crate**
  - `send_to_rules` (`ui/src/input.rs:17-25`).
  - The per-game `diagnostics` warn/check helpers.
  - The RmlUi load/bind boilerplate (`ui/src/rml.rs`, about 200 lines).
  - The status-on-a-carrier-unit pattern (`status.rs`, and the UI's `Hud::carrier`), if other games
    need a "survives the spire" channel.
- **Global state:** only immutable `OnceLock` def and piece caches (`definitions.rs:56`,
  `spire.rs:212`, `outline/passes.rs:34`, `ui/src/defs.rs:11`). No `thread_local!`, `static mut`
  or `unsafe`.

No new borrow-across-callin risks. Every gadget that creates or destroys units under a roster borrow
(waves, growth, promotion, wilt, restart) has its UnitCreated/UnitDestroyed side defer through
`ctx.delay`. PoisonGadget copies its roster before spraying.

## 4. Strengths

- **Faithful and documented:** the growth and wave schedule, the story gating, and the victory and
  defeat flow match the Lua code. Each quirk is documented in place (the `IsSteep` repeated probe,
  the `SpawnGrass` x/z mix-up, 33 frames per second).
- **Small gadgets:** one job each, and every file is under 470 lines. Shared state is a set of
  separately borrowable `Resource`s. Round state is reset in one place (`round.rs:236-275`), with
  the reason for its ordering written down.
- **Engine SDK adoption:** `CusHost` unit scripts with only the pieces each kind needs, and the
  engine's cylinder query, pick, mouse, `cmd`, `GAME_SPEED` and synced RNG.
- **The defeat broadcast survives the spire's death,** because the status moves to another carrier
  unit. This is tested (`integration.rs:472-482`).
- **Visual shots are frame-exact** (video-capture mode), and the headless suite waits for clean
  exit markers.
