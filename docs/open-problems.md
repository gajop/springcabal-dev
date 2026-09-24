# Open problems in the WASM ports

The problems still open in the seven ports, the shared crate and the harness. Nothing fixed is
listed; the earlier reviews and what they fixed are in git history (`docs/` before 2026-09-25).
Delete an entry when it is fixed.

- Paths are relative to `spring-linux/games/<Game>-wasm.sdd/wasm-src/` unless stated otherwise.
- Lua paths are relative to the Lua original next to it.
- ✔ means the coordinator re-checked the finding in the code; the rest come from the 2026-09-25
  review and are specific enough to verify quickly.

## 1. Gameplay bugs (the port plays differently from Lua)

### High
- **Area17: the silent beam slots get none of their special handling** ✔.
  - The UFO fires 4 slots per beam: 1 with sound and 3 `…silent` defs (`Units/ufo.lua:73-104`).
  - `weapons.rs:94-160` and `defs.rs:172` only recognise the non-silent id.
  - 3 of 4 gravity beams therefore don't pull. They deal raw damage instead: about 180 dps
    against 100-HP civilians, killing the humans the player wants to capture.
  - Only a quarter of the napalm patches appear.
  - Fix: resolve weapon behaviour per def from the custom params, as Lua does.
- **Hunted: `unit_invulnerable.lua` was never ported** ✔.
  - The player's shots (50,000 damage) and mines (150,000, AoE 200) destroy carrots, burrows and
    even the gun.
  - Each lost carrot costs score and ammo, and brings the game over closer.
  - Fix: a `unit_pre_damaged` that returns 0 for everything except rabbits, lighthouses and mines.
- **Hunted: `unit_blocking.lua` was never ported** ✔. Burrows and carried carrots block and
  collide, so rabbits spawn inside burrows.
- **Flove: Skip works on every story, not just the tutorial.**
  - Pressing `S` on the king's story grows 3 trees, resets mana and respawns wave 1, and it can be
    repeated.
  - Skipping during Repel leaves the trees immune to damage for the round.
  - The code: `ui/src/story.rs:83-133`, `ui/src/input.rs:136`, `rules-synced/src/story.rs:91-99`.
- **Gravitas: collisions between objects never do damage.**
  - `gadgets/fall.rs:26` zeroes every weapon −3 hit.
  - Lua zeroes only hits without an attacker. On this engine unit collisions carry one, so Lua
    lets them through.
  - A robot slammed into a wall by the gravity gun takes no damage, and that is the core mechanic.
- **TTLD: Poultice throws enemies away; the committed Lua pulls them onto the mage.**
  - The code: `player/spells.rs:352-366`.
  - Both test suites check for the throw.
  - The Lua checkout has an uncommitted edit that flips Lua to match the port (see §7).
- **TTLD: a stunned ork that attacks is disarmed for the rest of the round.**
  - `combat/attributes.rs:113-126` sets only slot 0's `reloadTime`, and never touches
    `reloadState`.
  - Firebombs (slot 2) are never slowed, so stunned orks keep burning houses.
  - Fix: port Lua's `UpdateWeapons`.

### Medium
- **Area17: impulses.** Ground units never get Lua's vertical lift, so black holes lift much less.
  The ±4 unstick impulse is on the black hole; Lua puts it on the gravity beam (`weapons.rs:279-308`).
- **Area17: the God Gun costs 7,500 biomass instead of 37,500.** The same formula error is in the
  rules and the UI (`upgrades.rs:342-354`, `ui/src/rml/tech_data.rs:159-164`).
- **Area17: civilians of a destroyed building freeze forever.** Lua keeps them wandering
  (`civilians.rs:242-244,411-419`).
- **Area17: a human dropped by the beam walks with the float animation forever**
  (`cus_scripts/human.rs:140-157`).
- **Hunted: the gun's recoil kicks it down; Lua kicks it up** (`weapons.rs:176-183`, sign of `y`).
- **Hunted: rabbits probably hop in place while eating.** The AI calls `StartMoving` on every
  update (`rabbits/steering.rs:172`, `rabbits/mod.rs:226,241`). Needs a pose check to confirm.
- **Flove: Skip spawns wave 1 at once.** Lua only marks it spawned (`story.rs:98`).
- **Flove: the spire shows one branch fewer than Lua at every level** (`spire.rs:34`).
- **Flove: poison damages everything except flowers.** Lua's poison damages nothing but flowers
  (`love.rs:73-86`).
