# Gravitas review, round 3

Reviewed the committed code at `32f6ad1`. Paths are relative to
`spring-linux/games/Gravitas-wasm.sdd/wasm-src/` unless stated otherwise. For ui files that have
uncommitted changes, line numbers come from `git show HEAD:<path>`.

## 1. Grade

**B+** (rules A−, ui C+). Up from B. Every round-2 bug and risk in the rules is fixed. The rules
gadgets are small, own their state and release their borrows before calling the engine. The e2e
suite grew from 14 to 18 cases and now covers flee, shoot, death, input through the ui module, and
the real level. What holds the grade back:
- one real gameplay difference from Lua: collision damage is gone, and the README doesn't list it;
- the ui module hasn't moved (global state, not on the shared crate), blocked by the fire WIP;
- a build check that can never fail;
- a golden that is too loose to notice units moving.

## 2. Round-2 findings, status now

**Bugs**
- STOP+MOVE drops the FIGHT assault: **fixed**. `robots.rs:72-96` inserts the escape at the front
  with ALT, as Lua does. `tests/flee.rs` checks that there is one MOVE in front of the FIGHT, twice.
- Death animation never played / `DIE` table dead: **fixed**. See `unit_scripts/gravit.rs:142-154`
  and `die` at `:295-310`. The robots' three-stage death is at `unit_scripts/robots/mod.rs:259-276`.
  `tests/death.rs` covers both.
- Any Gravit's death is a loss: **fixed**. `gadgets/player.rs:253-265` checks the player's unit.
  `tests/restarting.rs:43-52` kills another Gravit first.

**Risks**
- Robots never fire while moving: **fixed**. The rules params are gone, `robots/weapons.rs:369`
  always allows the shot, and `tests/shoot.rs` checks it.
- Level rules params set after `create_unit`: **fixed**. They go through `Global.pending_rules`
  (`units.rs:44-48`) into the first gadget's UnitCreated (`gadgets/unit_setup.rs:31-33`), and
  `tests/level.rs:198-214` checks the sizes each hazard had in UnitCreated.
- Deferred script attach doesn't re-validate the unit: **fixed**. `CusHost::unit_created` checks
  the def again (spring-bar `rust/crates/spring/src/cus/host.rs:262-274`).
- Restart resets `Global` field by field: **fixed well enough**. `restart.rs:17-43` destructures
  `Global`, so a new field won't compile until it is handled.

**Cleanups**
- `probe.rs` and `Terrain.levelled` ship: **fixed** (`b9a271a`). The ui's `fire/probe.rs` is
  untracked WIP.
- `unit_piece` fetches the whole piece map per call: **fixed**. Pieces are resolved once
  (`immobile.rs:35-48`). Only the test harness still looks pieces up by name.
- `fire.rs` reads `invulnerable` by name every frame: **partly**. It goes through
  `effects::is_invulnerable` now (`fire.rs:71`), but it is still one rules-param read per unit per
  frame. Lua does the same, so this is fine.
- Input formats two Strings per frame: **fixed**. `ui/src/input.rs:68-90` sends only on change.
- Hand-written `atan2`: **fixed**.
- `jump::blocked` loops forever when `jumpSpeed` is 0: **fixed**. See `jump.rs:160-163`; the README
  lists it and `tests/jump.rs:193-198` checks it.
- ui module not on the shared crate (music, shots, keys, menu, status parsing): **still open**. See
  §3.5.

**Tests**
- "Re-entered world state" grep of a string nothing emits: **fixed**. It now looks for
  `panic|already borrowed` (`verification/games/gravitas.sh:87-88`), which matches the
  `spring-addons` Resource conflict message.
- The `visuals` case can't fail: **fixed**. It now needs the ui module to report the shot taken
  (`tests/visuals.rs:23-29`). The image comparison behind it is weak, though (§3.3).
