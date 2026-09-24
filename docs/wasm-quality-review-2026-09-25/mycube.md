# MyCube, review round 3 (2026-09-25)

Paths are relative to `spring-linux/games/MyCube-wasm.sdd/wasm-src/` unless stated otherwise.
Lua paths are relative to `spring-linux/games/MyCube.sdd/`. Game HEAD `8063a04`.

## 1. Grade: A− (was B+)

Every bug and risk from round 2 is fixed or gone. Restart, loss, drowning, warming and combat are
now tested through the engine. The CusHost move removed the hand-written host and its Activate
workaround. I checked the rules against the Lua gadgets line by line (health, eskimos, drowning,
drill, storyteller, trade/modes, game_end, parachutes) and found no gameplay bug. What keeps it
from an A: the visual suite proves little, the camera differs from Lua without a README entry,
and a few small things are duplicated or can fail silently.

## 2. Round 2 findings and their status

Bugs
- `game_end.rs` absolute `FIRST_CHECK_FRAME`, so a restart ended in a loss: **fixed**. It now
  uses `GRACE_FRAMES` after `story.start_frame` (`gadgets/game_end.rs:17,27`), and the test checks
  it (`integration.rs:423-438`).
- Survival time included earlier rounds: **fixed**. `Story::survival_frames` counts from the
  round's `start_frame` (`state.rs:98-100`). The test checks for exactly `RESTART_CONDEMN + 1`.

Risks
- Failed height-map job retried forever, silently: **fixed**. Commit `97860a6` digs each crater at
  once and logs a failed `set_height_map_func` (`terrain.rs:18-23`).
- A failed health read became 0 and killed the unit without a log line: **fixed**.
  `health::pool` logs and returns `None`, and callers leave the unit alone.
- Manual `activate` could run twice: **obsolete**. CusHost and the engine deliver Create and
  Activate once (`7c53601`).
- Uncapped placement loop in `story.rs`: **fixed**. It stops after 1000 tries, logs, and the
  README lists the change.
- The integration tracker held four resources, so real damage would panic: **fixed**. Checks
  collect ids first and hold no borrow across `add_unit_damage`, `set_unit_position` or
  `destroy` (`integration.rs:223-247`, `419-421`).

Cleanups
- `SetupGadget` only turned on LOS: **fixed** (`GlobalLosGadget`).
- GameEnd and frame rates duplicated in rules and UI: **fixed** (`common/round.rs`).
- UI hard-coded max health: **fixed** (`ui/src/defs.rs:285-303` reads `customParams.health`).
- `GAME_SPEED` 30 vs 33 confusion: **fixed**. `LUA_FRAMES_PER_SECOND` is documented. The ship's
  sinking-sound lock correctly uses the engine's `GAME_SPEED`.
- Sell mode did 676 height queries per mouse move: **fixed** (at most 10 per second, and the
  README lists it).
- Healthbars sorted all units on every draw: **fixed** (the list is refreshed once per frame).
- Status formatted every frame: **fixed** (`SendOnChange`).
- Root `mycube-*.cwasm` files: **still open**. `mycube-rules.cwasm` and `mycube-ui.cwasm` are
  still in the dev repo root (a repo-hygiene item).

Tests
- Combat check called `unit_pre_damaged` directly: **fixed**. It goes through `add_unit_damage`,
  checks the pool drop, and checks that engine health is unchanged.
- Drill check read a flag set before the order: **fixed**. It reads the engine command queue
  (`integration.rs:378-400`).
- 2 of the 5 visual shots were never compared: **fixed**. All 5 are compared (`mycube.sh:81`), but
  see finding 2.
- Story timings fast-forwarded: **still open, by design** (`integration.rs:148-150`). Nothing
  checks the real waits.
- Untested drowning, craters, warming, freeze/starve death, loss path, restart: **partly**.
  Drowning, warming, loss and restart are tested. Drill craters, freeze/starve death and the
  drowning animation are not.

## 3. New findings (most severe first)

1. **Undocumented Lua difference: WASM sets an authored camera that Lua never applies.**
   `ui/src/widgets/gui_camera.rs:8-9` places the camera from `camera_control.lua`'s table.
   In Lua, the only `Spring.SetCameraState(s, 0)` is commented out (`LuaUI/Widgets/camera_control.lua:43`),
   so the Lua game keeps the engine's default start camera.
   - Consequence: the framing differs from the original. In the goldens the village sits cut off
     at the top edge and about 80% of the frame is sea.
   - Fix: pick one. Either drop the placement and match Lua, or keep it, list it under
     "Differences from the Lua version", and re-aim it at the village (e.g. `POSITION` at the map
     centre, where `find_position` puts the village).

