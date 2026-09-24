# WASM ports code review (2026-09-23)

This is a static review of the seven Rust/WASM ports under `spring-linux/games/*-wasm.sdd/wasm-src`. It is meant to drive follow-up work. Nothing was changed in the games.

- The verified starting state is in [`BASELINE.md`](../BASELINE.md).
- Items that belong to the engine or its crates are in `spring-bar/WASM_GAME_API_TODO_2026-09-24.md`, next to this repository (`../../spring-bar/` from here). It was `WASM_GAME_API_TODO_2026-09-23.md` when this review was written.

## Decisions (from review feedback)

| Topic | Decision |
|---|---|
| Hiding the default engine UI | Engine or `spring-addons` job. Filed in the spring-bar TODO (§1). |
| `CMD_*` ids, `GetGameFrame` split, RmlUi setup, Core-CUS attach/call queues | Engine or crate API gaps. Filed in the spring-bar TODO (§2–§5). |
| Restart | Leave per game. These are LD games; real games won't restart like this. |
| Healthbars | Not shared; they're trivial and differ in style. Delete dead copies. |
| Logging | Probably fine as it is. |
| Keyframe animation data | Fine. The Lua originals have the same tables (see below). |
| RNG | Replace every synced hand-rolled RNG with `spring::random`. |
| Dead code | Delete it: TTLD `healthbars/` and the list below. |
| Large files | Split the files that are mostly logic, reasonably. Keyframe data stays. |
| Port-history and stale comments | Purge them. |
| Shared SpringCabal crate | Allowed: a separate repo here, not pushed yet, that all SpringCabal games can depend on. Keep it small; anything useful beyond LD games goes to the engine. |
| Def-id caching, state ownership refactor | Do both, verified against `BASELINE.md`. |

## Per-game summary

| Game | LOC | State model | Main problems |
|---|---|---|---|
| Gravitas | 22.7k (11.9k of it data) | `thread_local WORLD` (19 fields) and an empty addon `Global`, plus `orchestration.rs` | God-state; `with_world` skips silently on a borrow conflict; hand-rolled lifecycle fan-out; `DEF_PARAMS` has drifted from the real customParams |
| TTLD | 10.2k | Same as Gravitas: `WORLD`, plus a 41-field `UiState` | Same as Gravitas; dead `healthbars/`; per-frame projectile-light lookups; O(n²) enlarger sweep |
| Flove | 8.1k | 12 `Resource`s, but logic sits in the wrong gadgets; the UI uses a `static mut` | UB from the `static mut`; `createdFrame` never set; 9-argument manager functions |
| Hunted | 6.0k | `Resource` Global, plus a 42-field `UI_STATE` | Quadratic rabbit AI (2048-slot linear scans); per-unit visibility work every frame; hide-UI list duplicated |
| Area17 | 10.0k | 10 `Resource`s, plus module thread_locals | 28 by-name def lookups (including per-frame abduction); per-frame rules-param spam; cheat button ships |
| Parts Needed | 8.8k | `Resource` Global, plus a Reaper effect queue | Hard-coded copy of the launch script; stringly-typed body parts |
| MyCube | 5.7k | `Resource` Global | Cleanest structure; a likely gameplay bug (Eskimo damage) |

## Problems shared across games

### 1. The gadget/widget layer is thin

All seven games use `spring_addons::{Gadget, Widget}`, but almost every gadget is an empty struct that forwards to free functions working on shared state.

**Ordering is enforced implicitly:**
- a `frame_consumed` flag set by `SetupGadget` (Hunted, Gravitas, TTLD);
- a Reaper gadget that must be registered last (MyCube, Parts Needed);
- one gadget reading data that another refilled in the same frame (Area17 `units.floating`).

**Unit callins are fanned out by hand** from a `LifecycleGadget` (Gravitas, TTLD, and Area17 partly) instead of each gadget implementing `unit_created` / `unit_destroyed`.

