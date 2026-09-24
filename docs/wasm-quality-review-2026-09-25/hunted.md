# Hunted review, round 3 (2026-09-25)

Paths are relative to `spring-linux/games/Hunted-wasm.sdd/wasm-src/` unless stated otherwise. The Lua original is `../Hunted.sdd`.

## 1. Grade: B+ (was B)

Every round-2 bug and risk is fixed. The rabbit AI arithmetic now lives in a host-tested crate (26 tests). The headless suite went from 4 checks to 21 real ones, covering weapons, scoring, the flare and restart. The structure is clean. It isn't an A− because two Lua gadgets were never ported: `unit_invulnerable.lua` and `unit_blocking.lua`. Without them the player's own shots and mines destroy carrots, which changes the core loop.

## 2. Round-2 findings, status now

**Bugs**
- Flashlight doesn't scare: **fixed.** `rabbits/senses.rs:168-175` and `ai/src/scare.rs:52-60` include the map-edge fade from `MoveShotgun`. The README documents that it only starts at the first mouse target.
- Mines scare with shotgun values: **fixed** (`Area::MINE` is 250/400).
- Single `Panic` slot: **fixed.** `Scares(Vec<Source>)`, and every blast in a frame is applied (`rabbits/mod.rs:199-211`).
- HUD lags after firing, mines or the flare: **fixed** (`Global::status_changed`, checked by the integration suite).
- Mine created before the timer-slot check: **fixed.** Any number of mines is allowed.

**Risks**
- Carried carrot teleported every update: **documented** in the README ("Differences").
- Failed static spawn retried every frame: **fixed** (`spawning.rs:19-23`).
- Restart accepted twice: **fixed.** It is accepted once and only after game over (`restart.rs:146-154`), and tested.
- Warnings compiled out without `diagnostics`: **fixed.**
- `with_rabbit_ctx` holds two resources: **documented** (`rabbits/memory.rs:141-148`). I checked the engine calls made inside it (positions, move-type setters, move goal, `set_unit_position`, CEG); none raises a callin.

**Cleanups**
- Position reads before `next_update`: **fixed**, except on frames with a blast.
- Mines scanning every rabbit: **fixed** (cylinder query).
- Visibility pass per draw update: **fixed.** It runs once per frame, target or flare change.
- `Shadows=0`, `forcestart` resent, `STATUS_PREFIX` defined twice: **fixed.**
- `warning_once` sharing one flag: **fixed** in the rules (a `Once` slot per message); the UI keys on the message text.
- Lighthouse rules params read by string every frame: **still open**, in the rules (`rabbits/senses.rs:154-164`) and in the UI (`ui/src/visibility.rs:117-121`).

**Tests**
- Only spawn, waves, movement and one pickup were tested: **mostly fixed.** 21 assertions now cover the flashlight, the shot scare, ammo, mines (the fuse on a hill, the timing, the blast), kills, the score tick, the flare and restart.
- "Status reached the UI" grepped a rules log: **fixed.** It now greps the UI's `status received` line.
- Suite linked the installed modules: **fixed** (staged).
- Shots timed in draw updates, only 3 of 4 compared: **fixed** (game frames, 4 goldens).
- No host tests for the AI: **fixed** (`ai/`, `just test`).

## 3. New findings

### High

**H1. Carrots, burrows, carried and dropped carrots, and the gun can be destroyed. In Lua they are invulnerable.**
- *What's missing:* Lua `LuaRules/Gadgets/unit_invulnerable.lua` returns 0 damage for everything except rabbits, lighthouses and mines. The port has no `unit_pre_damaged` anywhere (`grep -rn pre_damaged rules-synced/src` finds nothing). `Hunted-wasm.sdd/LuaRules/Gadgets/` holds only `unit_script.lua`, and the unit defs are byte-identical to Lua's.
- *Why the damage kills:* a shotgun pellet does 50000 damage (`Weapons/shotgun.lua`) and a mine blast does 150000 over an area of 200 (`Weapons/mineexplode.lua`). All carrot kinds and burrows have 800 HP; the gun has 860.
- *Why the pellets hit carrots:* they are fired as Gaia (`weapons.rs:159-171`, with the gun as owner), so carrots on team 0 are enemies and collide with them.
- *Evidence:* in `wasm-test/write/logs/wasm-20260924-015401-3904486.infolog.txt`, the status at frame 300 reads `carrots=96 stolen=0 shots=8`. Four carrots were gone with none stolen. Eating a carrot doesn't change the count, because the carried carrot replaces the field carrot.
- *Consequence in play:*
  - Shooting rabbits in a field kills the carrots they are eating.
  - A mine placed in a field (the natural place for one) clears every carrot within 200.
  - Each lost carrot costs a point per second and ammo regrowth, and brings the game over closer.
  - A burrow can be blown up. It then drops out of `roster.positions(Burrow)`, so carriers go elsewhere, but rabbits still spawn at its coordinates.
  - A mine near the gun can kill the gun.
