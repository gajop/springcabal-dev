# Area17 review, round 3 (2026-09-25)

Paths are relative to `spring-linux/games/Area17-wasm.sdd/wasm-src/` unless stated otherwise. The
Lua original is `spring-linux/games/Area-17.sdd`. Reviewed at `6a873f5`.

## 1. Grade: B (was B−)

Round 4 fixed every bug and risk from round 2: collision damage, the Rust health copy, the
footprints, the double ability sounds, game-won on respawn and the HUD context leak. The CusHost
move is clean, and the code is well split into small gadgets with borrows released before engine
calls. The grade doesn't go higher because a new pass against the Lua weapon code found a
gameplay bug: the UFO's "silent" weapon slots (3 of 4 gravity beams and 3 of 4 napalm beams) get
none of their special handling. The impulse code also differs from Lua. The e2e suite claims
RmlUi coverage it doesn't have.

## 2. Round-2 findings and their status

**Bugs**
- Collision damage, swapped args plus a flat 20: **fixed** (`487718f`, `b7324e5`). The damage is
  dealt as CRUSHED (-7) with the arguments in the right order.
- Rust copy of the UFO's health; armor could heal: **fixed** (`82d5f88`). `upgrades.rs:171-182`
  scales from the engine's health.
- Hard-coded footprints: **fixed** (`daa60d5`). `defs.rs:128-132` reads `terrainblock_*`, and the
  headless suite checks it.
- Ability sounds twice: **fixed** (`267669e`).
- Undocumented `human.rs` differences: **fixed**. The scream and the parachute are in the README;
  floating starts at once (`21bfa61`); the collision pass is documented.

**Risks**
- `game_over`/`game_won` reset on respawn: **fixed** (`c809faf`) and tested (`integration/ufo_death.rs`).
- RmlUi context leak and retry every frame: **fixed** (`9396c31`). `rml/lifecycle.rs:98-104`
  removes the context, and `setup_failed` stops the retries.
- Visual test borrow across `destroy_reclaimed`: **fixed** (`01f9069`).

**Cleanups**
- Every unit builds every ScriptKind state: **still open**. `cus_scripts/mod.rs:175-186` still
  builds the UFO, human, tank, drone, AA, building and helipad state (about 70 piece lookups) for
  every unit.
- Dead named calls: **fixed** (`943f18a`).
- `PDisUnlocked` rules param read per AimWeapon: **still open** (`cus_scripts/mod.rs:331`). The
  module already writes `UfoControl` straight into the script state; this flag could go the same
  way.
- `AREA17_DRONE` message: **still open** (`drones.rs:64`, consumed at
  `ui/.../gui_ufo_control.rs:57-66`). The UI could do this in its own `unit_created`.
- `upgrades::update` initializing every frame: **fixed** (`042cfeb`).
- Stop pose re-applied every 100 ms: **fixed** (`463e3b2`).
- `fire.retain` inside the 7×7 loop: **fixed** (`9597306`).
- UI mouse work done twice: **still open**. `gui_ufo_control.rs:80-83` (`update`) and `:103-106`
  (`mouse_move`) both call `process_mouse_move`, `update_tech_tooltip` and `update_aim`.
- Shield state set every frame: **still open** (`upgrades.rs:214,224`). It runs even when the
  shield is locked.
- Tech costs copied between the UI and the rules: **still open**.
  `ui/src/rml/tech_data.rs:150-164` duplicates `rules-synced/src/upgrades.rs:331-354`, and both
  copies share the bug in 3.3.
- Hard-coded HUD rectangles: **still open** (`ui/src/pointer.rs:6-12`).

**Tests**
- Fall damage, capture, heal, armor and the collision path: **added** (`90b5a0d`).
- Still untested:
  - the endcube win;
  - civilians (spawn, wander, flee);
  - drones;
  - napalm, black-hole and gravity-beam effects;
  - tech costs.
- The Lua scenario suite still only re-observes what the Rust suite does, and it still ships in
  the archive (`LuaRules/Gadgets/test_area17_scenario.lua`, not in `springignore.txt`): **still open**.