**Names don't match responsibilities:**
- Flove `MushroomsGadget` runs tree growth, `FlowersGadget` runs poison, and `UpgradesGadget` runs flower fields.
- Gravitas `ElectrafiGadget` runs fire and respawns; `JumpGadget` runs the player.
- TTLD `TownGadget` steers orks; `GuiInputWidget` places lights.

**UI god-structs:** Hunted `UI_STATE` (42 fields), TTLD `UiState` (41), Gravitas `UiState` (33), Flove `UiState` (28, `static mut`).

**Target:** each gadget owns its state, or its own `Resource`. Setup moves into `init`. Gadgets implement their own callins, and the addon `Global` holds only data that is really shared.

### 2. Re-entrancy

`spring-addons` now dispatches nested callins **immediately**, and `ctx.delay` is opt-in. A `Resource` borrow conflict panics (`runtime.rs` `borrow_conflict`). A borrow held across a callout that raises a callin is therefore a potential crash. Gravitas and TTLD use a hand-rolled `try_borrow` that skips the update instead, with nothing logged at the call site because callers write `let _ =`.

Known places a borrow is held across a callout:
- **Hunted:** `update_mines`, `fire_shotgun`, `update_eating_rabbit` (create/destroy/projectile).
- **MyCube:** `drills` → `give_order_to_unit`, which can raise `AllowCommand`.
- **Parts Needed:** `update_triggers` → `CMD_ONOFF` order.
- **Area17:** `EXPLOSIONS` borrowed during `add_unit_damage`.
- **Gravitas:** `player.update` and `jumps.start` → orders and `move_ctrl`.
- **TTLD:** `transfer_unit` inside a CUS callin.
- **Flove:** `rng` held mutably across GameFrame gadgets; `LoveGadget::unit_pre_damaged` also takes it.

Other issues:
- **Stale comments** assume the old queued model (MyCube `reaper.rs:31`, Hunted `weapons.rs:512`).
- **Unsound code:** Flove `ui/src/state.rs` uses a `static mut` with `&mut` handed out. Gravitas `ui/src/fire/distortion.rs` and Flove `rules-unsynced/src/outline.rs` use `unsafe impl Sync`.
- **`let _ =` swallowing engine errors**, count per game: Hunted 123, MyCube 115, Area17 203, Flove 215, Gravitas 270, Parts Needed 277, TTLD 442.

### 3. Unit and weapon defs looked up by name at runtime

Every game calls `get_unit_def_id_by_name` at use time. Counts: Area17 28, Parts Needed 39, TTLD 21, MyCube 20, Flove 14 (it has a `DefRegistry`, but most code bypasses it), Hunted 11, Gravitas 6 (plus 22 `units::def_id` calls).

This happens in `UnitPreDamaged`, `UnitCreated`, draw callins and per-frame loops. `script_kind_for_def` alone makes up to 31 lookups per unit. Custom params are read by string per unit per frame (Gravitas electrafi/fire, TTLD projectile lights, Parts Needed sprites).

**Fix per game:** a `Defs` struct resolved once at init, with typed ids and the per-def flags and custom params needed, plus a `def → ScriptKind` table.

### 4. Rules↔UI sync is string-based and duplicated

- Status goes out as a `GAME_STATUS|k=v|…` string, parsed by key. Area17, MyCube, Flove and TTLD also publish the same values as rules params, so there are two channels.
- Input goes out as `cmd|x|z` strings, often sent every frame even when nothing changed (Area17 `aimWeapon`, Gravitas input, TTLD `hold_mouse`).

Pick one channel per direction and send only on change.

### 5. RNG

Synced code in the games has its own RNGs:
- xorshift: Area17 `civilians.rs` and `drones.rs`
- PCG: Flove `random.rs`
- LCG: MyCube `story.rs` and `unit_scripts/common.rs`; TTLD `random.rs`; Gravitas `orchestration.rs`
- hash: Hunted, 4 copies

**Decision:** replace them all with `spring::random` (synced, spring-bar `4fc79bdbb9`). This matches Lua's `math.random` on `gsRNG`, and `FixedRNGSeed` then applies. It also allows restoring dropped randomness:
- Gravitas' projector stun spasm;
- MyCube's drill 50% mining gate (`let _ = state.random;`).