- `input` injects into `Global`: **fixed**. It uses a scripted pointer in the ui module
  (`tests/harness.rs:43-58`, `ui/src/shots.rs`).
- All cases share one arena, and restart relies on the others finishing first: **still open**. There
  are 18 cases now, on a hard-coded frame schedule. The dependencies are written into comments:
  - `tests/restarting.rs:33` "After the jump case is done with its Gravit";
  - `tests/death.rs:226` "After the fire and barrel cases";
  - `tests/level.rs:158`.
- The real level is never checked: **fixed** (`tests/level.rs`).

**WIP (uncommitted fire work)**: unchanged since round 2. See §3.8.

## 3. New findings (most severe first)

### 3.1 Collision damage is gone; Lua has it, and the README doesn't list it (bug, fidelity)
`rules-synced/src/gadgets/fall.rs:26` returns 0 for every object-collision hit (weapon −3).
- Lua `game_fall_damage.lua:185` zeroes only hits where `attackerID == nil`. It then deals its own
  unit-unit collision damage in `GameFrame` (`:252-345`, weapon −7), and 2.5× the engine damage for
  collisions with nothing it can match.
- On this engine, ground-unit collisions always pass the other unit as the attacker
  (`spring-bar/rts/Sim/MoveTypes/GroundMoveType.cpp:1736,1740,1766,1770`). So the Lua gadget
  lets the engine's damage through (`return damage`, `:246`).
- `GameData/ModRules.lua:7` turns on `allowUnitCollisionDamage = true` on purpose.
- Robot-on-robot hits are still zero, through friendly fire (`unit_robots.lua:129`).
- **Consequence:** in Lua, a robot slammed by the gravity gun into a wall, a gate or the Gravit
  takes collision damage, and so does the Gravit when it is hit. In the port nobody does. This is
  the game's core mechanic. The gadget comment ("objects don't hurt each other on collision")
  states the difference, but the README's "Differences from the Lua version" doesn't.
- **Fix:** return `None` for −3 when `attacker_id >= 0` (the engine's damage, as Lua gets on this
  engine). Keep 0 only for attacker-less hits. Add an e2e case that pushes a robot into a wall and
  expects damage. Or, if the port wants no collision damage, list it in the README.

### 3.2 "clippy is clean" can never fail (test that proves nothing)
`verification/games/gravitas.sh:119-126`:

```bash
( cd …; cargo clippy … 2>&1 | grep -qE '^(error|warning)' ) && return 1
return 0
```

- `lib/common.sh:3` sets `-o pipefail`, and the workspace denies warnings (`Cargo.toml` lints,
  `warnings = "deny"`). Any clippy finding therefore makes cargo exit non-zero.
- With `pipefail`, the pipeline takes cargo's status even though `grep` matched. The subshell fails,
  `&& return 1` is skipped, and the function returns 0: **PASS**.
- A clean run also returns 0. Both "clean" checks (lines 78-79) pass whatever clippy says.
- **Fix:** run `cargo clippy … -- -D warnings` and use its exit status. Check the other games'
  suites for the same pattern.

### 3.3 The arena golden is too loose to notice units moving (test)
`verification/games/gravitas.sh:161` compares against `fixtures/gravitas/goldens/arena.png` with
`SHOT_TOLERANCE` 10 (% RMSE).
- The golden was recorded on 2026-09-23 from `c480db7` plus the uncommitted fire work
  (`PROVENANCE.txt`).
- The arena changed after that: `2761ab1` moved the walking robots.
- The last run's `out/gravitas-shots/goldens/arena.diff.png` shows these in different places:
  - the flee and shoot robots;
  - a block of arena scenery;
  - the fire.

  Yet it measures 2.1% RMSE (I re-ran `compare`) and passes.
- The shot is taken at frame 75, while 17 other cases move, burn and kill units in the same arena.
  The fire's particles come from an unsynced RNG. So the frame isn't deterministic, and only a
  loose limit keeps it green.
