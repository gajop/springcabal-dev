# Review 3: consistency across the seven `wasm-src` trees

Paths are relative to `spring-linux/games/<Game>-wasm.sdd/wasm-src/`. The game HEADs reviewed are
Area17 `6a873f5`, Flove `0280dfe`, Gravitas `32f6ad1` (plus its uncommitted fire WIP), Hunted
`3e0665c`, MyCube `8063a04`, PartsNeeded `421ecbc` and TTLD `d0fe137`.

## Grade: B− (not graded in round 2)

The common structure is there in every game:
- `rules-synced` + `ui`, gadgets and widgets over a `Global`;
- the engine's `CusHost` with SDK deferral;
- the springcabal crate for messages and tests.

Round 5 made unit-script hosting nearly uniform. Consistency stops at that skeleton:
- file, feature and addon naming follow three or four conventions;
- rules↔UI shared code uses four different mechanisms;
- each game rewrites the same ~10 helpers;
- CLAUDE.md's `let _ =` rule is still broken on gameplay calls, mostly in Gravitas;
- no game uses the SDK's `ResultExt` logging.

## Round-2 cross-game themes, status now

| Round-2 theme | Status |
|---|---|
| The shared crate is adopted unevenly | **Partly.** Six UIs are on it. Gravitas' UI still isn't (see crate.md). |
| Every UI has its own `send_lua_rules_msg` wrapper | **Open**: 6 wrappers (crate.md D1). |
| Rules/UI constants copied (Area17 tech costs, Flove stages, TTLD `GameEnd`/`STATUS_PERIOD`) | **Open.** See S4. |
| No global state left except Gravitas' UI fire WIP | **Holds**, see S7. |

## Findings (most severe first)

### S1. `let _ =` still hides failures that break gameplay (silent failures)

- **Counts.**

  | Area17 | Flove | Gravitas | Hunted | MyCube | PartsNeeded | TTLD | Total |
  |---|---|---|---|---|---|---|---|
  | 109 | 140 | 189 | 76 | 71 | 210 | 272 | 1,067 |

  Most of these are GL state calls (`use_shader`, `bind_texture`, `matrix_mode`…), where ignoring
  the result is fine. The calls below are the ones CLAUDE.md names: orders, damage and destruction,
  script-facing messages.