- *Fix:* add `unit_pre_damaged` to a gadget (for example `Roster`, which knows each unit's kind) that returns 0 for every kind except `Rabbit`, `Lighthouse` and `Mine`.
- *Test:* add a check that a shot and a mine blast in a field leave `carrot_count` unchanged.

**H2. `unit_blocking.lua` isn't ported either.** Lua calls `SetUnitBlocking(unit, false, false)` on `carrot_carried` and `burrow` (not blocking, not collidable). In the port, burrows block (1×1 footprint) and take hits. Rabbits spawn within 0–144 elmos of the burrow centre (`spawning.rs:34`), often inside it. The carried carrot collides for a moment after its creation and during the 500 ms drop. Fix it in `Roster::track` or `units::create_at` with `set_unit_blocking` for those two kinds.

### Medium

**M1. The gun's recoil kicks it down; Lua kicks it up.**
- Lua `shotgun.lua:110`: `SetUnitVelocity(shotgunID, -dx*20, -dy*20, -dz*20)`.
- Port `weapons.rs:176-183`: `y: direction.y * SHOTGUN_RECOIL`, without the minus. It has been like this since the first port (`24bb6bf`) and isn't in the README.
- The target is below the gun, so `dy < 0`. Every shot sends the gun about 10 elmos per frame downwards instead of up.
- Fix: `-direction.y`.

**M2. Explicit `StartMoving`/`StopMoving` calls keep eating rabbits hopping in place (likely; confirm with a pose probe).**
- *Lua:* the AI never calls the rabbit script's `StartMoving`/`StopMoving`. The engine calls them, and `unit_attributes.lua:201` calls `StopMoving` only when the speed is 0.
- *Port:* `issue_goal` pushes `StartMoving` on every rabbit update (`rabbits/steering.rs:172`). The eating and burrow paths then push `StopMoving` (`rabbits/mod.rs:226,241`). The scripts also declare `START_MOVING|STOP_MOVING` (`cus/script.rs:40-42`), so the engine sends both as well.
- *Mechanism:* `start_moving` signals `SIG_MOVE`, which kills the 1.5 s stop task (`cus/rabbit.rs:122-151`). Updates come every 6–15 frames, so `moving` never becomes false while a rabbit eats (100+ frames) or stands at its burrow. It keeps the hop animation where Lua's goes idle.
- *History:* the calls came in with the CUS port (`da94979`). They look like a leftover from before the engine delivered movement callins to CUS.
- *Fix:* drop the three explicit calls and `Call::rabbit_start_moving`/`rabbit_stop_moving`.

**M3. The visual suite can't catch HUD or end-screen regressions.**
- `GOLDEN_TOLERANCE=10` (RMSE %, `verification/games/hunted.sh:5`). The HUD text covers far less than 10% of the frame (see `fixtures/hunted/goldens/shot_4.png`).
- All four shots fall in the first 4.3 s (`ui/src/widgets/setup.rs:197`): no flare, mine, carrier or end screen. The RmlUi end screen and its buttons are never rendered by any suite.
- Fix: compare a HUD crop at a tight tolerance, and add a shot after a forced game over (the integration gadget can already set `game_over`).

**M4. The integration suite bypasses the loss condition and carrying.**
- `restart_twice` sets `session.game_over = true` directly (`integration.rs:560-564`). `GameEndGadget` (carrots reach 0 once spawning is done) is never exercised.
- Carrying a carrot home (`carrots_stolen`, `ScoreCarrot`), panic drops and dropped-carrot pickup are only covered by the log marker for the first pickup.
- H1 would have been caught by a carrot-count check after the shot and the mine.

### Low

- **L1. Silent failures that matter** (judged, not counted):
  - `units.rs:237-269`: six `let _ =` on the rabbit move-type setters. If they fail, rabbits keep their def speed and turn rate: AI speed, panic and eating slow-down all stop working, with no log. Log once.
  - `cus/lighthouse.rs:264-266,312-313`: `let _ =` on the beam rules params. If they fail, the rules and UI silently fall back to the lighthouse's own position (`senses.rs:159-160`): the beam doesn't scare or reveal where it points.
  - `audio.rs:52,65` check only `is_err()`. The engine returns `Ok(false)` for an unknown sound file (`spring-bar/rts/NativeInterface/api/Sound.cpp:39-43`), so a missing sound is never reported.
- **L2. After a restart the gun and flashlight wait for the mouse.** `restart::reset` resets `Weapons` (target invalid), but the UI's `Input.last_target` is kept. Until the cursor moves more than 1 elmo, `update_gun` returns early and the flashlight scares nothing. Fix: have the UI resend its target when a status with `game_over=0` follows a pending restart.
- **L3. Floating events differ from Lua without mention.**
  - Lua `ui_floating_text.lua:62-90` samples every 15 frames, sizes the text by the change, and shows carrot gains too.
  - The port shows every status change: each kill is its own "Rabbits: -1".
  - After a restart it shows "Rabbits: -N", because the reset status reports 0 rabbits (`ui/src/rml/hud.rs:108-114`).
- **L4. Hard-coded weapon data.** `weapons.rs:14,318` hard-code 10 projectiles and the spray (`2000 * PI / 0xafff`, the engine's `AccuracyToSin`). `defs.rs` already reads `projectile_speed` from the weapon def; read the projectile count and spray from there too.

### Structure and duplication
- File sizes are fine: `integration.rs` 688, `rabbits/mod.rs` 346, `weapons.rs` 339, the rest under 280.
- `ui/src/widgets/camera.rs` is a 39-line wrapper that only forwards `update` to `springcabal_control::camera::CameraPlacement`, which is already a `Widget<G>`. Register it directly.
- **Candidates for the shared crate (cross-game):**
  - `ui/src/rml/mod.rs:123-277`: context/document create, liveness check and rebuild, about 150 lines. Round 2 counted 5 copies of this (engine TODO §4).
  - `state::send_to_rules` plus `rules_message_failed`: every UI still has its own wrapper.
  - The rules and UI `diagnostics.rs` (117 and 151 lines) each re-implement cfg-gated info/debug/warning and `warning_once`, in two different ways (an enum bitset vs. a string set).
- **Unused lighthouse data:** the rules read the lighthouse beam through string rules params that its own script wrote in the same module (`cus/lighthouse.rs` → `senses.rs`). The rules could read the script's state, or compute the angle, and keep the params only for the UI.

### `thread_local!` and global state
- **Rules:** `defs.rs:101` (a `OnceCell` def cache) and `diagnostics.rs:18` (log-once bits).
- **UI:** `defs.rs:11`, and `diagnostics.rs:39,46` (log-once set, visibility-log frame, mouse-sample counter).
- All of these are caches or log throttles, with no game state. They're acceptable, but the log state could move to the resources.
- No `static mut` in game code; the CUS module statics come from the SDK macro.

### Re-entrancy
No new risks. Every create and destroy runs with no resource borrowed, and callins reached from CUS use `ctx.delay`. Script calls made inside `with_rabbit_ctx` are queued and run after the borrows are released. The integration tracker's `RefCell` is held across engine calls, but only its own `game_frame` touches it.

## 4. Strengths
- The `hunted-ai` crate: pure, host-tested and documented against the Lua lines. `waves.rs` reproduces `wave_handler.lua` exactly (the difficulty step, `ceil(x*1.2)`, `MAX_RABBITS`).
- The unit-script port is careful down to Lua quirks: the wiggle-tail turn with no speed, the `math.random(-0.2, 0.2)` offset of 0, the double `math.rad` on the return stroke. Each is commented.
- Resource borrows are disciplined: `Calls` queues script calls, pickups are two-phase, and the restart destroys units through `ctx.delay`.
- The integration suite drives the real message handler and the engine (unit destruction, cylinder queries, a mine on the highest ground). It checks exact frame counts and uses `require_at_least(21)`.
- The README's "Differences from the Lua version" is short and accurate for what it lists. H1, H2, M1 and M2 are missing from it.