## 3. New findings, most severe first

### 3.1 The silent weapon slots get none of their special handling (bug)
- **Where:**
  - `rules-synced/src/weapons.rs:94-100`: explosion kind.
  - `weapons.rs:150,160`: black hole and gravity beam in `pre_damaged`.
  - `defs.rs:172`: only resolves `ufo_<weapon>`.
- **The setup:** the UFO fires 4 slots per beam weapon: the sound slot plus 3 `…silent` defs
  (`Units/ufo.lua:73-104`). `Weapon::slots()` fires all 4 (`state.rs:76-84`), and Lua's
  `AimWeapon` also allows all 4.
- **What's wrong:** the Rust handlers compare against the one non-silent def id. In Lua,
  `area_damage_defs.lua` and `weapon_impulse.lua` key on the custom params, so they cover the
  silent defs too:
  - `ufo_incendiarybeamlasersilent` has `area_damage`;
  - `ufo_gravitybeamsilent` has `impulse=-30, normaldamage=0` (`ufo.lua:203-330`).
- **Consequence in play:**
  - **Gravity beam, the worst case.** 3 of 4 beams don't pull, and they deal their raw damage
    instead of 0: 2 damage per shot, reload 0.02 s. That is about 180 dps from the three silent
    slots together, against 100-HP civilians and scientists. The "gravity beam" kills the humans
    it should drag, so the player loses the biomass.
  - **Napalm:** only a quarter of the lingering fire patches appear.
- **Why the tests missed it:** they check only the non-silent projectile
  (`integration/weapons.rs:20`).
- **Fix:** resolve every def by custom param, as Lua does. In `defs.rs`, keep a per-weapon-def
  table (area_damage, impulse, normaldamage, falldamageimmunity) and have `weapons.rs` look it up
  by id. Keep the typemap check on the non-silent id only, as in Lua (`typemap_control.lua`).

### 3.2 Impulses differ from `weapon_impulse.lua` (Lua fidelity, undocumented)
- **Where:** `weapons.rs:279-308`.
- **Lift:** for ground units, Lua always adds `y += |magnitude| / (20 * mass)`
  (`weapon_impulse.lua:191-194`). Rust never adds it. For a 100-mass unit in a black hole, that
  is about 0.23 elmo/frame of lift on every 2-frame tick. So black holes throw units up much less
  than in Lua, and the gravity beam loses its lift.
- **Unstick dummy, swapped:** Lua gives the gravity beam `useDummy=true` and the area (black hole)
  impulse `useDummy=false`. Compare the argument order of the calls at `weapon_impulse.lua:318`
  and `weapon_area_damage.lua:100`. Rust applies the ±4 dummy to the black hole only.
- **Fix:** port `AddGadgetImpulse` as written. Add a check that a pulled ground unit leaves the
  ground.

### 3.3 The God Gun upgrade costs a fifth of Lua's price (bug, in both modules)
- **Where:** `upgrades.rs:342-354` and `ui/src/rml/tech_data.rs:159-164`.
- **Lua:** for tier 3, `lvlMultiplier = 15` replaces the level factor, and the tier factor
  `2*tier-1 = 5` still applies. That gives 5 × 15 × 500 = 37,500 biomass
  (`LuaRules/Utilities/tech.lua:333-345`).
- **Rust:** `multiplier = 15` replaces the tier factor instead: 15 × 1 × 500 = 7,500. The UI shows
  the same wrong price.
- **Fix:** match Lua's formula, and move the tech table and cost functions into one crate shared
  by the rules and UI modules (see 3.10).

### 3.4 Civilians of a destroyed building freeze (Lua fidelity)
- **Where:** `civilians.rs:242-244` and `:411-419`.
- **Rust:** when a spawner dies, `unit_destroyed` drops all its wanderers, and
  `refresh_wander_orders` also requires a live, active spawner. The UFO's weapons destroy
  buildings often, and their civilians then stand still for the rest of the game, even with the
  UFO overhead, and never flee.
- **Lua:** `RemoveSpawner` keeps the wanderers. `WandererIdle` then treats a missing spawner as
  active (`unit_civilian_spawner.lua`, WandererIdle/RemoveSpawner).
