# Parts Needed (`PartsNeeded-wasm.sdd`), review round 3

Paths are relative to `spring-linux/games/PartsNeeded-wasm.sdd/wasm-src/` unless stated.
Game HEAD: `421ecbc`.

## 1. Grade: B+ (was B)

Both bugs from the last review are fixed, and so are most of its fidelity gaps: plate ONOFF,
latching like `unit_plate.lua`, the 40-frame cage release, the stop glide, the UI hello and
restart gating. Round 5 moved the game cleanly onto `CusHost`. What keeps it from an A-
is the tests. Two of the four compared scenario shots are timing-dependent and pass while
showing the wrong room. The lever-combination check is tested against its own table. Most
"Lua message" checks call rules functions directly.

## 2. Previous findings, status now

**Bugs**
- Plates never got their own ONOFF: **fixed**. `triggers.rs:61-73,102-104` orders ONOFF 1 on the plate. The check at `integration/checks.rs:402` sees the Button sink.
- `form_frame` was updated without eyes, so the UI prediction stuck: **fixed**. `input.rs:39-43` returns before touching the cooldown, and `api_sync.rs` times the prediction out in `update`.

**Risks**
- Cages linked from a lever and a plate flipped every 5 frames: **fixed**. Everything but levers latches (`triggers.rs:44-49`, `switch_on`), as in Lua, where ONOFF 0 is commented out.
- Undocumented differences:
  - gate 20 re-closing: **fixed** (latched);
  - instant cage resolve: **fixed** (`cages::OPEN_FRAMES`);
  - no stop glide: **fixed** (`wisp.rs` `GLIDE`);
  - the trail: **documented** in the README.
- Restart accepted about 160 frames before the prompt showed: **fixed** (`end_screen_shown()` in `gui_wisp_control.rs:71,150`).
- A LuaUI reload lost the status: **fixed**. `Command::Hello` goes out from `api_sync.rs:init`, and `StatusGadget` resets `SendOnChange`.

**Cleanups**
- `level/mod.rs` looked defs up by name: **fixed**. `Defs::by_name` now matches cached ids.
- `wisp/idle.rs` unrolled `turn()` calls: **open**. There are still 82 calls, and the file keeps `#[allow(clippy::needless_borrow)]`.
- An enum repeats the `WispPieces` fields: **open** (`unit_scripts/wisp/mod.rs:139-185`).
- `Rc<RefCell>` around a `Copy` struct: **open** (`unit_scripts/props.rs:31`). `WispAnimationState.pieces` also copies `PartsUnitScript.pieces`.
- The lever reach was defined three times: **fixed** (`shared::LEVER_REACH`).
- The Ctrl+Q engine bind duplicated the crate: **fixed**.
- Game-over NPC scans and sprite rules-param reads on every update: **partly fixed**.
  - The scan now runs every 30 ticks, but still on every update during the ending (`gfx_eyes_effect/npcs.rs:23-27`).
  - `death_amount` still reads 3 rules params per wisp per draw.
- The trail stepped per draw frame: **fixed** (`552df7d`).

**Tests**
- "Walking" passed on the bob alone: **fixed**. The legs and arms are now measured relative to Body.
- "Game-over blocks form switch" never sent a switch: **fixed** (frame 130).
- A table tested against itself: **still open**. See N3.
- The ending shots were never compared: **partly fixed**.
  - `ending_final` is compared, but it is mostly a white fade, so it's weak (see N2).
  - `ending start` is still uncompared, on purpose (RNG).
- No check for the plate script, the kill plate, the UI→rules path or restart:
  - the plate script and the kill plate are **fixed**;
  - the UI→rules path is **partly fixed** (only `Hello` travels the real path);
  - restart is **open**.

## 3. New findings (most severe first)

### N1. Visual shots 3 and 4 depend on wall-clock timing and now show the wrong room, yet pass (tests)

`ui/src/widgets/dbg_e2e.rs:18-21`, `ui/src/widgets/camera_follow.rs:20-23`, `verification/games/partsneeded.sh:6,94`.

Confirmed. The goldens (recorded at `ffbee41`) show two different places:
- shot 3: the start-room crates;
- shot 4: the plate corridor.

The last run (`verification/out/partsneeded-visual/goldens/`) shows other rooms:
- shot 3: the table and pipe room;
- shot 4: the crate room that the golden has as shot 3.

In other words, the camera pan is one shot "behind" the goldens. Measured RMSE against the goldens:

| shot | RMSE vs golden | result at the 8% limit |
|---|---|---|
| shot 1 | 0.5% | pass |
| shot 2 | 1.7% | pass |
| shot 3 | 5.3% | pass |
| shot 4 | 7.1% | pass |

An all-black frame is only 10.2% (shot 3) and 13.0% (shot 4) off these goldens, so in this dark scene the 8% limit catches little beyond a black screen.

Cause:
- The follow camera smooths with `Smoothing::Exponential { tau: 0.12 }` over the widget's wall-clock `dt` (`springcabal-control/src/camera.rs:314`).
- The suite runs at `minspeed=100;maxspeed=100`, so sim frames are decoupled from real time.
- The rules teleport the wisp to another room at frame 82 (`gadgets/integration.rs` frame 82).

As a result, the camera's position at "frame 86" and "frame 100" depends only on how long the previous screenshot took to save. The log shows:
- shot 2 at frame 84 (t=4.713 s);
- shot 3 at frame 86, 43 ms later;
- the shot-2 save finishing at t=5.26;
- shot 4 landing on frame 101, not 100.

The code comment at `dbg_e2e.rs:18-20` admits this ("depends on how long the earlier captures took"), but the suite still compares both shots as goldens.

Consequence: two of the four scenario goldens verify nothing, and any disk or CPU load reshuffles them.

Fix:
- Trigger shots 3 and 4 on a settled camera, not on a frame. The e2e widget can wait until the camera focus is within a few elmos of the wisp's view position (or until `dt`-integrated time since the teleport exceeds ~5·tau), then shoot.
- Alternatively, drop the "in transit" shots and take one shot after settling in the plate room.
- Then tighten the tolerance: run-to-run drift here is 0.5–1.7%, so 3% is safe. Also add a sanity floor such as "not within X% of black" (or a mean-luminance check) for dark games.

### N2. The `ending_final` golden barely checks the end-screen text (tests)

`verification/games/partsneeded.sh:99`.

The golden is a white vignette with two thin lines of text, and the current run matches it at RMSE 0.0. Losing the text (the only game-specific content) changes a thin-glyph area of about 300×50 px out of 1280×720, which will likely stay under 8%.

Fix: also compare a crop of the text band, since `vf_golden` already takes a `CROP` argument, e.g. `600x80+340+330`.

### N3. The lever-gate check is self-referential (tests, carried over)

`rules-synced/src/gadgets/integration.rs:13,84-87`, `integration/checks.rs:208-223`.

The scenario pulls the levers that `triggers::LEVER_GATE_COMBINATION` marks `true`. The rules then open gate 20 when the levers match that same table. The check's comment says reading the negative ids as "must be off" would leave the door unopenable. It wouldn't: an inverted table would make the scenario pull the other levers, and the check would still pass.

Fix: in `integration/scenario.rs`, hard-code the levers to pull from `game_custom_spawn.lua`'s `["20"] = {-29318, 23884, -14619, -19115}` (pull 29318, 14619, 19115), independently of the rules constant.

### N4. The "Lua message" checks bypass the engine (tests)

`rules-synced/src/gadgets/integration.rs:1,135-150`.

The header says the scenario "drives ... through the real message path". But `send()` and `steer()` call `input::handle_message` or `input::steer` inside the rules module. Several checks are therefore named for a path they don't test:
- "movement Lua message reaches wisp controller";
- "form-switch Lua message enters body form";
- the lever pulls.

Only `Hello` crosses `SendLuaRulesMsg` → engine → `RecvLuaMsg` → `InputGadget`/`StatusGadget`. Beyond that:
- The UI's key handling (`gui_wisp_control.rs`), its form prediction and its lever picking are not exercised at all.
- `bring_and_pull_lever` teleports the lever onto the wisp, so the reach limit is never tested.
- `remote_lever_refused` (`checks.rs:131`) fails for three reasons at once (spirit, no arms, far away), so it cannot tell which guard works.

Fix:
- Have the e2e/headless UI build send the scenario's commands via `crate::commands::send`, or feed synthetic key events to `GuiWispControlWidget`.
- Add one embodied, armed, out-of-reach pull that must be refused.
- Rename the checks that stay direct.

### N5. The restart script duplicates `launch/` against the repo rule, and restart is untested (structure)

`ui/src/restart.rs:1-88`.

`RESTART_SCRIPT` is a hand copy of `launch/games/partsneeded/wasm.txt`. It is byte-identical today, and the comment says "keep the two in sync". `CLAUDE.md` says `launch/` is the only source of launch settings. Every other port restarts inside the rules (MyCube `ui/src/rules.rs`, Gravitas, Hunted, TTLD send a restart message). Parts Needed alone reloads the engine with a hard-coded script, and nothing tests that path.