- **Gravitas (the worst):**
  - `rules-synced/src/restart.rs:8` `destroy_unit` (restart can leave the old units behind);
  - `respawn.rs:135` `destroy_unit`;
  - `effects.rs:61` `add_unit_damage`, `:90` `destroy_unit`, `:134` `send_to_unsynced` (the fire/fx
    feed for the UI);
  - `gadgets/electrafi.rs:44` and `gadgets/fire.rs:41` `add_unit_damage` (the hazards' damage);
  - `mission.rs:94` `send_to_unsynced`, `:152` `set_unit_health`;
  - `jump.rs:192` `set_unit_position` (the jump flight itself);
  - `impulse.rs:80` `add_unit_impulse`.
- **Area17:**
  - `rules-synced/src/drones.rs:108` `give_order_to_unit` (drone orders), `:65` `send_to_unsynced`;
  - `fall_damage.rs:319` and `weapons.rs:222` `add_unit_damage`;
  - `abduction.rs:95` `send_to_unsynced` (the capture event for the UI).
- **The others:**
  - Hunted `weapons.rs:149` `send_to_unsynced`;
  - Flove `story.rs:176` `set_unit_health`;
  - Parts Needed `level/mod.rs:104,118` and `gadgets/collisions.rs:20` `set_unit_position`.
- **Consequence.** These are the same class of bug as the `call_unit_script` ApiError that hid
  jumps and piece masks for months: a failing engine call is invisible.
- **The fix is cheap now.** `spring::ResultExt::{log_err, log_err_once}` exists
  (`spring/src/result_ext.rs:16-24`), and the crate already uses it. Yet **no game uses it**:
  0 `ResultExt`, 0 `log_err` in all seven trees. Replace the gameplay `let _ =` calls with
  `.log_err("…")`, and add a grep to the static check (tooling.md T6) that forbids `let _ =` on
  those calls.

### S2. Named script calls go through strings, and three games drop the result (silent failures)
- **What's wrong.** The rules and the scripts share one crate, yet rules code calls script functions
  by name through `CusHost::call`:
  - Area17 `cus_scripts/module.rs:44-48` (`"Abduction_float"`, `"Alien_land"`);
  - Gravitas `unit_scripts/module.rs:38-42` via `jump.rs:170,196,203` (`"PreJump"`,
    `"StopJump"`…);
  - TTLD `unit_scripts/module.rs:46-54` (`"CastAnimation"`, `"Buff"`, `"Stun"`);
  - Hunted `cus/mod.rs:30-42` with the string table in `unit_scripts.rs`.
- **Consequence.** `call` returns `None` when the unit has no such function. Area17, Gravitas and
  TTLD discard that, so a typo or a renamed function no-ops silently. That is exactly how Gravitas'
  jumps were lost before. Only Hunted logs it.
- **Fix:**
  - Use typed calls, as Parts Needed already does (`unit_scripts/module.rs:28-37`,
    `host.with_script(unit, |ctx, s| s.set_piece_mask(ctx, …))`).
  - Keep name dispatch only for the engine's own callins.
  - At minimum, log `None` in every game, as Hunted does.

### S3. The unit-script hosting boilerplate is copied seven times, with small differences (structure)
- **Near-identical code:**
  - `impl UnitDefScript` (`capabilities` = `script_kind_for_def(def).map(capabilities)`, `for_def`
    = `for_kind`);
  - an `attach(unit, def)` wrapper;
  - a ~30-line `UnitScriptsGadget` in `gadgets/unit_scripts.rs` (Area17, Flove, MyCube,
    PartsNeeded, TTLD). Gravitas does it in `gadgets/unit_setup.rs:19,30`, Hunted in
    `gadgets/roster.rs:50`.
- **Where they differ:**
  - Directory names: `cus_scripts/` (Area17), `cus/` plus a separate `unit_scripts.rs` for the call
    table (Hunted), `unit_scripts/` (the rest).
  - `attach_existing()` in `init`: Area17, Gravitas, Parts Needed and TTLD call it; Flove, Hunted
    and MyCube don't. The stated reason ("units that outlived a rules restart", e.g. Area17
    `gadgets/unit_scripts.rs:21`, TTLD `:17`) no longer holds: springcabal-rs `416a90e` notes that
    `luarules reload` doesn't reload Wasm rules modules. Either the call is needed for units created
    before the gadget's init, and all seven games need it, or it is dead.
  - Gadget names: `"unit_scripts"` (Area17), `"UnitScripts"` (the rest).
- **Fix:** a generic `spring_addons::cus::AttachScripts` gadget (it needs only the macro-generated
  `with_cus_module_or_defer`). Then one `script_kind_for_def`/`for_kind` convention, and one
  directory name (`unit_scripts/`).

### S4. Four ways to share code between rules and UI, and three games still copy (structure, duplication)
- **The four mechanisms:**
  - Parts Needed: a `shared/` crate (`partsneeded-shared`, with host tests);
  - Hunted: the `ai/` crate, which also holds the protocol (`ai/src/protocol.rs`);
  - MyCube: `common/*.rs`, pulled into both crates with `#[path = "../../common/…"]`
    (`rules-synced/src/lib.rs:9,14,21`, `ui/src/lib.rs:4,6,11`);
  - Area17, Flove and TTLD: nothing, so they copy.
- **What is copied:**
  - Flove: `STAGE_*`, `SHROOM_EVENT_*`, `PLAYER_TEAM_ID` in both rules and UI (7 duplicated
    constants).
  - TTLD: `enum GameEnd` (`rules-synced/src/state.rs:88`, `ui/src/state.rs:24`),
    `STATUS_PERIOD = 6` (`rules-synced/src/gadgets/status.rs:17`, `ui/src/game.rs:5`) and the
    `"TTLD_STATUS"` literal (`rules-synced/src/gadgets/status.rs:88` vs
    `ui/src/widgets/api_sync.rs:6`).
  - Area17: the tech cost formulas (`ui/src/rml/tech_data.rs:150-164` vs
    `rules-synced/src/upgrades.rs:331-342`).