- **Consequence:** the golden proves little beyond "something rendered". The HUD and fire-pixel
  checks (lines 170-201) are the real signal.
- **Fix:**
  - take the shot in its own staged arena, or before the other cases start moving units;
  - re-record the golden from HEAD once the fire work lands;
  - tighten the limit to around 2%.

### 3.4 Other undocumented differences from Lua (low)
- **Sounds are positional in the port, not global.**
  - Lua plays the gate, plate and Gravit death sounds without a position, so they are heard at full
    volume anywhere (`scripts/gate.lua:22,35`, `plate.lua:20,32`, `gravit.lua:140`).
  - The port plays them at the unit (`unit_scripts/common.rs:38-43`, called from
    `immobile.rs:98,107,116,125` and `gravit.rs:146`). The engine attenuates them with distance
    (`rts/NativeInterface/api/Sound.cpp:54-61`), so a gate opening off-screen may be inaudible.
  - **Fix:** pass `Float3::default()` as the position, as `effects.rs` does for the barrel.
- **Robots stop sparking as soon as they leave an electric field.**
  - Lua keeps sending sparks, without damage, for 60 frames after a robot leaves
    (`unit_electrafi.lua`, the `watchedRobots` lingering branch).
  - `electrafi.rs:53` filters those contacts out, so the spark stops at once. It's visual only.
  - **Fix:** keep the contact and send the spark, without damage.
- **The Gravit's walk and idle tasks don't cancel an earlier copy of themselves.**
  - `gravit.lua`'s `Walk`/`Idle` call `Signal(SIG_WALK)`/`Signal(SIG_IDLE)` before setting their
    mask.
  - `gravit.rs:241-257` only set the mask, and `start_moving`/`stop_moving` (`:114-130`) signal the
    other task.
  - If the engine sends StartMoving twice without a StopMoving between them, two walk loops would
    fight over the pieces. I couldn't show that it happens; the jump calls signal everything
    anyway.
  - **Fix:** a one-line `ctx.signal(SIG_WALK)` / `ctx.signal(SIG_IDLE)` at the top of each task.
- **The flee point search clears its candidates differently from Lua.**
  - `unit_robots.lua:101-102` has an off-by-one: `goodPoints` is only cleared when it holds more
    than one point. So a worse first direction survives, and so does the score it is compared
    against.
  - `robots.rs:503-509` does what was meant. Direction choice may differ slightly. Add it to the
    README's list, next to the two `unit_robots.lua` typos already there.

### 3.5 ui module: global state, and still not on the shared crate (structure; blocked by the WIP)
- **Global state.** There is a `thread_local! STATE: RefCell<UiState>` (`ui/src/state.rs:35`) and a
  `static STATE` with `unsafe impl Sync for SharedState` (`ui/src/fire/distortion.rs:34-46`).
  Round 2 put the `unsafe impl Sync` down to the WIP, but it is in HEAD. It's the last
  `unsafe impl Sync` across the ports.
- **Not on the crate.** `ui/Cargo.toml` at HEAD depends only on `spring` and `spring-addons`. What
  the crate already offers:
  - `ui/src/music.rs` is a hand-rolled loop; `springcabal::music::MusicLoop` does this.
  - `ui/src/hud/status.rs:20-32` parses `GRAVITAS_STATUS` by hand, although the rules write it with
    `Encoder` (`rules-synced/src/status.rs:12-18`); `springcabal::message::fields` reads it.
  - `ui/src/camera.rs` could use `springcabal_control::camera::{Follow, Smoother}`.
  - the e2e `shot`/`quitforce` handling (`ui/src/shots.rs:33-41`) duplicates
    `springcabal::shots`.
- **Fix:** once the fire work is committed:
  - add `springcabal`/`springcabal-control` to the ui crate;
  - move `UiState` into a `Resource` on `Global`;
  - keep the static only if the GL callback API really needs it, and say so in the comment.

