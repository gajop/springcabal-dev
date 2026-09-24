# Review 3: shared crate `springcabal-rs` (`springcabal`, `springcabal-control`)

Paths: `springcabal-rs/crates/<crate>/src/…` (HEAD `3187499`). Game paths are
`spring-linux/games/<Game>-wasm.sdd/wasm-src/…`.

## Grade: B− (unchanged from B−)

The crate is smaller and better aligned with the SDK than it was: pointer tracing, key codes,
restart and the music timer went to the engine, the music loop is now correct, and
`springcabal-control` has real users. But none of the six specific API findings from round 2 was
fixed, the dependency is still unpinned, the host tests exist but nothing runs them, and adoption
has gaps. Gravitas' UI still uses none of it. The games also still copy the same ~10 helpers
between themselves.

## Round-2 findings, status now

| Round-2 finding | Status |
|---|---|
| Unpinned git dependency; lockfiles record no source (the path patch takes over) | **Open.** Every game's `Cargo.toml` still has `springcabal = { git = "ssh://…springcabal-rs.git" }` with no `rev`, and the `spring` git deps track `branch = "rust-wip"`. `Flove-wasm.sdd/wasm-src/Cargo.lock` has one `source` line in total. A fresh clone without the `[patch]` builds whatever HEAD is at the time. |
| `Encoder` doesn't escape `\|`/`=`, writes `NaN`, which `Fields::f32` then drops silently | **Open** (`message.rs:150-159`). |
| `flag()` reads "false" as true | **Documented, not fixed** (`message.rs:113-117` now says "any other non-empty value counts as true"). |
| `check::Suite` passes with 0 checks unless `require_at_least` is set | **Open in the API.** All but two suites set it: Area17's visual suite (`rules-synced/src/visual_integration.rs:43`) and Parts Needed's ending suite (`rules-synced/src/integration/ending.rs:23`) don't. |
| `Screenshots` checks ordering only with `debug_assert` | **Open** (`shots.rs:159`). Release test builds skip it. |
| `MusicLoop` logs a failure once, even after `switch` | **Open.** `music.rs:73` uses `log_once!`, which is keyed by call site, so a second track that fails after `switch` is never logged. |
| 4 of 6 modules untested | **Open.** `check`, `menu`, `music` and `shots` are still wasm32-only with no tests. `music.rs` was rewritten in `416a90e` (a state machine over `sound_stream_time`), and its logic is still untested. |
| Docs name `send_lua_ui_msg` | **Open** (`message.rs:3`). The games use `spring::send_to_unsynced` in 15 places and `send_lua_ui_msg` in none. |
| No `send_to_rules`/`send_to_ui` wrappers | **Open**, see D1 below. |
| `MyCube`/`Hunted` rewrite `quit_after` | Fixed: `quit_after` lives in `Screenshots`. |
| Gravitas UI can't take the dependency (WIP `Cargo.toml`) | **Open.** `Gravitas-wasm.sdd/wasm-src/ui/Cargo.toml` still has no `springcabal`/`springcabal-control` dependency. |

## New findings (most severe first)

### Tests and API

1. **Nothing runs the crate's tests.**
   - There are about 23 host tests: `message` 8, `keys` 2, and `control`'s `camera` 4, `goal` 4,
     `hold`, `protocol`, `keyboard`, `velocity`.
   - No `justfile` recipe, verify suite or pre-commit step runs `cargo test` in `springcabal-rs/`.
     `just build-all`/`check-all` only build the games, for wasm32.
   - The repo has no CI.
   - A regression in `Fields`, `SendOnChange` or `Smoother` is caught only if someone remembers to
     run the tests.
   - **Fix:** add `just test-host` (crate and host-testable game crates) and call it from
     `verify all`.

2. **Dead public API.** No game uses these:
   - `KeyMoveWidget` (`keyboard.rs:386-434`);
   - `VelocityDrive` and its `heading` (`velocity.rs`, 103 lines, the whole module);
   - `pointer::ground_under_mouse` (`pointer.rs:185`);
   - `MoveKeys` directly (every user goes through `KeyMovement`).

   Their engine halves (`enable`/`apply`, the widget) have never run.

   **Fix:** delete them until a game needs them, or give each a user.

3. **`check::Suite` should require its minimum.** Make the count a `Suite::new` argument, so a suite
   can't exist without one. The two suites without a minimum (above) show that an opt-in gets missed.

4. **`goal::map_rect` duplicates the SDK** (`goal.rs:219-230`).
   - It hard-codes `SQUARE_SIZE = 8.0` and derives the map size from `get_height_map_size() - 1`.
   - The SDK now has `spring::consts::SQUARE_SIZE_F` and `map_size_elmos()`
     (`spring/src/lib.rs:179-184,355`).
   - `MoveGoal::goal` also turns a failed `get_ground_height` into `y = 0.0` silently
     (`goal.rs:185`).

5. **`CameraFollow::update` holds its `RefCell` borrow across `set_camera_state`**
   (`camera.rs:460-465`: `state.placed = place_camera(...)` inside `borrow_mut`).
   - Today no callin is raised synchronously from there, so the risk is low.
   - It is still the pattern the games were told to avoid.
   - **Fix:** compute, drop the borrow, then call the engine, as the rest of `update` does.

6. **`arm_tracker` never retries** (`camera.rs:476-478,558-560`). `tracked` is set even when
   `spring::track_unit` fails, and the failure is `log_err_once`, so one failure leaves the engine
   tracker off for that unit for good. Set `tracked` only on `Ok(true)`.