- **Consequence.** A change on one side silently desyncs the HUD, e.g. Area17's UI can show a price
  the rules don't charge.
- **Fix:** adopt Parts Needed's model everywhere, a `<game>-shared` crate with host tests.

### S5. Naming conventions diverge (structure)
- **Addon `name()`s.** Area17 uses Lua-style snake_case with prefixes (`"unit_setup"`,
  `"dbg_integration"`, `"api_status"`). Five games use PascalCase (`"GuiHud"`, `"UnitScripts"`).
  Gravitas mixes PascalCase addons with lowercase test-case names. TTLD has `"TTLD Pose Probe"`. The
  crate's own widgets register as `"snd_music"`/`"dbg_screenshots"`, so every widget list mixes the
  styles.
- **Rules gadget files.** Only Area17 uses Lua prefixes (`unit_*`, `game_*`, `api_*`, `dbg_*`); the
  others use bare nouns (`flowers.rs`, `growth.rs`, `score.rs`).
- **UI widget files.** These mostly use `gfx_/gui_/snd_/dbg_`, with exceptions: Hunted
  `widgets/camera.rs`, Parts Needed `camera_follow.rs`, MyCube `scenery.rs`, Gravitas
  `game_clock.rs`, and Area17 `api_sync` next to `gui_*`.
- **Fix:** pick one convention (the Lua prefixes on file names, PascalCase `name()`), write it in
  CLAUDE.md, and rename in one sweep.

### S6. Test layout and feature flags differ per game (tests, structure)
- **Features per crate:**

  | game | rules features | ui features |
  |---|---|---|
  | Area17 | `diagnostics`, `headless-integration`, `visual-integration`, `e2e` (= visual-integration + diagnostics) | `diagnostics`, `e2e` |
  | Flove | `headless-integration` (= `test-commands`), `test-commands`, `animation-trace`, `diagnostics` | `headless-integration` |
  | Gravitas | `e2e` (the in-game cases **and** the screenshot) | `e2e`, `fire-probe` (WIP) |
  | Hunted | **`default = ["diagnostics"]`**, `headless-integration` | **`default = ["diagnostics"]`**, `e2e` |
  | MyCube | `headless-integration`, `e2e` | `e2e`, `headless-integration` |
  | PartsNeeded | `headless-integration`, `unit-script-probe`, `e2e` | `e2e`, `headless-integration`, `unit-script-probe` |
  | TTLD | `headless-integration`, `e2e`, `pose-probe` | `e2e`, `headless-integration` |

- **What `e2e` means.** It is Gravitas' headless assertion suite, the visual scenario in
  MyCube/Parts Needed/TTLD, and Hunted's UI screenshots.
- **Hunted ships diagnostics.** Its release modules have `diagnostics` on by default: periodic
  `info` lines every 300 frames, and a DEBUG status line. The reason is that its headless suite
  requires those log lines (`verification/games/hunted.sh:50,53`), which ties a test to the shipped
  log output.
- **Four screenshot drivers:**
  - Lua gadgets that ship in the archive: Area17 `LuaRules/Gadgets/test_area17_scenario.lua`, Flove
    `test_scenario.lua` (both gated by the `test_mode` modoption);
  - Gravitas' own `GRAVITAS_SHOT` rules→UI protocol;
  - `springcabal::shots::Screenshots` in the other four.
- **Integration code layout:**
  - `integration/` directories: Area17, Parts Needed, TTLD;
  - single files over 500 lines: Flove `integration.rs` 542, Hunted 688, MyCube 510;
  - Gravitas: `tests/` (27 files) with its own harness instead of `check::Suite`.
- **Fix:**
  - Standardise on `headless-integration` for the headless suite and `e2e` for the visual scenario.
    Take Gravitas' cases off `e2e`.
  - Split the three big `integration.rs` files like Parts Needed/TTLD.
  - Move Gravitas' harness onto `check::Suite`.
  - Make Hunted's suite assert through the integration gadget instead of `diagnostics` logs, then
    drop the default.