Consequence: editing the launch profile (graphics or options) silently diverges after the first restart.

Fix, in order of preference:
1. Do a rules-side reset like the other ports.
2. Get the current start script from the engine (an SDK accessor; `reloadforce` goes to the menu, so it won't do).
3. At least add a static verification check that diffs `RESTART_SCRIPT` against `launch/games/partsneeded/wasm.txt`.

### N6. The piece mask is applied twice; the second pass looks like a leftover workaround (structure, silent)

`rules-synced/src/wisp.rs:162-187`.

`sync_wisp_pieces` first applies the mask through the CUS host (`set_piece_mask` → `ctx.hide`/`ctx.show`). It then walks `get_unit_piece_map` and calls `set_unit_piece_visible` for every piece, ignoring the result with `let _`. The comment's reason ("Show(parent) semantics differ on the Core renderer ... can implicitly re-enable children") doesn't match the engine: both `CUS_OP_SHOW`/`HIDE` (`NativeUnitScript.cpp:99-103` → `CUnitScript::SetVisibility`) and `SetUnitPieceVisible` (`NativeInterface/api/SyncedCtrl.cpp:3562`) set the same per-piece `SetScriptVisible` flag, with no recursion.

Consequence:
- The same state has two owners.
- There's a string-compare scan of 18 names per piece on every mask change.
- A failure of the second pass is invisible.

Fix: drop the engine-level pass. The anim goldens and `wisp model pieces` checks cover it. If a real case remains, document it with the engine commit that needs it.

### N7. Kill links set `do_kill` with `let _` (silent failure)

`rules-synced/src/triggers.rs:86`.

`do_kill` is the only thing that makes a cage kill rather than free its prisoner (`cages::kills`, `props::cage_open`). If the set fails, a kill plate silently saves the prisoners and the ending changes. Use `crate::log::check` like the ONOFF orders do.

`endgame.rs:172-174` (the `is_dying`/`killed_frame`/`destroy_frame` params the UI fade reads) and `cages.rs:25` are minor by comparison. `spawn_unit` already logs.

### N8. Undocumented Lua differences (fidelity, minor)

- `endgame.rs:14-24` "settling" delays game over while every remaining NPC is mid-death. `game_end.lua` doesn't wait: `alive_wisps` only drops on `UnitDestroyed` 45 frames later. The last pickup within 1.5 s of the last rescue gives Ending #1/#3 in Lua and #2 here. This is arguably a fix, but it isn't in the README.
- Same-pass lever+kill-plate ordering: when a lever and the kill plate open the same cage in one 5-frame pass, the port always kills. `do_kill` is set in the link loop before any ONOFF goes out (`triggers.rs:76-91`), and `cages::kills` is read afterwards. In Lua, the outcome depends on `pairs` order, because `cage.lua` reads `do_kill` synchronously in `Activate`. This is an edge case; one README line would do.

### N9. Smaller structure notes

- `unit_scripts/mod.rs:29-31`: `SIG_GATE` and `SIG_WALK` share bit 1 on purpose. That is fine, but it's the kind of thing a `SignalMask` per script kind in `CusHost` would make unnecessary.
- `gfx_eyes_effect/npcs.rs:23-27`: during the 500-wisp ending it calls `get_all_units` plus `get_unit_def_id` per unit on every update. Track `UnitCreated`/`UnitDestroyed` for npcwisps instead; the UI already gets unit callins.

**Re-entrancy:** no findings. Every engine call made under a `Resource` borrow (positions, move goals, velocities, rules params) raises no callin. Orders go out after the borrows end (`triggers.rs:59-104`, `input.rs:70-81`), and STOP/destroy go through `ctx.delay`.

**Global state:** only the immutable `OnceCell` def caches remain (`rules-synced/src/defs.rs:108-110`, `ui/src/defs.rs:13-15`). That's fine.

## 4. Strengths

- `triggers.rs` is a faithful, well-commented port of `unit_plate.lua`: latching, bitmask sign semantics and orders after the borrows end.
- The integration checks now measure unit-script effects on real pieces (Base_001 turn, Button sink, gate slide, arm/leg relative to Body), not Rust-side flags.
- The test gadgets and widgets are feature-gated and never ship.
- `SendOnChange` status plus hello, and the prediction timeout, make the UI/rules sync robust.
- The move to `CusHost` was clean. `Create` runs once, and `with_cus_module_or_defer` is used for attach and masks.
