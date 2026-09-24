# WASM ports quality review, round 2 (2026-09-24)

This is a second review, done after two refactor rounds and the move onto the shared `springcabal`
crate. The first one is [`wasm-code-review-2026-09-23.md`](wasm-code-review-2026-09-23.md). Four
read-only reviewers covered the seven games, the crate, the verification harness and the repo.

- Paths are relative to `spring-linux/games/<Game>-wasm.sdd/wasm-src/` unless stated otherwise.
- Line numbers are from the day of the review.
- Engine-side findings went to `spring-bar/WASM_GAME_API_TODO_2026-09-24.md`: §1-§4 from the refactor
  rounds, §5-§10 from this review.

## Grades

| Area | Grade | Top problems |
|---|---|---|
| MyCube | B+ | Ctrl+R restart probably ends in an immediate loss; silent terrain/health failures; the tests prove less than they claim |
| TTLD | B+ | Heartburn differs from Lua (flat 2D damage, enemies only); the staff flicker is frozen in the shipped game for screenshots; weak visual checks |
| Gravitas | B (rules B+, ui C+) | Robots forget their assault after fleeing; the ui module still has global state and isn't on the crate; e2e only tests the arena |
| Flove | B | "Continue" on the king story sends the game back to the intro stage; growth and victory differ from Lua; tests run three drivers at once |
| Parts Needed | B | The plates never get their own ONOFF, so their script never runs; the UI's form-switch prediction can stick; tests that can't fail |
| Hunted | B | The flashlight doesn't scare rabbits; there is one panic slot, mines use the shotgun's scare values, and the HUD lags; weapons, scoring and restart are untested |
| Area17 | B− | All collision damage is a flat 20 (engine §10 plus swapped arguments); a Rust copy of the UFO's health drifts from the engine; thin tests |
| springcabal crate | B− | Unpinned git dependency; adoption differs across games; 4 of 6 modules untested |
| Verification harness | C+ | Every count doubled (`last.combined.txt`), which let Hunted pass with one wave; no lock inside `verify`; most suites ignore the engine exit status |
| Repo hygiene | C | `just setup-dev-engine` deletes its own config; ~21 GB of clutter; stale docs |

## What improved since round 1

Structurally, every game went from god-state and hand-rolled fan-out to gadgets and widgets that
own their state:
- No `WORLD`, `UI_STATE`, `static mut` or `unsafe impl Sync` is left, except in Gravitas' ui fire
  code (uncommitted WIP).
- Defs are resolved once.
- Files are under 500 lines, except data tables.
- The known re-entrancy sites release their borrows before calling the engine.
- The engine APIs are adopted: `HideDefaultInterface`, `with_cus_module`, `spring::cmd`,
  `game::frame` and the engine RNG.

The work also found and fixed real bugs:
- double `Create` in Area17 and Hunted;
- music that never looped in five games;
- script calls silently dropped by the `call_unit_script` argument bug;
- MyCube's iglu and drill scripts;
- Hunted's rabbit facing.

`let _ =` counts dropped by 30–40%, and every call whose failure breaks gameplay is now logged.

## What's left: themes

1. **Fidelity to the Lua originals is now the weakest point.** Most remaining bugs are behaviour
   that quietly differs from Lua:
   - Heartburn, collision damage, the flashlight scare, the plate ONOFF;
   - robots fleeing with STOP+MOVE, Flove's growth rules and its victory flow.

   None of these is documented.
2. **Tests prove less than they claim.**
   - Assertions that can't fail (`check(true)`, `>= before` on values that only grow).
   - Checks that call internals directly instead of going through the engine (MyCube combat,
     Gravitas input, TTLD victory).
   - Screenshots that are taken but never compared.
   - Doubled counts.
   - Test code that changes the shipped game: TTLD's staff flicker, Flove's release test commands.
3. **Engine gaps show up as game bugs.**
   - Negative damage ids (engine §10).
   - Hit types (§6/§9).
   - Per-callin host limits (§3).
   - The unit-script host (§5).
   - The scheduler losing parent tasks (§8).
4. **The shared crate is new and adopted unevenly.**
   - Gravitas' ui can't take the dependency while its `Cargo.toml` holds WIP.
   - MyCube and Hunted rewrite `quit_after`.
   - `require_at_least` is optional.
   - Every UI has its own `send_lua_rules_msg` wrapper.

## Findings per game (bugs and risks; cleanups condensed)

### Area17 (B−)

**Bugs**
- `fall_damage.rs:311`: `add_unit_damage(unit, dmg, 0.0, -1, CRUSHED, …)` swaps weapon and
  attacker. Because of engine §10, every collision is then turned into a flat 20 by
  `unit_fall_damage.rs:74`. Fix the arguments, and mark damaged units to skip in
  `unit_pre_damaged` until the engine passes negative ids through.
