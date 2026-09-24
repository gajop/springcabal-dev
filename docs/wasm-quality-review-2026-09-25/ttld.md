# To The Last Drop (TTLD) — review round 3

Paths are relative to `spring-linux/games/ToTheLastDrop-wasm.sdd/wasm-src/` unless stated.
Lua paths are in `ToTheLastDrop.sdd/`. Line numbers are from 2026-09-25, WASM repo HEAD `d0fe137`.
The WASM repo is clean.

## 1. Grade: B+ (unchanged)

Every bug and risk from round 2 is fixed, and the Heartburn check is now a real test (engine
damage, falloff, friendly fire, crater, all via UnitPreDamaged). But checking against the
*committed* Lua turned up new problems. Poultice's direction is reversed. The attribute port loses
the reload-state handling, so a stunned ork that fires can stay disarmed for good. Destroyed houses
keep their window lights. The only compared screenshots don't show the fireball they are meant to
catch.

## 2. Round 2 findings: status

| Finding | Status |
|---|---|
| Heartburn: flat 1600 in a 2D cylinder, enemies only | **Fixed** (`0e55337`). It is the weapon def's own projectile now: AoE 500, edge 0.9, impulse, crater, every team (`player/spells.rs:236-285`). |
| Staff flicker frozen in the shipped game | **Fixed** (`71614cc`, `0b03a5b`). It is only still in e2e/gallery builds (`ui/src/lights/mod.rs:56-79`), and the README lists it. |
| Right-click sends `attmove` on press and `attack` on hold | **Fixed** (`006616a`). The UI only sends `attack`, and the README notes this. |
| A boss that fails to spawn counts as instant victory | **Fixed** (`a8ac21c`). `combat/victory.rs:147-155` respawns it, and the README lists it. |
| `killed()` transfers the unit inside a CUS export | **Fixed/dropped** (`e1d256b`). There is a comment on the engine refusing the transfer (`unit_scripts/mod.rs:341-344`). |
| Rules talk to their own scripts through public rules params (`firing`/`fireTx`) | **Still open** (`player/control.rs:318`, `unit_scripts/mod.rs:212-221,240-245`). |
| `STATUS_PERIOD` and `GameEnd` defined in both crates | **Still open** (`rules-synced/src/gadgets/status.rs:17`, `ui/src/game.rs:5`; `rules-synced/src/state.rs:88`, `ui/src/state.rs:24`). The `"restart"` string is duplicated too. |
| `boss_x`/`boss_z` written and never read | **Fixed** (`f27c808`). |
| The highlight runs with no hovered unit | **Fixed** (`737d420`). |
| Deferred lighting retries shader compiles every frame | **Fixed** (`692fa74`). |
| House lights scan all units until houses exist | **Still open, harmless**: it is a one-off until houses exist (`ui/src/lights/houses.rs:62-72`). |
| The UI polls `on_fire` on all 107 houses | **Fixed** (`b8085e3`, in the README). |
| `DeathParalysis` entries never pruned | **Fixed** (`5d82588`, `unit_scripts/tasks.rs:353-355`). |
| `dbg_e2e` doesn't use `Screenshots` | **Fixed** (`ef02645`). |
| Test: the heartburn check passes on any health loss | **Fixed**. It now checks centre > edge > 0, ally damage and the crater (`integration/gameplay.rs:290-325`). |
| Test: the stun checks return early | **Fixed** (`e2452ac`). |
| Test: the victory check forces the gate | **Partly fixed**. The VictoryGadget now declares victory by itself after a real `destroy_unit`. But `final_wave_checks` still calls `combat::open_victory` directly (`integration/victory.rs:14-17`), bypassing StoryGadget's `boss_due` path, and the boss-respawn branch is never exercised. |
| Test: most `dbg_e2e` log lines are never checked | **Partly fixed**. Hover, wheel, selection, Poultice and tracking `after_move` are now required. `north_edge`/`north_edge_late` are neither required nor reached (see §3.6). |

## 3. New findings (most severe first)

### 3.1 Poultice is reversed: the original pulls enemies onto the mage, the port throws them away (fidelity, not in the README)
- `rules-synced/src/player/spells.rs:352-366` uses `position - origin`.
- The committed Lua uses the opposite, `dx = x - ux` (`ToTheLastDrop.sdd` HEAD, `LuaRules/Gadgets/api_blood_magic.lua:301`).
- With `vx = dx/flyTime`, `vy = flyTime*g/2 + dy/flyTime`, the Lua arc lands each enemy *on the mage* after `flyTime`. That gathers the horde for Heartburn.
- The spell arrived in `77428e4` "Replaced Dialysis with a much more synergistic spell", and `fad734e` buffed it alongside "tighter spawn spacing for more satisfying fireballs". So the pull looks deliberate.
- The Rust comment (`spells.rs:352-354`) calls the pull the bug. The Lua checkout has an **uncommitted** edit that flips it to match ("Poultice throws enemies away").
- Both tests enforce the push:
  - headless: `away_dot > 1` (`integration/gameplay.rs:343-349`);
  - visual: `moved=[1-9][0-9]{2,}` (`verification/games/ttld.sh:273`).