7. **Stale caller comment.** `PartsNeeded-wasm.sdd/wasm-src/ui/src/widgets/snd_music.rs:23-24` says
   "the hint is used only when the engine can't report the stream's length", but `length_hint` was
   removed in `416a90e`.

### Adoption: what games still hand-roll that the crate offers

| Crate item | Area17 | Flove | Gravitas | Hunted | MyCube | PartsN | TTLD |
|---|---|---|---|---|---|---|---|
| `check::Suite` | ✓ | ✓ | **own harness** (`rules-synced/src/tests/{harness,record,runner}.rs`) | ✓ | ✓ | ✓ | ✓ |
| `music::MusicLoop` | ✓ | ✓ | **own** `ui/src/music.rs` | ✓ | ✓ | ✓ | ✓ |
| `shots::Screenshots` | Lua gadget | Lua gadget | **own** `ui/src/shots.rs` | ✓ | ✓ | ✓ | ✓ |
| `menu::is_quit_to_menu` | ✓ | ✓ | **own** `ui/src/widgets/gui_input.rs:71,88` | ✓ | ✓ | ✓ | ✓ |
| `message::fields`/`command` | ✓ | ✓ | rules ✓; UI parses with `split('\|')` (`ui/src/shots.rs:98-115`, `ui/src/camera.rs:18-31`) | ✓ | ✓ | ✓ | ✓ |
| `control::camera` | `CameraFollow` | `place_camera` | **own** follow camera (`ui/src/camera.rs`, 143 lines: lead, initial snap) | `CameraPlacement` | `CameraPlacement` | `CameraFollowWidget` | `CameraFollow` |
| `control::goal`/`keyboard` | ✓ | – | `MoveGoal` | `MoveGoal` | – | ✓ | `MoveGoal`, `HoldTarget` |

Gravitas' UI is the one real gap.
- Its `Music` (`ui/src/music.rs:17-37`) is the frame-time counting loop the crate replaced in
  `416a90e`. It reads the stream length once, right after `play_sound_stream`, and never restarts
  a stream the engine dropped.
- Its camera re-implements `Follow::state(..).lead(..).snap_updates(..)`.

This needs its WIP `ui/Cargo.toml` settled first (the fire work). Then the migration is mechanical.

### Duplication between games that should move into the crate (or SDK)

- **D1. `send_to_rules` wrappers, 7 copies.**
  - Copies:
    - `Area17 ui/src/commands.rs:14`;
    - `Flove ui/src/input.rs:17`;
    - `Hunted ui/src/state.rs:73`;
    - `MyCube ui/src/rules.rs:4`;
    - `PartsNeeded ui/src/commands.rs:5`;
    - `TTLD ui/src/input.rs:156`;
    - the crate's own `keyboard::send_direction`.
  - Each logs a failure. They disagree on whether `Ok(false)` counts as sent: only Flove returns the
    bool.
  - **Fix:** add `springcabal::message::{send_to_rules, send_to_ui}` returning `bool`, and log in
    one place.
- **D2. `gallery::active()`, 7 identical copies** (`ui/src/widgets/gallery.rs:14-19` in every
  game).
  - The `gallery mode: <widgets>` log line is a contract with `verification/games/gallery.sh:156`,
    just as `check.rs` owns the assertion-line contract.
  - **Fix:** `springcabal::gallery::{active, announce(&[&str])}`.
- **D3. Per-game logging helpers, 6 games.**
  - The helpers: `diagnostics::warning`/`warn` in Area17, Flove, Gravitas and Hunted, plus Hunted's
    two `warning_once` variants (a bitset in `rules-synced/src/diagnostics.rs:18-34`, a
    `BTreeSet<String>` in `ui/src/diagnostics.rs:39-43`).
  - No game uses `spring::ResultExt::{log_err, log_err_once}` or `log_once!`, which the crate
    itself switched to.
  - This is adoption of the SDK, not new crate code. It would also shrink the games' `let _ =`
    counts (see cross-game.md).
- **D4. `defs::get()` over a `thread_local! { static DEFS: OnceCell<…> }`, 12 copies** (rules and
  UI of most games; Flove uses `OnceLock`).
  - **Fix:** a `springcabal::defs::Lazy<T>` (or a `defs!` macro), so every game builds its def
    tables the same way.
- **D5. The CUS attach boilerplate** belongs in `spring-addons` rather than here, because `CusHost`
  lives there.
  - Five near-identical `UnitScriptsGadget`s (30 lines each).
  - Seven `attach(unit, def)` / `call(unit, name, args)` wrappers.
  - See cross-game.md.
- **D6. Two ports each of `map_edge_extension.lua` and of the LUPS fire.**
  - Map edge: `Gravitas ui/src/mapedge.rs` (grid) and `TTLD ui/src/mapedge.rs` (mirrored,
    shader).
  - Fire: `Gravitas ui/src/fire/*` and `TTLD ui/src/fire/*`.
  - A shared `springcabal-gfx` could hold them. That is only worth it once Gravitas' fire WIP is
    committed, and the two ports are different variants, so the priority is low.

Things that should **not** move into the crate: status payloads, restart logic, game rules. Those
differ in each game.

## Strengths

- The module docs state each wire contract: the assertion line format in `check.rs`, and
  `movement|x|z` in `protocol.rs`.
- Engine-free cores are split from thin wasm32 shells, so the logic can be tested on the host:
  `Smoother`, `MoveGoal::offset`, `Steering`, `HoldTarget`, `SendOnChange`.
- `SendOnChange::send_if` releases its borrow before calling the engine (`message.rs:236`).
- Removals are disciplined. When the SDK gained an equivalent (`pick`, key codes, `reload_rules`,
  `track_unit`, `Float3::heading`), the crate dropped its own version and said why in the commit.