UI and unsynced RNGs (particles, lights, audio) stay local for now, because there is no unsynced engine RNG (spring-bar TODO §6).

**Expect behaviour changes:** random streams change, so headless assertion counts that depend on randomness and the scenario goldens may move. Re-baseline each game on its own.

### 6. Duplicated infrastructure: where each piece goes

| Concern | Status | Destination |
|---|---|---|
| Hide default UI | 7 lists that have drifted apart; Hunted uses the broken `("console","0")` form | Engine / `spring-addons` (TODO §1) |
| `CMD_*` constants | Raw ids everywhere; Area17 `ORDER_WAIT` is really `IDLEMODE` | Engine (TODO §2) |
| Game-frame decode | About 15 copies of `(high16 << 16) \| low16` | Engine (TODO §3) |
| RmlUi setup | 5 copies, Gravitas/TTLD 82% identical | Engine / crate, later (TODO §4) |
| Unit-script attach/call queues | 7 attach queues, 4 call-queue variants | Engine / crate (TODO §5); explained below |
| Unit-query buffer-retry helpers | 2–3 copies in several games | `spring` SDK (TODO §6) |
| Synced RNG | See §5 | `spring::random` |
| Restart | 4 mechanisms | Stays per game |
| Healthbars | Gravitas and TTLD copies (`geometry.rs` 100% identical); TTLD's is dead | Stays per game; delete TTLD's |
| Logging | 7 `diagnostics.rs`; `spring_addons::log` unused | Probably fine as is |
| Fire particles | Gravitas ~1.3k LOC vs TTLD ~270, 35% similar | See "Particles" below |
| Music loop widget (6), e2e screenshot widget (4), camera follow smoothing (4), shader/uniform boilerplate | Small copies | Candidates for the shared SpringCabal crate; low priority |

### 7. Hygiene

- **Large logic files to split:**
  - Area17 `cus_scripts.rs` (1616; split per script kind, and move `walk_frame` data to its own file)
  - Parts Needed `unit_scripts.rs` (2457; about 450 lines of logic, the rest keyframes)
  - TTLD `unit_scripts/mod.rs` (1351)
  - Hunted `cus_scripts.rs` (1099), `rabbits.rs` (848), `state.rs` (641), `ui/rml.rs` (601)
  - MyCube `unit_scripts/mod.rs` (903)
  - Area17 `gui_ufo_control.rs` (514)
  - Parts Needed `gfx_eyes_effect.rs` (765)
  - Flove `outline.rs` (686), `mushrooms.rs` (578, including a 190-line wave table)
  - Gravitas `unit_scripts/mod.rs` (598)
  - Also split the 100+ line functions listed in the per-game notes.
- **Comments to purge:** port-history narration ("the old WASM port…", "the first pass…") and stale comments:
  - Gravitas `orchestration.rs:1-3`
  - TTLD `enlarger.rs:16-17`, `spells.rs:271-273`
  - Flove `outline.rs:314`
  - Hunted `cus_scripts.rs:3-6`
  - READMEs that say Lua unit scripts are still used (Hunted, Parts Needed)
- **Magic numbers:** command ids (engine TODO), raw key codes, and repeated map constants (Hunted `6143.0`, TTLD town centre).
- **Dead code and artifacts:**
  - TTLD `ui/src/healthbars/` (4 files) and `widgets/gfx_healthbars.rs`: not in the module tree.
  - TTLD unused `headless-integration` feature in `ui/Cargo.toml`.
  - Area17 `weapons::pre_damaged_without_upgrade`, the UI `DiagnosticsState`, and `Units.units`.
  - Hunted `ScriptKind::Trap`, the `"SpawnRabbits"` no-op, `play_dig_sound`, and the stale `LuaRules/wasm/hunted-unsynced.wasm`.
  - Flove `Session.pending_upgrades` (so `UpgradesGadget:21-47` does nothing), and the `view_width`/`view_height`/`DefRegistry.initialized`/`OutlineState.current_frame` fields.
  - Gravitas unused `UiState` fields (`view_width`, `view_height`, `document`), and `probe::report(world)`.
  - MyCube `ShipState.minetime`/`random` (see §5), and committed `.cwasm` files in `wasm-src/`. This repo also has `mycube-*.cwasm` and `partsneeded-*.cwasm` at its root.
  - Parts Needed `LuaUI/wasm/partsneeded.rml`/`.rcss` (unused).