2. **The visual suite proves little.**
   - `ui/src/widgets/dbg_e2e.rs:4` shoots at frames 25–530 (the first 16 s). That is before any
     pirate lands and before any drill ship, combat, trade or crater. The 5 goldens differ only in
     the intro text and the heat meter.
   - Measured run-to-run noise is 4.2–4.4% RMSE (mostly animated water), and the tolerance is 9%
     (`verification/games/mycube.sh:5`). The village covers roughly 15% of the frame, so a
     regression confined to it could pass, e.g. missing iglu decorations, a wrong burner piece,
     or healthbars off. I did not measure this.
   - Fix:
     - Add later shots (a pirate on the ice around frame ~700, drill ships after the frame-1100
       wave) or a test-only trade click.
     - Compare the village with a crop: `vf_golden` already takes a crop argument.
     - Or mask the water.

3. **Scenery check bypasses the engine** (`rules-synced/src/integration.rs:173-181`).
   - It calls `crate::untargetable::allow_command` directly. The MOVE half
     (`allow_command(MOVE, &[100,0,100])`) can't fail, because three params never match the
     single-target pattern.
   - So it doesn't prove the gadget is registered or that the engine consults `AllowCommand`.
     That matters here, since the AllowCommand export is opt-in.
   - Fix: give a real `CMD.ATTACK` on the burner to an Eskimo with `give_order_to_unit`. Check
     that the call is rejected, or that the command queue stays empty.

4. **Missing health pool is logged on every frame, per unit.**
   - `health::pool` (`rules-synced/src/health.rs:13-19`) warns on every failed read. It is called
     every frame for every Eskimo (`eskimos.rs:51`) and for every unit in water (`drowning.rs:25`).
   - One unit without a pool writes about 30 warnings a second, which buries other log lines.
   - Fix: `log_once!` keyed by unit, or log at the caller once per unit.

5. **Silent failures that matter only a little.**
   - `terrain.rs:52` `let _ = spring::add_height_map(...)` is inside the transaction. A failed
     cell leaves a partial crater while `decrease_terrain` reports `Ok(true)`. Count failures and
     include them in the existing warning.
   - `spawning.rs:51-63` `let _ =` on `set_unit_neutral`/`set_unit_blocking` for scenery. A
     failure makes the iglus attackable or non-blocking. Log it, as the rest of spawning does.
   - `units.rs:6-7` (food/heat rules params) and the scripts' mid/radius setters are cosmetic;
     leave them.

6. **Crater geometry is off by 1–2 elmos from Lua** (`terrain.rs:11-16`, `35-36`).
   - Lua rounds `size` to the grid before halving: `size = RoundInt(size, 8)`, so 250 becomes 248
     with `sh = 124`, and 300 becomes 296 with `sh = 148` (`unit_drill.lua:65-67`).
   - Rust halves the unrounded size (125 and 150) but iterates the rounded grid. The trade crater
     is therefore 2 elmos wider and off-centre by 2 elmos within its 296-elmo grid.
   - Harmless in play. Fix it for fidelity with `let size = size - size % SQUARE_SIZE;` before
     computing `half`.

7. **Duplication.**
   - Within the game:
     - `rules-synced/src/defs.rs:98-112` and `ui/src/defs.rs:23-26,285-292` each parse
       `customParams.health` with their own `DEFAULT_HEALTH` and their own `thread_local!` cache.
       Move the parser and constant to `common/`, like `ice.rs` and `round.rs`.
     - The `MYCUBE_STATUS` layout is written in `gadgets/status.rs:18-27` and parsed in
       `ui/src/widgets/api_sync.rs:454-470`. A shared `common/status.rs` with `encode`/`parse`
       would keep them in step.
   - Across games: `units::destroy`/`destroy_later` ("destroy unless already dead, after the
     callin") exists in MyCube, Parts Needed and Hunted (`rules-synced/src/units.rs` in each).
     Candidate for the `springcabal` crate.

8. **Small leftovers.**
   - `rules-synced/Cargo.toml` declares an `e2e` feature that no rules code uses.
   - The comment in `drowning.rs:13-16` ("the module is free here") is right, but
     `with_cus_module` returning `None` would silently skip the flounder animation. That's fine to
     leave; a `debug_assert!` would document it.

9. **Global state.** Only the two `thread_local!` `OnceCell` def caches remain (rules and UI
   `defs.rs`). They are read-only after init, which is acceptable. Folding them into finding 7's
   shared module would leave one.

Re-entrancy: none found. Every gadget either releases its borrows before engine calls that can
raise callins, or defers them with `ctx.delay`:
- orders: `gadgets/drills.rs:57-59`;
- spawns: `storyteller.rs:58-64`;
- destroys: `units::destroy_later`.

The borrows that remain across engine calls (height-map edits, rules params, positions) are not
held across any call that raises a synced callin.

## 4. Strengths worth keeping

- Gadgets that own their state, with small files; only the animation data table exceeds 500 lines.
- Clear comments that cite the Lua source they port. The rules match `unit_eskimos.lua`,
  `game_health.lua`, `unit_drill.lua` and `storyteller.lua` closely, including subtle state
  (eating/warm hysteresis, loss overriding victory).
- The README's list of differences is honest and complete, apart from the camera.
- The integration suite drives trades and the restart through the UI's real message channel. It
  checks results in the engine (command queue, engine health, terrain), requires 29 checks and a
  clean exit, and forbids traps and panics.