- **Fix:** keep the wanderers, treat a missing spawner as active, and keep the flee check.
- **Also undocumented here:** Rust re-orders wandering units every 300 frames
  (`WANDER_REORDER_FRAMES`); Lua only re-orders on UnitIdle.

### 3.5 A dropped human walks with the float animation forever (Lua fidelity, visual)
- **Where:** `cus_scripts/human.rs:140-157`.
- **Rust:** `floating` is only cleared in the alien's `parachute_fall` (`human.rs:208`). A
  civilian the beam lets go of (the UFO moves away, or the God Gun starts) keeps `floating=true`.
  Every later `start_moving`/`stop_moving` spawns a controller that picks `float_cycle` first.
- **Lua:** `StartMoving`/`StopMoving` signal the Float thread and play walk/stop.
- **Fix:** give walking priority over a stale float. Either clear `floating` in
  `start_moving`/`stop_moving` for non-aliens, or clear it when the beam stops lifting the unit.

### 3.6 Every capture plays the swoop twice (bug, UI)
- **Where:** `ui/src/widgets/api_sync.rs:132-134` → `audio.rs:15-21`.
- **What happens:** `AREA17_CAPTURE` plays swoop/yay (`api_sync.rs:46-50`). The next status
  message, up to 15 frames later, sees the biomass rise and plays swoop again through
  `play_resource`. So an alien capture plays yay and then a swoop.
- **Lua:** the UI plays no resource sound.
- **Fix:** delete `play_resource`.

### 3.7 The e2e suite claims RmlUi and SDL coverage it doesn't have (test proves less)
- **Direct calls, no RmlUi dispatch:**
  - `ui/src/widgets/dbg_integration.rs:71` calls `commands::toggle_upgrade_panel` directly, and
    `:79` calls `commands::grant_test_resources` directly.
  - Those functions log "Area 17 RmlUi callback: technology toggle" / "… cheat resources"
    (`commands.rs:84,100`).
  - `verification/games/area17.sh:159-162` requires those lines as proof that "the RmlUi …
    callback dispatched".
  - No RmlUi event is ever dispatched. There is no cheat button in `LuaUI/wasm/area17.rml` at all.
- **No SDL events:** the widget calls `send()` itself. "SDL/RmlUi input integration passed"
  (`visual_integration.rs:132`, required at `area17.sh:163`) is only true for the
  `send_lua_rules_msg` hop.
- **"Four abilities activated" can't fail for the God Gun:** the rules test activates it itself at
  frame 45 (`visual_integration.rs:169`). `prepare` also unlocks all tech directly (`:205-213`).
- **Fix:**
  - Drive real clicks with `context_process_mouse_*` on `#tech-toggle`, or rename the log lines.
  - Log "RmlUi callback" only from the bound closures.
  - Drop the God Gun from the input check, or stop activating it in the rules test.

### 3.8 Headless suite: stale claims and engine bypasses (tests)
- **Stale messages:** `integration/weapons.rs:50,79` still say "Lua UFO script" / "Lua model
  script"; the script is Rust CUS now.
- **Direct handler calls:**
  - `:34-36` and all other stages call `ufo_controller::handle_message` directly.
  - The failure text says "unsynced weapon-selection message", but no message is sent.
- **Collision test bypasses the engine:** it calls `record_collision`/`resolve_collisions`
  directly (`integration/gameplay.rs:192-198`). No engine collision ever raises UnitPreDamaged.
  What the test proves is that the CRUSHED damage isn't rewritten, and it says so. That is fine,
  but no test covers the real collision route.
- **Lua suite duplicates and depends on timing:** it hard-codes the Rust suite's frame schedule
  (`test_area17_scenario.lua`: `360 + (stage-1)*80`, 725, 765), so the two suites are coupled
  by timing.