- **Test code changing gameplay:** Parts Needed `MOVE_STALE_FRAMES`, and `EndgameGadget` compiled out under `unit-script-probe`.
- **Shipped cheat:** Area17 `cheatResources` is unguarded and has a HUD button (`LuaUI/wasm/area17.rml:14`).

## Likely bugs

| Game | Bug | Verified |
|---|---|---|
| MyCube | Eskimo combat damage is overwritten: `health.rs:44` lowers the rules param, then `eskimos.rs:84` writes the stored copy back every 5 frames. The integration test compensates (`integration.rs:152`). | reviewer |
| Flove | `createdFrame` is never set (Lua: `grove_spawner.lua:109`), so tree grow-in is always complete. | ✓ |
| Flove | Restart destroys units without `reclaimed`, so the cluster mushroom's `Killed` spawns 10 children that survive into the new round. | plausible |
| Flove | The UI `static mut` state is UB if ever nested. | ✓ |
| Gravitas | The healthbar blink never fires, because `ui.seconds` is never written. | reviewer |
| Gravitas | `selection::suppress` compares only the unit count, so a respawned unit can be selectable. | reviewer |
| Gravitas | `DEF_PARAMS` gives `crate` a `radius=30` that `units/immobile.lua` doesn't have. | reviewer |
| Hunted | `queue_named_call` always returns `true`, so the fallbacks at `rabbits.rs:326` and `:427` never run. | reviewer |
| Hunted | The first hide-UI list toggles each command and then sends `0` as a separate command. | ✓ |
| MyCube | The CUS attach and drowning queues re-queue forever when the piece map fails. Eskimo timers run at 29/30 of the Lua rate (`frame % 30` skip). | reviewer |
| Area17 | `ORDER_WAIT = 145` is `CMD.IDLEMODE`. `aimWeapon` is sent every draw frame. | reviewer |
| Parts Needed | `RESTART_SCRIPT` copies `launch/games/partsneeded/wasm.txt`, which breaks the `launch/` rule. | ✓ |

## Explanations

### Queueing unit-script calls

In a WASM port, the rules (gadgets) and the unit scripts (Core-CUS) are compiled into the same module. But the CUS module object lives in a `static mut` created by `spring::export_core_cus!`, which gadget code can't reach. That leaves two problems:

1. **Attach.** `CoreCusModule` has no attach callin, so the module never hears that a unit was created. Each game's lifecycle gadget pushes `(unit, def)` into a thread-local `PENDING_UNITS` in `UnitCreated`. The module drains it on the next `cus_tick`, works out the script kind (usually through many by-name def lookups) and creates the instance.
2. **Calls from rules code.** Lua rules would call `Spring.CallCOBScript` / `env.Foo()`. The Rust equivalent, `spring::typed::call_unit_script`, goes out to the engine and back into this module, which is still inside the gadget callin. The engine rejects that (ApiError 1), and `let _ =` hid it. Parts Needed's piece masks, Gravitas' jumps and TTLD's spell animations were all silently dropped. So each game pushes `(unit, "FunctionName", args)` into a second thread-local queue and applies it on the next `cus_tick`.

The four call-queue variants are TTLD `queue_call` (with args), Gravitas `queue_call` (no args), Hunted/Area17 `queue_named_call`, and Parts Needed/MyCube purpose-specific queues. They all exist because of these two API gaps. The proper fix is an attach callin plus direct access to the CUS module from the same module (spring-bar TODO §5). Until then, one shared helper would at least make the games consistent. It would also stop functions like Hunted's `queue_named_call` returning a misleading `true`.

### "Game-frame decode"