- `weapon_handlers.rs:55-72` keeps its own copy of the UFO's health, and the copy misses the debris
  hits. `upgrades.rs:178-190` rescales max health from that copy, so an armor upgrade can heal. Use
  the engine's health.
- `game_terrain.rs:156-163`: the footprints are hard-coded and skip `Building4BigTank`
  (`terrainblock_x = 96`). Read the `terrainblock` custom params.
- Ability sounds play twice. `gui_ufo_control.rs:214` also plays one while on cooldown or locked.
- Undocumented `human.rs` differences from Lua:
  - the scream plays once;
  - floating waits for the walk cycle;
  - `land` requires `floating`;
  - the unit-unit collision pass drops WAIT, ally handling and feature immunity.

**Risks**
- `unit_ufo_controller.rs:68-72` resets `game_over`/`game_won` on respawn.
- `rml/lifecycle.rs:97-99` leaks the context when the document load fails and retries every frame.
- `gadgets/dbg_visual_integration.rs:28` holds a borrow across `destroy_reclaimed`.

**Cleanups**
- Each unit builds every `ScriptKind` state (about 70 piece lookups); build only the one it needs.
- Dead named calls (`SetCurrentWeapon`, …).
- `PDisUnlocked` is a rules param read per AimWeapon.
- `AREA17_DRONE` could be the UI's own `unit_created`.
- `upgrades::update` calls `initialize()` every frame.
- `human.rs:152` re-applies the stop pose every 100 ms.
- `fire.retain` inside a 7×7 loop.
- The UI does its mouse work twice.
- The shield state is set every frame.
- Tech costs are copied between the UI and the rules (add an `area17-shared` crate).
- HUD rectangles are hard-coded in `pointer.rs`.

**Tests**
- There is no check for fall damage, abduction, capture, heal, the endcube win, civilians, drones,
  terrain, costs or the UI→rules path.
- The Lua scenario suite only re-observes what the Rust suite does, and it ships in the archive.

### Hunted (B)

**Bugs**
- The flashlight scare is missing (Lua `shotgun.lua:52-61,134-141,179`, radius 200, 1.8/0.1). The
  rules already get the target through `movegun`.
- Mines scare with the shotgun's values (300/150) instead of 250/400 (`weapons.rs:279-282`).
- `Panic` is a single slot (`state.rs:109-126`); the last scare wins.
- Firing, mines and the flare bonus don't set `status_dirty`, so the HUD lags by up to 1 s.
- `weapons.rs:200-211` creates the mine before it checks the timer slots.

**Risks**
- `rabbits/eating.rs:19-26` teleports the carrot every update, which isn't documented.
- A failed static spawn is retried every frame with an unthrottled warning.
- `restart` is accepted twice.
- Warnings are compiled out without the `diagnostics` feature.
- `with_rabbit_ctx` holds two resources for the whole AI pass; safe today, but not documented.

**Cleanups**
- 600 position reads every frame before the `next_update` check.
- Lighthouse rules params are read by string every frame.
- Mines scan every rabbit instead of doing a cylinder query.
- Visibility runs per draw update.
- `Shadows=0` duplicates `launch/`.
- `forcestart` is resent on HUD rebuild.
- `warning_once` shares one flag across messages.
- `STATUS_PREFIX` is defined twice.

**Tests**
- Only the spawn, the waves, one rabbit moving and one pickup are checked.
- The "status reached the UI" check greps a rules-side log line.
- The suite links installed modules.
- Shots are timed in draw updates; only 3 of the 4 are compared.
- No host tests for the pure AI functions.

### Flove (B)

**Bugs**
- `story.rs:120-121`: `set_stage` accepts any stage. After the king spawns, Continue moves the game
  from free play to the intro: waves and growth stop, and mana is zeroed every frame. Lua only
  advances stages 2–7.
- Growth rules differ from `grove_spawner.lua`: interval, first tree, spacing, placement weighting,
  grass count (`growth.rs:25-34,88-129,196-203`).
- Killing the king ends the game immediately; Lua shows the victory story first
  (`gadgets/mushrooms.rs:61-64`).

**Risks**
- Spire shots are on team 0 (enemy); Lua uses Gaia (`spire.rs:242,271`).
- `spawn.rs:67` swallows the error that makes the spire undestroyable.
- The held button is the engine state OR tracked state, so a missed release keeps it zapping.
- `hit_id > 0` excludes unit 0 (`ui/src/input.rs:208`, `outline/passes.rs:271`).
- Reloading the document reopens the intro.
- `GrassDetail` is saved to the user's config permanently.
- Release rules accept the test commands `add_mana`, `upgrade`, `field_of_flowers` and `flower`.