### 3.9 Silent failures on calls that matter (`let _ =`)
These fail quietly where a failure breaks gameplay:
- `ufo_controller.rs:295`: `STEER…apply_from`, the UFO's only movement order.
- `ufo_controller.rs:95`: `set_target(None)`. If ceasefire fails, the UFO keeps firing.
- `upgrades.rs:180-181`: `set_unit_max_health`/`set_health`, the armor upgrade.
- `upgrades.rs:98,248`: `set_unit_cloak`, the cloak ability.
- `upgrades.rs:293`: teleport `set_position`.
- `game_terrain.rs:52-64`: `set_terrain_type_data`. If it fails, buildings become passable.
- `civilians.rs:362,392,422`: FIGHT orders.

The rest, such as effects and tooltips, are fine as they are. Log these, once per kind.

### 3.10 Structure and duplication
- **Dead collision-pairing code:** `fall_damage.rs:78-117, 276-303, 322-334`. As the README
  says, engine unit-unit collisions carry an attacker and pass through unchanged
  (`unit_fall_damage.rs:53,74`). Air collisions don't reach the pass either:
  - only StrafeAir deals collision damage without an attacker;
  - Area17's only aircraft, the UFO and the drones, are `hoverAttack`.
  - So only feature collisions are recorded, and a pair is never matched: `matching_damage`,
    `local_speed_damage`, `certain_damage` and the pair loop never do anything. (If kept, they
    also miss Lua's equal-damage match, `collideWithBuilding`.)
  - Reduce the pass to "2.5 × damage per feature collision" plus the WAIT interrupt.
- **Unit-def data copied into Rust tables:**
  - `abduction.rs:191-210`: capture values and `abduct_mult`, from `customParams` biomass,
    research, metal and abduct_mult.
  - `definitions.rs:298-316`: mid position and radius, from `midposoffset`/`modelradius`.
  - `defs.rs` already reads `terrainblock_*`; read these the same way.
- **`Point3` duplicates `spring::Float3`:** `definitions.rs` is mostly `Point3`↔`Float3`
  conversion wrappers (`unit_position`, `add_impulse`, `set_velocity`, …); `weapons.rs` and
  `fall_damage.rs` convert back and forth. Use `spring::Float3` throughout.
- **Shared code across games:**
  - The UI's `commands::send` wrapper is another copy of the per-game
    `send_lua_rules_msg`-with-logging; this is the springcabal `send_to_rules` gap from round 2.
  - The `Tally`/`Suite` test scaffolding is the same across games, and is fine.
- **Low-severity differences to document or align:**
  - Napalm damage decay: `weapons.rs:117`. With upgrades, Lua's `timeLoss / durationMult` makes
    the damage fall by a fixed amount. Rust scales the loss with the multiplied damage, so fully
    upgraded napalm deals about 20% less in total.
  - UFO brake: `ufo_controller.rs:13,277`. Rust brakes above 2 elmo/frame toward a goal 8 ahead;
    Lua brakes above 6, toward a goal 20 ahead.
  - Black hole: `weapons.rs:196` never pulls the UFO; Lua's does.

### 3.11 Global state
The only `thread_local!` left is `defs.rs:190-196` (`DEFS: OnceCell<Defs>`), a resolve-once
cache. It is acceptable. It could become a field of `Global`, loaded in `GameLoadGadget::init`,
which would also make the defs order-independent of the first call.

## 4. Strengths
- **State ownership:**
  - Each gadget owns its state in a `RefCell` or `Resource`.
  - `Global` is split into independently borrowable resources.
  - Every engine call that can raise a callin (`create_unit`, `destroy_reclaimed`, damage,
    orders) is made with the borrows released, and the code comments why
    (`civilians.rs:332`, `abduction.rs:83-84`, `ufo_controller.rs:67-68,145-146`).
- **Unit scripts:**
  - The script host is `CusHost`, with `with_cus_module_or_defer` for attach and named calls.
  - `set_ufo_control` writes the UFO's aim, weapon and beam straight into the script state.
- **Lua-matching details:** the fall-damage immunity, the ground-bounce math, the respawn and
  alien sequence, and the cone upgrade.
- **Headless suite:** it checks engine-side results (projectiles, crater depth, map damage,
  health ratios, the respawn) and requires a minimum check count.
- **Static suite:** the modules must match a fresh build of the source.
