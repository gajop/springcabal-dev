TODO:

1. [x] Make backups of all WASM dirs (complete pre-change copies are in `wasm-backups/20260903-020053/`).
2. [x] Make each existing WASM directory a Git working tree based on its original Lua game, without deleting or restoring files. Each port now tracks the original upstream history; Hunted's existing matching repository was retained.
   - Re-checked: the history and remote were right in all seven, but six of them
     had an emptied index (the `git rm -r --cached .` signature), so every
     original file was staged as deleted and the game content read as untracked.
     `git diff` was therefore useless and the ports did not sit "on top of" the
     original in any usable sense.  Only Hunted, which was retained rather than
     recreated, was correct.
   - Repaired with a plain `git reset` (index only, no commit) in the six.
     Verified byte-identical working trees before/after via checksum, and every
     repo now has index == HEAD tree with 0 staged deletions.  Each port now
     shows a meaningful diff: modified originals, deleted Lua widgets/gadgets
     that the WASM modules replaced, and untracked new files (wasm-src etc.).

In general I will do review for one game, but all of this applies to Area17 and all other games.
See if other games have other issues.

Area17 (WASM):

1. [x] remove unnecessary rules-unsynced (removed the empty scaffold, stale artifact, workspace/copy/verification references; `just copy` and static verification pass)
2. consider making volumes.rs a standalone, reusable crate, as most games/tools will want something like this
3. decouple into smaller files, generally no more than 300 LOC per file, at most 500, follow SRP, stuff like rmlui.rs seems crazy
4. These kind of blocks are scattered throughtout the code. This is just silly , the diagnostic feature can compile it out, we shouldn't compiling it out at the call site..
```rs
#[cfg(feature = "diagnostics")]
        crate::diagnostics::info("Area 17 RmlUi callback: cheat resources");
```
5. These GL constants belong in the engine.
const GL_TRIANGLE_STRIP: u32 = 0x0005;
const GL_GREATER: u32 = 0x0204;
6. [x] configure project-root IDE support for Area17, Hunted, Parts Needed, and MyCube (`.vscode/settings.json` links `wasm-src/Cargo.toml` with the WASM target; each workspace has `.cargo/config.toml`; release WASM Cargo checks pass for all four).

cannot find function `depth_test` in crate `spring`
not found in `spring`rustcClick for full compiler diagnostic
7. I wonder why you're sending data like this.. is it really necessary? surely we should have a ::play_sound_file() overload that doesn't require to specify ::default() twice and a 0 , which seems like meaningless data. In the native interface there is this concept of Opts struct with ::default(). It's something to consider (or alternative approach..), coz these args are bad and very hard to understand.
```rs
    let _ = spring::sound::play_sound_file(
        file,
        volume,
        spring::Float3::default(),
        spring::Float3::default(),
        0,
    );
```
8. generate_scenario_data is a terrible idea. You should convert the .lua to json or rust, and embed it in rust itself. We shouldn't be parsing lua at build time (?). I wonder if this build.rs is the reason why my IDE can't tell half the types (?), .cargo/config.toml might be more sensible, no? With this the whole build.rs might go away..
9. [x] make the WASM workspace READMEs concise and list the `just` commands for Area17, Hunted, Parts Needed, and MyCube (manual Cargo/copy instructions and long implementation notes removed).
10. [x] remove UI `is_headless()` checks from Area17, Hunted, Parts Needed, and MyCube (the UI modules now assume the engine does not load UI callins in headless mode, matching LuaUI).
11. stuff like spring::types::UnitHealthValue should have defaults so you don't need to specify capture, paralyze, build, use_amounts lol..
```
    spring::set_unit_health(
        unit_id,
        spring::types::UnitHealthValue {
            health: health.clamp(0.0, max_health),
            capture: 0.0,
            paralyze: 0.0,
            build: 1.0,
            use_amounts: false,
        },
    )
```
12. this thing in callins.rs invoking a bunch of "update()" seems super wrong. it really should be invoking game_frame, coz it's a game_frame event! it makes sense to use consistent naming for events so we KNOW what event it is, update() has a TOTALLY different meaning in spring, corresponding to the Update callin.
```rs
pub fn game_frame(frame: i32) {
    let pending_messages = state::take_pending_messages();
    state::with_game(|game| {
```

Gravitas / To the Last Drop / Flove (WASM) -- same checklist, tracked separately
because the [x] marks above cover only Area17, Hunted, Parts Needed and MyCube:

1. [ ] rules-unsynced: Gravitas and TTLD have none.  Flove's is real (a 693-line
       unit-outline post-process) and is in its manifest, so it is not dead
       scaffolding -- but it is a drawing concern that belongs in `ui`, and it
       is the reason Flove spams "failed to use GLSL shader" every frame under
       headless (LuaRules-unsynced *does* load there, unlike LuaUI).  Folding it
       into `ui` is the fix; blocked on Flove having a validation harness.
       Fixed already: Flove's justfile never rebuilt or copied that module, so
       the shipped .wasm was stale.
2. n/a  none of the three has a volumes.rs.
3. [ ] files over 300 LOC: Gravitas 2, TTLD 4, Flove 6.
4. [x] no `#[cfg(feature = "diagnostics")]` call sites in any of the three.
5. [ ] GL constants still declared per-game: Gravitas 6, TTLD 12, Flove 13.
6. [x] `.vscode/settings.json` + `wasm-src/.cargo/config.toml` for all three; a
       bare `cargo check` (no --target) now succeeds in each workspace.
7. [ ] play_sound_file Opts-style overload -- engine SDK change.
8. n/a  no generate_scenario_data; each build.rs is four lines of link args.
9. [x] concise README.md in each of the three wasm-src workspaces.
10. [x] UI is_headless() checks removed from all three.  Confirmed empirically
       first (a probe in TTLD's ui update never fired under spring-headless):
       the ui environment is not loaded in headless, matching LuaUI, so every
       one of those branches was dead.  Gravitas's dead branch was also keeping
       `input::poll_scripted` alive, which `poll()` already covers.
11. [ ] Default impls for spring::types::* -- engine SDK change.
12. [ ] update() -> game_frame rename -- not yet audited for these three.

Validation status -- all three have harnesses and all three are green:
  * TTLD     `wasm-test/verify-ttld.sh`            20 assertions + screenshots
  * Flove    `gemini-work/flove-test/verify.sh`    54 rules + 14 scenario
  * Gravitas `claude-work/gravitas-test/e2e.sh`    10 cases + build/log checks

Engine: the `ui` world is now disabled in a headless build (WasmEnvironment.cpp),
matching LuaUI, and a manifest that lists a UI module skips it there rather than
failing.  Guests no longer need is_headless() guards.  Fallout fixed with it:
  * Flove's ui integration suite is headless-only dead code now; its 2 checks
    have to move to the visual runner.
  * Gravitas's e2e drove player input through the ui module (synced ->
    GRAVITAS_SHOT -> ui -> "gravitas|..." -> synced).  It now builds the same
    PlayerCommand directly in the synced harness, re-issued per frame the way
    the ui poll did, with the jump goal at ground height (a zero height was
    refused as TooHigh).

Bugs found and fixed while validating:
  * Flove tree assertions expected >= 8 trees / >= 24 power, but the spawn table
    defines 7 "base" points; now derived from the table.
  * Flove's Lua scenario looked for a mushroom at frame 5, before any wave has
    spawned one; it now spawns one, as step 7 already did for the boss.
  * `gemini-work/flove-test/verify.sh` grepped for "ALL FLOVE TEST ASSERTIONS
    PASSED" while the gadget prints "ALL FLOVE EXTENDED TEST ASSERTIONS PASSED",
    so success was unreachable; it also now counts failed assertions directly.
  * Flove's justfile never rebuilt or copied rules-unsynced, shipping a stale
    .wasm.

-- TODO: Deeper consideration

1. spring::context_process_mouse_button_up <- what on earth is this? first time seeing this

2. lib.rs takes this approach to register callins. This is quite unintuitive for devs I think, but further more, callins.rs is a mess, it ends up invoking each subsystem. in reality, these subsystems should automatically declare callins they need (perhaps with priority). We need something like a widget/gadget handler to keep things modular.


spring::export_callin_scratch!(4096);
spring::export_update!(callins::update);
spring::export_recv_from_synced!(callins::recv_from_synced);
spring::export_mouse_move!(callins::mouse_move);
spring::export_mouse_press!(callins::mouse_press);
spring::export_mouse_release!(callins::mouse_release);
spring::export_key_press!(callins::key_press);
spring::export_key_release!(callins::key_release);
spring::export_draw_world!(callins::draw_world);
spring::export_draw_screen!(callins::draw_screen);
spring::export_environment_mask!(spring::ui::ENVIRONMENT_MASK);
spring::export_callback_dispatch!(callbacks::dispatch);




-- TODO (old)

1. Gravitas: BROKEN
   - Most objects are not interactable