- **Flove: while the king's story types (6.5 s mid-wave), the player can't zap.** The game keeps
  running, whereas Lua pauses it.
- **TTLD: destroyed houses keep their window lights** (`ui/src/lights/mod.rs:82-84`).
- **TTLD: stunned units coast, may reverse, and a unit dying mid-toss drops straight down.** The
  movement attributes are only partly ported (`attributes.rs:81-107`).
- **MyCube: the port places a camera that Lua never applies.** Lua's `SetCameraState` is commented
  out, so the village is cut off at the top (`ui/src/widgets/gui_camera.rs:8-9`).

### Low (small, or document in the README)
- **Area17:**
  - every capture plays the swoop twice (`ui/src/widgets/api_sync.rs:132-134`);
  - napalm decay with upgrades differs from Lua;
  - the UFO brake threshold differs from Lua;
  - the black hole never pulls the UFO;
  - civilians are re-ordered every 300 frames.
- **Flove:**
  - the zap's impact sound (`fairy dust.wav`) is missing;
  - `love_happy` shows twice;
  - there is an extra `dirtfling` on promotion;
  - `love_heals` is shown for `zapecho` hits too;
  - mushrooms can pick the spire as the nearest target;
  - the flower-field slow changes only max speed.
- **Gravitas:**
  - gate, plate and death sounds are positional (Lua plays them globally);
  - sparks stop as soon as a robot leaves a field;
  - the walk and idle tasks don't cancel an earlier copy of themselves;
  - the flee search doesn't copy a Lua off-by-one.
- **Hunted:**
  - the floating text shows every change, including "Rabbits: -N" after a restart;
  - after a restart the gun and flashlight don't move until the mouse does;
  - the projectile count and spray are hard-coded.
- **TTLD:**
  - spell sounds play at volume 1 instead of 30;
  - the drain sound plays at the mage, not at each villager;
  - a failed drain returns the villagers (Lua leaves them neutral);
  - `gtfo_pulse` and `fireball_ball` CEGs changed without a README note;
  - victory doesn't lock the rules' input.
- **MyCube:** craters are 1–2 elmos off (`terrain.rs:11-16`, round `size` before halving).
- **Parts Needed:**
  - the "settling" delay changes which ending the last pickup gets;
  - when a lever and the kill plate hit the same cage in one pass, the port always kills.

## 2. Tests that prove less than they claim

- **Parts Needed: visual shots 3–4 catch a camera pan, show the wrong room, and pass** ✔.
  - An all-black frame would be only 10–13% off, against an 8% limit.
  - Fix: shoot once the camera settles, and tighten the limit to about 3%.
- **Parts Needed: other weak checks.**
  - The `ending_final` golden barely covers the text; crop it.
  - The lever-gate check reads the same table as the rules.
  - The "Lua message" checks call `handle_message` directly; only `Hello` uses the real path.
- **Area17:**
  - the "RmlUi callback" and "SDL input" lines come from direct calls, and no RmlUi event is ever
    dispatched;
  - the "four abilities" check can't fail for the God Gun;
  - weapon checks call `handle_message` directly;
  - the collision test bypasses the engine;
  - the Lua scenario suite duplicates the Rust suite's frame schedule and ships in the archive.
- **Gravitas:**
  - the "clippy is clean" check can never fail (`pipefail` plus `grep -q` in
    `verification/games/gravitas.sh:119-126`);
  - the arena golden passes with robots in different places (2.1% against 10%);
  - the "no test code" check reads whatever `.wasm` is in the checkout;
  - `gravitas headless` asserts nothing;
  - all 18 cases share one arena on a hard-coded schedule.
- **Hunted:**
  - the 10% visual tolerance can't see the HUD, and the end screen is never rendered;
  - the loss condition and carrying a carrot home are never exercised (game over is set directly);
  - a carrot-count check after shots would have caught the invulnerability bug.
- **Flove:**
  - tutorial stages 2–6 are never played, which is how Skip got through;
  - the UI suite drives the same round as the rules suite;
  - the zap, upgrade and flower checks call internals;
  - the scenario needs no minimum count.