### S7. Remaining global state (thread_local)
- **Def tables.** The only thread-local state left in committed code is the def tables: 12
  `thread_local! { static DEFS: OnceCell<…> }` copies across the rules and UI crates, plus
  `OnceLock` in Flove (`rules-synced/src/definitions.rs:56`, `ui/src/defs.rs:11`) and Parts
  Needed's `COLLISIONS` (`rules-synced/src/defs.rs:110`). These are written once and fine, but they
  should be one helper (crate.md D4).
- **Hunted diagnostics.** Hunted keeps diagnostics state in thread-locals: the `REPORTED` bitset
  (`rules-synced/src/diagnostics.rs:18`), and `REPORTED`, `LAST_VISIBILITY_LOG_FRAME` and
  `MOUSE_TARGET_TICKS` (`ui/src/diagnostics.rs:39-54`). The SDK's `log_once!`/`log_err_once` make
  the "once" parts unnecessary.
- **Gravitas UI.** It still has a global `STATE: RefCell<UiState>` (`ui/src/state.rs:35-48`, fire
  and clock), whose `with_state` returns `Option` but can only return `Some` or panic. The WIP adds
  `unsafe impl Sync for SharedState` (`ui/src/fire/distortion.rs:33`) and a `probe.rs` of
  thread-local `Cell`s. This is WIP, so judge it when committed. It is the last place where the
  round-1 "no globals" goal doesn't hold.
- **Flove.** `spire.rs:212` `static EYE: OnceLock<i32>` caches a piece index per process. That is
  fine while there is one spire def, but it is hidden state.

### S8. Per-game helpers that duplicate the SDK or crate
- `diagnostics::warning/warn` in six games (crate.md D3).
- `gallery::active()` × 7 (D2).
- `send_to_rules` × 6 (D1).
- Gravitas UI's music, camera, screenshots, Ctrl+Q and hand-split messages.
- TTLD `ui/src/input.rs:153-154` uses raw `KEY_1 = 49`/`KEY_5 = 53`.
- Area17 `build.rs`:
  - it is 152 lines while the other six are an identical 5-line file;
  - `build.rs:9` has `rerun-if-changed=../LuaRules/Configs/spawn.lua`, relative to the package
    (`wasm-src/rules-synced/`), where no such file exists. The file actually read is
    `../../LuaRules/…` (`:15`), so Cargo never tracks the real input;
  - `build.rs:11` `let _ = env::var_os(...)` is dead;
  - the scenario is generated for the UI crate too, which doesn't use it.

### S9. Stray tracked files in game repos (hygiene)
- `Hunted-wasm.sdd/wasm-test/` (game repo root) is tracked in git: an engine write dir with
  `write/cache/ArchiveCache22.lua` and `spring.conf`.
- Three games track `port-reference/`: Area17 668 K, Hunted 4 M, MyCube 532 K.
- Flove tracks `verification/animation_trace.sh`, which sources the dev repo's `lib/common.sh` by
  relative path (tooling.md T6).

`release/package.sh` excludes all of these, so nothing ships. Delete the tracked `wasm-test/`, and
move Flove's probe into `springcabal-games/verification/probes/`.

## Strengths

- The skeleton is the same everywhere:
  - `lib.rs` exports and `export_core_cus!`;
  - `state.rs` with a `Global`;
  - `gadgets/` + `widgets/` with a `setup.rs` or `mod.rs` registry;
  - a `gallery.rs` gallery mode in every UI;
  - a `defs.rs` resolved once;
  - the identical `build.rs` (six games) and the same wasm32 target pin in `.cargo/config.toml`.
- Unit-script hosting has converged on the engine's `CusHost` plus
  `with_cus_module_or_defer`. No game keeps its own deferred queue or double-`Create` guard any
  more.
- Parts Needed is the model: its `shared` crate has host tests, and its CUS calls are typed
  (`set_piece_mask`). The other games should copy both.
- Every game's workspace lints are `warnings = "deny"` + `clippy::all = deny`, and every game
  builds `--release` for wasm32 with the same memory settings.