### 3.6 Silent failures that break gameplay (judged, not counted)
These `let _ =` calls hide a failure that would quietly disable a mechanic:
- `gadgets/fire.rs:41` and `gadgets/electrafi.rs:44` (`add_unit_damage`): hazards stop hurting.
- `effects.rs:61`: the barrel blast deals no damage.
- `jump.rs:192` (`set_unit_position`): the Gravit freezes mid-jump.
- `mission.rs:152` (`set_unit_health`): robots don't start stunned in their fields.
- `restart.rs:8` (`destroy_unit` in the wipe): old units survive a restart.

`units::order`, `move_ctrl` and `set_rules_params` already go through `diagnostics::check`. Use it
for these too. The sounds, CEGs, LOS, blocking and shape calls are fine as they are.

### 3.7 Dead code and leftovers (structure, small)
- `unit_scripts/mod.rs:132-136` implements `UnitScript::new`, and with it the `Script::None` arm
  (`:125` and eight match arms). Neither is reachable any more:
  - `CusHost` builds scripts through `UnitDefScript::for_def` (`module.rs:21-23`);
  - `capabilities` returns `None` for defs without a script, so those defs are never attached;
  - the trait says hosts needn't implement `new` (spring-bar `cus/script.rs:14-16`).

  Drop `new`, and make `for_kind` take a `ScriptKind`.
- `verification/games/gravitas.sh:74-77`, the "shipped module carries no test code" checks:
  - They read the untracked `.wasm` in the checkout, from whatever `just copy` last ran (the
    current one includes the ui WIP). The suite never builds that file.
  - If the file is missing, `! strings … | grep` passes.
  - **Fix:** build without the feature into the cache and check that. Or at least fail when the
    file is missing.
- `gravitas_headless` (`gravitas.sh:31-45`) only checks that the engine exits cleanly after 900
  frames of the real level; `tests/level.rs` covers more. Either give it a marker to assert
  (`level spawned: N of N`) or drop it.

### 3.8 WIP (uncommitted fire work), briefly
The same 8 files as round 2, plus the untracked `fire/probe.rs`:
- `fire_distortion.frag` still writes `gl_FragCoord.z` into the alpha mask;
- the round-2 notes on the size clamp and the LCG still apply;
- `verification/probes/gravitas-fire.sh:10` (committed in the dev repo) builds
  `--features fire-probe`, which only the WIP `Cargo.toml` defines;
- the arena golden and the anim gallery embed the WIP's rendering (BASELINE says the anim gallery
  fails in the checkout).

Needs a commit or a revert before §3.3 and §3.5 can move.

### 3.9 Re-entrancy
Nothing found. Every engine call that can raise a callin runs after its borrow is dropped. The
comments say so where it matters:
- `gadgets/robots.rs:30-38` (INSERT raises UnitCmdDone);
- `gadgets/respawn.rs:216-234`;
- `tests/runner.rs:126-133`.

`gadgets/barrel.rs:23-25` defers the blast out of UnitDestroyed.

### 3.10 Global state (rules)
Only `defs.rs:67` is left: a `thread_local` `OnceCell` holding the leaked, read-only defs. It's
fine.

## 4. Strengths worth keeping
- The rules are organised well:
  - one gadget per Lua gadget, each small;
  - `PerLevel<T>` (`state.rs:117-142`) resets gadget state on restart through a generation counter;
  - the `UnitPreDamaged` chain order is written down (`gadgets/mod.rs:34-36`).
- Fidelity work is careful and commented:
  - the flee search, the jump arc and its checks, the fire cone (Lua bug kept);
  - the `QueryWeapon` rotation quirks;
  - the README records the Lua typos it deliberately doesn't copy.
- The e2e suite drives real engine paths: orders, damage with an attacker, the ui module's input
  and restart button, and the real level with its link and hazard-size checks. It quits itself and
  requires a clean exit and an exact `passed=18 failed=0`.