- **TTLD:**
  - golden shot 3 is taken before the fireball exists;
  - shots are scheduled by UI tick rather than game frame;
  - the run always ends on its timeout, so the late steps (map edge) never run;
  - the hover check is near-tautological;
  - Migraine and Transfusion are never cast;
  - spells bypass the input path;
  - the stun check can't see the reload bug.
- **MyCube:**
  - all 5 shots are in the first 16 s and mostly sea (crop the village);
  - the scenery check calls `allow_command` directly, and its MOVE half can't fail.

## 3. Silent failures (`let _ =` on calls whose failure breaks play)

No game uses the SDK's `ResultExt::log_err`/`log_err_once` yet. Use it on these:
- **Gravitas:**
  - `restart.rs:8` and `respawn.rs:135` (`destroy_unit`);
  - `effects.rs:61,90,134`;
  - `gadgets/fire.rs:41` and `gadgets/electrafi.rs:44` (`add_unit_damage`);
  - `mission.rs:94,152`;
  - `jump.rs:192`;
  - `impulse.rs:80`.
- **Area17:**
  - `ufo_controller.rs:95,295`;
  - `upgrades.rs:98,180-181,248,293`;
  - `game_terrain.rs:52-64`;
  - `civilians.rs:362,392,422`;
  - `drones.rs:65,108`;
  - `fall_damage.rs:319`, `weapons.rs:222` and `abduction.rs:95`.
- **TTLD:** `combat/attributes.rs:89-105,125`, and the `firing`/`fireTx` rules params, which gate
  every mage shot.
- **Hunted:**
  - `units.rs:237-269`, the rabbit move-type setters;
  - `cus/lighthouse.rs:264-266,312-313`;
  - `audio.rs:52,65` ignore `Ok(false)`.
- **Flove:** `spire.rs:35-42` caches before a failed write; also `story.rs:176` and
  `unit_scripts/simple.rs:9`.
- **Parts Needed:** `triggers.rs:86` (`do_kill`), and `level/mod.rs:104,118`.
- **MyCube:**
  - `terrain.rs:52`;
  - `spawning.rs:51-63`;
  - `health::pool` logs every frame per unit instead of once.
- **Named script calls:** Area17, Gravitas and TTLD call scripts by string and drop `None`, so a
  typo does nothing. Use typed calls, as Parts Needed does, or log the failure.

## 4. Harness and tooling

- **Speed overrides are ignored** ✔. `vf_start_file` looks for lowercase `maxspeed=`, while
  `launch/` spells it `MaxSpeed=`. Headless suites run at 20× instead of 100×, and the 1× runs
  aren't pinned. Fixing it changes test timing, so goldens will need re-recording.
- **A renderer change skips every pixel check and still passes** (`lib/common.sh:726-729`). Even a
  Mesa package bump does it. Fail unless `VF_ALLOW_RENDERER_MISMATCH=1`.
- **Runtime-failure checks miss real failures.**
  - Hunted and the smoke test grep for "Wasm trap"; the engine logs "core Wasm export trapped".
  - `ttld visual` and `gravitas shots` forbid nothing.
  - TTLD's `world state re-entered` check can never fire.
  - Fix: one `vf_forbid_runtime_failures` helper for every suite.
- **`vf_write_settings` writes a file the engine never reads** (`--config` replaces it), so Gravitas'
  test settings don't apply.
- **MyCube and Parts Needed use inline start scripts** instead of `launch/`, so the layout players
  get has no assertion suite.
- **Checks that exist but aren't run:**
  - host tests (the crate, Flove, Parts Needed, TTLD, Hunted);
  - `ttld pose-parity`;
  - "installed module = source", which runs only for Area17;
  - Flove's `animation-trace` build;
  - hover arms and idle in the unit-script comparison.
- **Visual runs end on their timeout** instead of a marker. That costs about 5 min per
  `verify visual`, and turns a hang into a pass.
- **Release:**
  - `BUILDINFO.txt` doesn't record the crate or engine-crate revisions;
  - the test-build guard misses Flove's `test-commands`;
  - the smoke test never starts the shipped graphics profile;
  - the menu's staleness check ignores `game-info/*/README.md`.
- **Parts Needed's restart** reloads a hand-copied `launch/` script (`ui/src/restart.rs`), and
  nothing tests it.
- **Clutter:** about 21 GB (`verification/out` 15 GB in 609 directories, `wasm-backups` 5.7 GB,
  cache, root `*.cwasm`).