**Cleanups**
- Trees and mushrooms are registered twice.
- Every unit builds the mushroom and spire piece tables.
- Stage, event and param constants are copied between rules and UI; add a `common` crate.
- rules-unsynced finds the UI's RmlUi context by name.
- `desiredBranches` is written and polled every frame.
- The whole piece map is fetched per flare.
- The outline pass reads rules params per unit per draw frame.

**Tests**
- The visual build includes the Rust integration gadget, which restarts the round between shots 3
  and 4, so shots 4–7 show a fresh tutorial round.
- Assertions that can't fail: `integration.rs:242-245,251,261,284`, and VictoryManager called
  directly.
- `MIN_CHECKS = 20` is too loose.

### Gravitas (B)

**Bugs**
- `robots.rs:62-72`: STOP followed by MOVE drops the FIGHT assault. Lua inserts the escape move at
  the front of the queue.
- The death animation is never played; the ~940-line `DIE` table is dead.
- `gadgets/level.rs:38-41`: any Gravit's death is a loss; check the player unit.

**Risks**
- Robots never fire while moving: the explicit-target rules params are never set, yet they are
  read by about 110 robots every frame. Check against Lua, then remove.
- Level rules params are set after `create_unit`, so `UnitCreated` handlers see defaults (hazard
  size, respawn adoption).
- Deferred script attach doesn't re-validate the unit (TTLD does).
- Restart resets `Global` field by field.

**Cleanups**
- `probe.rs`/`Terrain.levelled` ship.
- `unit_piece` fetches the whole piece map per call.
- `fire.rs` reads `invulnerable` by name every frame.
- The input formats two Strings per frame.
- A hand-written `atan2`.
- `jump::blocked` loops forever if `jumpSpeed` is 0.
- The ui module isn't on the crate: music, shots, keys, menu, status parsing.

**Tests**
- The "re-entered world state" check greps a string nothing emits any more.
- The `visuals` case can't fail.
- `input` injects commands into `Global` instead of sending messages.
- All 14 cases share one arena, and restart relies on the others finishing first.
- The real level is never checked.

**WIP (uncommitted fire work)**
- The `fire-probe` feature doesn't build.
- `fire_distortion.frag` writes depth into the alpha mask, so the mask no longer works.
- The distortion size clamp was removed while the strength was tripled.
- A new hand-written LCG.

### TTLD (B+)

**Bugs**
- Heartburn (`player/spells.rs:280-287,409-445`): the fireball's own damage is zeroed and replaced
  by a flat 1600 to enemies in a 2D cylinder, with no falloff or impulse, and it is skipped if the
  caster died. Lua uses AoE 500, edge 0.9, impulse 0.6, damages every team and leaves a crater.

**Risks**
- `lights/mod.rs:41-44` freezes the staff flicker in the shipped game; gate it behind `e2e`.
- Right-click sends `attmove` on press and `attack` on hold.
- A boss that failed to spawn counts as an instant victory.
- `killed()` transfers the unit inside a CUS export; this is documented but untested.

**Cleanups**
- Rules talk to their own scripts through public rules params (`firing`/`fireTx`).
- `STATUS_PERIOD` and `GameEnd` are defined in both crates.
- `boss_x`/`boss_z` are written and never read.
- The highlight runs its pipeline even with no hovered unit.
- Deferred lighting retries shader compiles every frame.
- House lights scan all units until houses exist.
- The UI polls `on_fire` on all 107 houses.
- `DeathParalysis` entries are never pruned.
- `dbg_e2e` doesn't use `Screenshots`.

**Tests**
- The heartburn check passes on any health loss.
- The stun checks return early when the mage is invalid.
- The victory check forces the gate.
- Most of `dbg_e2e`'s log lines are never checked.

### MyCube (B+)

**Bugs**
- `gadgets/game_end.rs:16,24`: `FIRST_CHECK_FRAME = 6` is an absolute frame, so a restart probably
  ends in an immediate loss.
- The survival time includes earlier rounds.

**Risks**
- `terrain.rs:65-67`: a failed height-map job is retried forever, silently.
- A failed health read becomes 0 and the unit dies without a log line.
- The manual `activate` would run twice if the engine starts queueing Create (engine §2).
- `story.rs:62-73`: the placement loop has no cap.
- The integration tracker holds four resources; switching it to real damage would panic.

**Cleanups**
- `SetupGadget` only turns on LOS.
- `GameEnd` and the frame rates are duplicated between rules and UI.
- The UI hard-codes max health.
- `GAME_SPEED` 30 vs `FRAMES_PER_SECOND` 33 confusion.
- Sell mode does 676 height queries per mouse move.
- The healthbars sort all units every draw.
- The status is formatted every frame just to compare it.
- Root `mycube-*.cwasm` files.