`spring::game::get_game_frame(0)` returns the frame as two `u32` halves (`low16`, `high16`), because the native API (`NativeInterface/api/Game.cpp:109`) splits it, and it takes a dummy `unused` argument. Every game rebuilds the number with `(v.high16 << 16) | v.low16`, about 15 times across the seven games. It should just return the frame (spring-bar TODO §3).

### Keyframe animation data

The Lua originals ship the same keyframe tables, exported from Blender, so the Rust ports having them is faithful rather than odd:

| Game | Lua keyframe data | Rust port |
|---|---|---|
| Gravitas | `scripts/animations/gravit_*.lua` (8 files, 873 lines) | `gravit_animation_data.rs`, 5013 lines |
| Parts Needed | `Scripts/animations/wisp_*.lua` (726 lines) | about 1460 lines in `unit_scripts.rs` |
| MyCube | `scripts/animations/*.lua` (8 files, 1143 lines) | `eskimo_animations.rs`, 1037 lines (`include!`) |
| Area17 | `Scripts/animations/human_*.lua` (499 lines) | `walk_frame` / `float_cycle` in `cus_scripts.rs` |
| Flove | none; its gaits are procedural (`Scripts/headers/bipedal_*.lua`) | `unit_scripts/mushroom.rs` hand-unrolls those `Turn` calls, which is logic, not data |
| Hunted, TTLD | no keyframe tables | none |

The Rust versions are up to 6× longer only because each command is a multi-line struct literal. That's cosmetic: one-line tuples, or generating the tables from the Lua files in `build.rs`, would fix it. Gravitas `level.rs` (6890 lines) is also data (544 spawns from the scenario) and could be generated the same way.

### Particles (fire)

All seven Lua games ship **LUPS**, the Lua particle system from ZK. Gravitas uses it heavily: units on fire, napalm, flame jitter, shockwaves, nano spray, projectiles and electrafi. Hunted and TTLD use `gfx_lups_units_on_fire`, and the others load only the manager.

The Rust fire modules are ports of two LUPS particle classes:
- Gravitas `ui/src/fire/`: `SimpleParticles2` plus `distortionFBO`, with an `Effect` table of about 25 fields;
- TTLD: a cut-down copy of the same idea.

The reusable part is not "fire". It is the LUPS-style runtime:
- an emitter/particle update loop;
- a colormap and size/rotation curve;
- billboard rendering;
- an optional heat-distortion post pass;
- data-driven `Effect` definitions.

"Fire" is just one effect definition, and each game would supply its own. That runtime is what Area17, Hunted and TTLD could share with Gravitas. A ZK-style game might use it too. BAR has mostly moved away from LUPS to GL4 widgets, and a ship game would probably want its own. Suggested path:
1. Extract Gravitas `fire/` into a generic `particles` module (runtime plus effect data) inside the shared SpringCabal crate.
2. Move TTLD onto it.
3. Decide about engine-level placement only if a non-SpringCabal game wants it.

## Suggested order of work

Each step is verified against `BASELINE.md`: headless assertion counts must match exactly, and visual suites must pass or have intended golden updates. Commit per game.

1. **Hygiene, no behaviour change:** delete dead code (TTLD `healthbars/` first), purge stale and history comments, name magic numbers, remove committed `.cwasm` files.
2. **Bug fixes** from the table above, each with its own check.
3. **Def-id caching per game** (§3).
4. **Split large logic files** (§7).
5. **State ownership refactor:** Gravitas and TTLD first (remove `WORLD`, `orchestration.rs`, `frame_consumed`, the lifecycle fan-out), then the UI god-structs, then the other games' shim gadgets.
6. **Synced RNG → `spring::random`** (§5). Re-baseline the affected assertions and goldens deliberately.
7. **Shared SpringCabal crate** (new local repo, not pushed): start with the particle runtime, then any small widgets that are really shared.
8. **Engine TODO items** in spring-bar; afterwards, remove the per-game workarounds (hide-UI lists, frame decode, CUS queues, CMD ids, RmlUi boilerplate).