- **Consequence:** the port plays a different spell from the jam game, the reference build was edited to agree, and nothing records the change.
- **Fix:** decide with the user. Then either restore the pull (and change both checks to "lands near the mage"), or list the push in "Differences from the Lua version".
- Related: the Lua reference checkout has 22 uncommitted entries (`git -C ToTheLastDrop.sdd status`). They include `api_blood_magic.lua`, `unit_player_controller.lua`, `ui_endgame.lua` and a new `GameData/weapondefs_post.lua`. `lua-visual` and `pose-parity` run against this modified tree, not the original. Commit those edits as "Lua compat fixes" with the fidelity-relevant ones called out, or review against HEAD.

### 3.2 Paused reload never touches `reloadState`: a stunned ork that fires is disarmed for the rest of the round (bug)
- `combat/attributes.rs:113-126` sets only weapon slot 0's `reloadTime`: `100000` when the factor is 0, else `base/factor`.
- Lua's `UpdateWeapons` (`unit_attributes_generic.lua:146-209`) does more, for **every** weapon:
  - it rescales `reloadState` whenever it changes `reloadTime`;
  - when paused, it pins `reloadState` to `frame+UPDATE_PERIOD+1`.
- Consequences in Rust:
  - A Migraine-stunned ork (move 0.1, reload 0) whose weapon is loaded still bites when a villager is in range. That shot sets `reloadState = now + 100000 s`, and restoring `reloadTime` when the stun ends doesn't pull it back, so the ork never attacks again.
  - A reload already in progress isn't slowed or sped up by stun or Adrenaline.
  - Weapon 2 (`Firebomb`, house-only, 450 damage, which sets houses on fire) is never slowed or paused. Stunned orks keep burning houses at full rate.
- The stun check (`integration/gameplay.rs:362-400`) only compares `reloadTime` before and during the stun, on the mage, which isn't firing. It can't see any of this.
- **Fix:**
  - Port `UpdateWeapons`: loop over all weapons, cache each base reload per def, rescale `reloadFrame` exactly as Lua does, and pin it while paused.
  - Add a check: stun an ork next to a villager, let the stun expire, and assert that it fires again.

### 3.3 Destroyed houses keep their window lights (fidelity bug)
- `ui/src/lights/mod.rs:82-84` places house lights once (`houses.rs:8-49`) and never removes any. `gfx_lighting` has no `unit_destroyed`.
- Lua's `ui_house_light.lua:42-44` drops a house's lights in `UnitDestroyed`.
- **Consequence:** burned or collapsed houses leave glowing windows in empty space for the rest of the round.
- After a restart the lights happen to line up again, because `HOUSE_POSITIONS` is fixed.
- **Fix:** key the lights by house unit id and drop them on `unit_destroyed`. `gfx_fire` already tracks units this way.

### 3.4 Silent failures on attribute calls (CLAUDE.md rule)
- `combat/attributes.rs:89-105,125` has `let _ =` on `set_move_type_numeric` (max speed, wanted speed, turn rate) and on `set_unit_weapon_state(reloadTime)`.
- These carry the town's half speed, stun, Adrenaline, flee disarm and death paralysis. If they fail, those effects are silently lost.
- **Fix:** route them through `engine::check`.
- `engine::set_unit_number` (`engine.rs:6-8`) also drops errors. It is fine for `on_fire`/`unorkable`. But `firing`/`fireTx` gate every mage shot (`unit_scripts/mod.rs:212-214`), so check those, or better, stop using rules params for them (the round 2 cleanup).

### 3.5 Other fidelity differences not in the README (smaller)
- **Spell sound volumes:**
  - Lua plays spell, drain and heal sounds at volume 30, the fireball launch at 12 and deaths at 10 (`api_blood_magic.lua:57,170,200,237,265,296`).
  - Rust uses 1.0 for all spell and drain sounds (`fx.rs:52-53`) and 10 only for deaths (`unit_scripts/common.rs:82`).
  - OpenAL clamps gain after distance attenuation, so the Lua sounds reach full volume from much farther away. At camera distance the Rust spells are probably noticeably quieter. I haven't verified this by ear.
- **The drain sound plays at the mage, not at each drained villager** (`player/drain.rs:68,100` vs `SpawnEffect(..., SOUND_DRAIN)` at the unit, `api_blood_magic.lua:95,125`).
- **Failed drains give villagers back:**
  - When a non-partial drain fails, Rust transfers the would-be victims back to the player (`drain.rs:92`).
  - Lua only restores houses. The villagers stay on neutral team 2, a Lua bug.
  - The Rust behaviour is better, but list it.
- **CEGs changed beyond what the README says:**
  - `effects/gtfo_pulse.lua` (Poultice): about twice the flash size, twice the TTL, and an extra `wave` particle system.
  - `effects/fireball_spell.lua` (`fireball_ball` trail): recoloured, non-directional, longer life.
  - The README only mentions the sprite and `fireball_impact`.