**Tests**
- The combat check calls `unit_pre_damaged` directly.
- The drill check reads a flag set before the order is given.
- 2 of the 5 visual shots are never compared.
- Story timings are fast-forwarded.
- Untested: drowning, craters, warming, freeze/starve death, the loss path, restart.

### Parts Needed (B)

**Bugs**
- `triggers.rs:64-71`: plates never get their own ONOFF (Lua `unit_plate.lua:147`), so
  `props.rs:62-70` never runs.
- `input.rs:31-41`: `form_frame` is updated even without eyes. The UI prediction then sticks or
  inverts (`api_sync.rs:42` only times it out when a status arrives).

**Risks**
- Cages linked from both a lever and a plate flip every 5 frames (last link wins; `LINKS:222-257`).
- Undocumented differences from Lua:
  - gate 20 can re-close;
  - cages resolve immediately instead of after about 40 frames;
  - there is no stop glide;
  - the trail is new.
- Restart is accepted about 160 frames before the prompt shows.
- A LuaUI reload loses the send-on-change status; resend it on a hello message.

**Cleanups**
- `level/mod.rs:76` looks defs up by name.
- `wisp/idle.rs` is 95 unrolled `turn()` calls.
- An enum repeats the `WispPieces` fields.
- `Rc<RefCell>` wraps a `Copy` struct.
- The lever reach is defined three times.
- The Ctrl+Q engine bind duplicates the crate.
- Game-over NPC scans and sprite rules-param reads run every update.
- The trail is stepped per draw frame, so it depends on FPS.

**Tests**
- "Wisp animated while walking" passes on the bob alone.
- "Game-over blocks form switch" never sends a switch.
- A table is tested against itself.
- The ending shots are never compared.
- There is no check for the plate script, the kill plate, the UI→rules path or restart.

## Infrastructure

### springcabal crate (B−)
- The dependency is an unpinned git URL, and the lockfiles don't record a source because the path
  patch takes over. A fresh clone needs undocumented setup, and provenance doesn't record the crate.
- `Encoder` doesn't escape `|`/`=` and writes NaN, which `Fields::f32` then rejects without a trace.
  `flag()` reads "false" as true. `check::Suite` passes with 0 checks unless `require_at_least` is
  set. `Screenshots` only checks ordering with a `debug_assert`. `MusicLoop` logs a failure only
  once, even after `switch`.
- 4 of the 6 modules compile only for wasm32 and have no tests; inject a sink or clock to test them.
- The docs name `send_lua_ui_msg`, but every game uses `send_to_unsynced`.
- Missing: `send_to_rules`/`send_to_ui` wrappers (all seven UIs write their own).

### Verification harness (C+)
- `last.combined.txt` doubles every count. Hunted's `waves >= 2` passes with one wave, Gravitas
  lists every case twice, and the unit-script traces are fed twice.
- No lock inside `verify`, and BASELINE.md gives a stale reason for locking (the port is now
  random).
- Only Hunted checks the engine exit status. Visual suites accept a timeout. Area17 headless has no
  panic/trap forbid. The traps misbehave on Ctrl+C.
- `run-wasm.sh`'s `exec` skips its EXIT trap; the relaunch path is probably dead.
- `area17 static` builds inside the checkout. The Flove visual suite skips `vf_graphics` and all
  checks.
- Provenance gives untracked folders the dev repo's commit and records spring-bar HEAD rather than
  the binary's version. Goldens don't check the renderer.
- The gallery strips UI modules, so UI effects never show. The camera distance comes from the def
  radius (MyCube's iglu). MyCube, which has no CEGs, crashes the CEG gallery.

### Repo hygiene (C)
- `justfile:115`: a backtick inside a string runs `just remove-dev-engine`, which deletes the config
  the recipe just wrote. The recipe also writes only the spring patch.
- The unanchored `springsettings.cfg` in `.gitignore` matches `launch/springsettings.cfg`.
- About 21 GB of ignored clutter:
  - `verification/out/` 15 G
  - `wasm-backups/` 5.7 G
  - `area17-test/`
  - root `*.cwasm`
  - `*-work/`
- Stale docs:
  - BASELINE.md (`~/.cargo`, the HostPort reason, doubled "2 errors");
  - this directory's previous review links a renamed TODO;
  - README layout and the relaunch description.

## Follow-up (in progress at the time of writing)

- **Harness and hygiene fixes:** the double counting, the lock inside `verify`, exit status,
  provenance, the justfile, `.gitignore`, docs and a cleanup recipe.
- **Gallery:** show UI-drawn effects, frame the camera from model bounds, record the GPU/driver,
  skip cleanly when a game has no CEGs.
- **`springcabal-control`:** WASD/mouse movement and camera follow, plus a restart helper.
- **Game fix round:** the bugs and risks above, starting with the Lua-fidelity bugs and the tests
  that can't fail.