2. Hunted: Bronze
   - Works if you disable shadows
   - Tested very briefly
3. Area17: ?
4. Flove: Silver
   - Game is playable
   - Problems:
     - Various errors with projectiles (deferred rendering and unit_spire_controller)
     - No unitDefId spam
     - Error: Failed to load: api_custom_unit_shaders.lua
     - Some units aren't shooting
     - Some units seem like they're in the ground
5. Parts Needed: WIP — Rust rules/UI are running; 23 integration assertions and
   five graphical progression screenshots pass. Core body-form, pickup,
   movement, valid/invalid lever authorization, plate/cage rescue links, ending, authored prompt, direct-control input
   (selection/HUD suppression), camera tracking, and the original
   vignette/blue/noise screen treatment are implemented. The retained Lua wisp
   script owns its original animation while Core applies the exact collected
   part mask; the authored form-transition timing and positional ambient audio
   are also restored. Continue visual parity/manual gameplay audit.
6. My Cube: WIP — Rust rules/UI are running; 17 integration assertions and
   five graphical screenshots pass, including a paced run through every
   authored storyteller wave and terminal state with no Core-WASM diagnostics.
   Drill terrain work, movement searches, and late-wave unit bookkeeping are
   bounded across frames rather than exhausting the host-call budget. The
   initial expedition is asserted to spawn on terrain safely above the supplied
   map's water plane, and direct clicks no longer fall through to RTS selection.
   The original story events and their line breaks are now forwarded to the
   floating-text UI rather than replaced by a port-authored instruction line.
   Continue visual parity/manual gameplay audit.
7. To the Last Drop: Silver (WASM port)
	- Map renders again: LD43-map shipped a Spring-2018 SMFFragProg.glsl override
	  that no longer compiles, so the terrain was invisible.  Removed, along with
	  the missing cleardesert.dds skybox and the bogus splatDetailTex.
	- Orks attack again: the synced module spawned waves while its world state
	  was borrowed, so the UnitCreated call-in was skipped and no ork was ever
	  registered with the AI or given orders.
	- The player can attack again: the mage's script blocked every shot because
	  the port never published the fire target the Lua build kept in GG.fireTx.
	- Def/CEG/icon warnings are gone; `wasm-test/verify-ttld.sh headless` asserts
	  the gameplay and `... visual` captures screenshots.
	- Three engine defects the port had been working around are fixed in
	  spring-bar (the earlier "dangling decoded string" diagnosis here was
	  wrong; the storage was always function-scoped):
	    * GetUnitWeaponState reported `weaponDef->reload` instead of the live
	      `weapon->reloadTime`, so every SetUnitWeaponState looked like it was
	      ignored.  Now reports the live value in seconds, as Lua does.
	    * RulesParamValue was a real C union, but the codegen model cannot
	      express one, so the generated decoder filled all three members in turn
	      and the trailing stringValue pointer clobbered floatValue.  The struct
	      is now plain (native API 1.8.0 -> 1.9.0).
	    * Variable-io/dynamic-output host bindings read string inputs as raw
	      bytes while the guest sends them length-prefixed, so every lookup
	      keyed on the string missed.  Fixed in the shared wire renderer and in
	      the 70 generated sites.
	  Verified: native_api_parity wasm mode goes 22 -> 17 mismatches with no
	  regressions; the five fixed are decode_base64, decode_base64_url and the
	  unit/feature/weapon def custom-param reads.
	- With those fixed, api_unit_script_support.lua drops from ~176 lines to the
	  two things Lua genuinely has to do (cross-boundary sound, and the
	  GG.Attributes entry point the unit scripts call).  Draw scales and reload
	  modulation now go straight through the engine callouts, and the
	  integration assertions test those instead of the shim's rules params.
	- Codegen runs again: it had aborted with "callin inventory is missing:
	  CusCallNamed, CusDetach, CusInvoke, CusTick".  Those four are custom unit
	  scripts, which reach a guest through the hand-written SPRING_CUS_* exports
	  and a shared scratch buffer rather than the generated callin wire, so the
	  inventory check was simply over-strict.  Callins.def gained a NATIVE(name)
	  entry kind for exactly that case and lists the four.  `verify_codegen.py`
	  now reports the artifacts reproducible and up to date, and regenerating
	  reproduces the two edited binding files byte for byte.


Terminology:
- Gold: works with no issues
- Silver: playable but with large issues
- Bronze: playable with some large issues or complex workarounds
- Broken: doesn't work no matter what you do