- **Stray tracked files:** `Hunted-wasm.sdd/wasm-test/`, `port-reference/` in 3 games, and Flove's
  `verification/animation_trace.sh`.

## 5. Shared crate (`springcabal-rs`)

- **Unpinned git dependency.** A fresh clone without the local `[patch]` builds whatever HEAD is at
  the time. Pin a rev or tag.
- **`Encoder`** doesn't escape `|` or `=`, and writes `NaN`, which the parser drops.
- **`flag("false")` reads as true.**
- **`check::Suite` passes with 0 checks** unless a minimum is set. Area17's visual suite and Parts
  Needed's ending suite set none. Make the minimum a constructor argument.
- **Untested modules:** `check`, `menu`, `music` (rewritten) and `shots`. `Screenshots` checks the
  shot order only with `debug_assert`.
- **`MusicLoop` logs a failure once per call site,** so a second track's failure is never logged.
- **Camera:**
  - `CameraFollow` holds its borrow across `set_camera_state`;
  - `arm_tracker` never retries after a failure;
  - `goal::map_rect` hard-codes the square size.
- **Dead API:** `KeyMoveWidget`, `VelocityDrive`, `ground_under_mouse`.
- **Stale docs:** `message.rs:3` names `send_lua_ui_msg`; a Parts Needed comment still mentions the
  removed `length_hint`.

## 6. Structure and duplication

- **Gravitas' UI** still has global state (`ui/src/state.rs:35`, and `unsafe impl Sync` in
  `fire/distortion.rs`). It uses none of the crate: its music loop, camera, screenshots, Ctrl+Q and
  message parsing are all hand-rolled. The uncommitted fire work blocks this.
- **Copied between games; should move to the crate or the SDK:**
  - `send_to_rules` (6×);
  - `gallery::active()` (7×);
  - per-game warning/`warning_once` helpers (6×; use `log_err`/`log_once!`);
  - `thread_local!` def caches (12×);
  - the unit-script attach gadget (5×), which belongs in `spring-addons`;
  - two ports each of map-edge and fire.
- **Copied between rules and UI within a game.** Parts Needed's `shared` crate is the model to copy.
  - Area17's tech costs, which share the God Gun bug;
  - Flove's stage and event constants;
  - TTLD's `GameEnd`, `STATUS_PERIOD` and `"TTLD_STATUS"`;
  - MyCube's health parsing and status layout.
- **Conventions differ:**
  - addon names are snake_case in Area17 and PascalCase elsewhere;
  - file prefixes differ;
  - `e2e` means three different things;
  - Hunted ships with `diagnostics` on because its tests grep those logs;
  - `attach_existing()` is called in `init` by 4 games and not by the other 3;
  - `integration.rs` is over 500 lines in Flove, Hunted and MyCube.
- **Per-game leftovers:**
  - Area17:
    - dead collision-pairing code (`fall_damage.rs`);
    - `Point3` duplicates `Float3`;
    - unit-def data is copied into Rust tables;
    - every unit builds every script kind's state;
    - the mouse work runs twice;
    - `build.rs` watches a path that doesn't exist.
  - Flove:
    - trees are registered twice;
    - the outline pass reads a rules param per tree on every draw;
    - `target_pos` is never read;
    - an animation-trace leftover in `unit_scripts/mod.rs:212`.
  - Gravitas: `UnitScript::new` and `Script::None` are unreachable.
  - Parts Needed: the piece mask is applied twice (`wisp.rs:162-187`).
  - Hunted: the lighthouse beam is passed through rules params the module itself writes.
  - TTLD:
    - `cast_level` doubles as a duration;
    - mage shots go through public rules params;
    - raw `KEY_1`/`KEY_5`.
  - MyCube: an unused `e2e` feature in rules.

## 7. Decisions for the user

- **TTLD's Lua checkout (`ToTheLastDrop.sdd`) has 22 uncommitted edits,** including a new
  `GameData/weapondefs_post.lua` and the Poultice flip. `lua-visual` and `pose-parity` compare
  against this modified copy. Are those edits wanted? And should Poultice pull, as the jam game
  does?
- **`CusHost::game_frame`** would wake unit scripts on Lua's schedule. It is optional, and would
  move the anim goldens.
- **Gravitas' fire work** is uncommitted and blocks §6's Gravitas UI items and the Gravitas anim
  goldens.
- **Deleting the ~21 GB of clutter.**