- **Movement attributes are a partial port** (`attributes.rs:81-107`). Compared with Lua's `UpdateMovementSpeed` (`unit_attributes_generic.lua:218-300`):
  - Lua raises `decRate` ×1000 while slowed and clamps `accRate`. Rust doesn't, so stunned units coast.
  - Lua forbids reverse while slowed. Rust doesn't.
  - Lua zeroes velocity only on the ground. Rust zeroes it unconditionally, so a unit that starts dying mid-toss drops straight down instead of finishing its arc.
- **Victory doesn't lock the rules:** Lua's `HandleLuaMessage` ignores input once `gameEnd` is victory. Rust relies on the UI's modal end screen (`ui/src/input.rs:17-19`). This is harmless while the UI is the only sender.

### 3.6 Tests that prove less than they claim
- **The only compared shots miss the fireball:**
  - The visual suite compares goldens for shots 1-3 only (`verification/games/ttld.sh:282`), i.e. UI ticks 11, 22, 26 (`ui/src/widgets/dbg_e2e.rs:18-20`).
  - The spell is sent on tick 25 (frame 164 in the last run). It takes effect ≥10 frames later, and shot 3 is at frame 171. So golden `shot_3.png` shows the mage *before* the fireball exists; screen 4, which is uncompared, has it.
  - Ticks are UI updates, about 6-7 game frames per tick on llvmpipe, so on a GPU the same tick lands on a different frame. This is the same timing-dependent capture as Parts Needed.
  - The hover outline and target panel (ticks 37/42), Poultice (55-75) and camera shots are never compared.
  - **Fix:** schedule captures by game frame, not UI tick; compare a fireball-in-flight shot and a hover shot; drop the rest or mark them as artifacts.
- **Late e2e steps never run:**
  - The run always ends on its 60 s timeout, which `vf_require_exit_or_timeout` accepts (`ttld.sh:262`). The last run stopped at tick ~120.
  - So shots 240/330 and the `north_edge` tracking the widget's doc comment promises never happen, and nothing notices.
  - **Fix:** quit on a marker (`vf_quit_when`) and require the edge tracking, or delete those steps.
- **The hover check is near-tautological:**
  - `hover_fixture` first searches a grid until `cursor::unit_at` returns the unit (`dbg_e2e.rs:393-400`), then logs a trace at that spot.
  - The suite's regex `trace=1:[0-9]+` doesn't even compare the traced id with `unit=`.
  - The widget's real output (target panel, outline) is asserted nowhere.
- **Spells bypass the input path in the headless suite, and two are never cast:**
  - `spell_checks` calls `player::cast` directly, three times in one frame, ignoring the cast lock (`integration/gameplay.rs:191,225,255`). The `spell|…` parse and `Player::accept`/`take_cast` path is only covered by the e2e run.
  - Migraine and Transfusion are never cast. The stun check calls `combat::stun` directly (`gameplay.rs:375`), so Migraine's wave delay, falloff and enemy filter, and Transfusion's partial drain, are untested.
  - The Adrenaline check only asserts that the cast was accepted and villagers were drained, not that the buff changed speed or reload.
- **Dead start-script keys:** the start script sets `minspeed=100; maxspeed=100` (`ttld.sh:43`). The engine reads these only from `ModOptions` (`GameSetup.cpp:639-640`), so they are dead config.

### 3.7 Structure and cleanups
- **`cast_level` holds two things:** it is the cast level for `CastAnimation` and the *duration in frames* for `Buff`/`Stun` (`unit_scripts/mod.rs:402-414`, `tasks.rs:277,299`). Give the durations their own field.
- **Cross-game duplication:** `ui/src/mapedge.rs` (252 lines) and Gravitas' `mapedge.rs` (130) port the same Lua `map_edge_extension`. `ui/src/fire/` duplicates Gravitas' `fire/` (emit/particles/render, diverged). Both belong in the shared crate or `springcabal-control`.
- **Global state:** the only remaining `thread_local!` is the immutable defs cache (`defs.rs:72-80`, with an interior `RefCell` info map). That is acceptable, since the CUS host needs defs outside the gadget `Global`.
- File sizes are fine (largest: `ui/src/deferred_lighting.rs` 484, `ui/src/widgets/dbg_e2e.rs` 439).
- Re-entrancy is fine: every gadget releases its borrows before engine calls that can raise callins (`destroy_all`, drains, spawns, orders). `killed()`/`death_task` reach `Global` through `with_global` with nothing held.

## 4. Strengths
- A clean gadget split with a well-documented round `Phase`, and an in-rules restart that the headless run checks against round 1's unit, villager and enemy counts.
- Heartburn is now fully engine-driven and its test checks falloff, friendly fire and the crater through `UnitPreDamaged`.
- `pose-parity` compares Lua and Rust piece transforms for the spell animations: rare and valuable.
- The unit scripts match the Lua scripts closely (timings, signal masks, FireWeapon threading, weapon indices). Where they deviate, comments say why (the builder uses the crossbowman script; the engine refuses the death transfer).
- The README's "Differences" section exists and is accurate as far as it goes. It needs §3.1 and §3.5 added.
