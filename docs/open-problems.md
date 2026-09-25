# Open problems in the WASM ports

What's still wrong in the seven ports, the shared crate and the harness. Nothing fixed is listed;
git history has the reviews and fixes. Delete an entry when it's fixed.

Paths are relative to `spring-linux/games/<Game>-wasm.sdd/wasm-src/` unless stated otherwise.

## 1. Games

- **Gravitas: the arena golden can't see robots in the wrong place.** Runs of the same build differ
  by 1.0–2.5%, which is about what a misplaced robot costs. Assert unit positions at the shot frame
  instead.
- **Gravitas: all e2e cases share one arena on a hard-coded frame schedule.** Some cases depend on
  earlier ones finishing first. Fixing this needs a runner rewrite.
- **TTLD: Adrenaline, Heartburn and Poultice are cast directly in the headless suite,** not through
  the input message. Migraine and Transfusion already go through it.
- **Parts Needed: no check covers a lever and the kill plate opening the same cage in one pass.**
  The port handles it; a check would need both scenarios reworked.
- **Hunted: the pellet count and spray are hard-coded,** because the SDK's `WeaponDefInfo` has no
  `projectiles` or `sprayAngle` (engine).
- **Flove: the poison mushroom's poses differ from the Lua original's by 3.2 elmos** (unchanged since
  before round 7).
- **Area17: a human re-lifted by the beam floats again;** Lua only floats on the first lift. This is
  deliberate and in the README.

## 2. Flaky or non-deterministic checks

- **MyCube's headless suite and Gravitas' e2e run at 1x,** not the 100x of the other headless
  suites. They check the UI's messages on fixed frames a few frames after the UI sends them
  (MyCube: buy coal, terrain trade; Gravitas: input, restart, the level case's restart), and at
  100x the UI's round trip takes more frames: MyCube failed every time, Gravitas' level case once
  in three runs. Waiting for each message, as Hunted's gun check now does, would let them run at
  100x.

## 3. Harness and tooling

- **TTLD's suites and the probes use inline start scripts** (TTLD's has three teams, the menu's
  two), so TTLD's headless suite doesn't test the layout players get.
- **The launch scripts' top-level `MaxSpeed`/`MinSpeed` are dead:** the engine reads them only
  from `[modoptions]`. They hold the engine defaults, so players see no difference.
- **Gravitas shots and TTLD's `lua-visual` still accept the timeout** as their end.

## 4. Duplication and conventions across games

- **Copied between games:**
  - the unit-script attach gadget (5×): it belongs in `spring-addons`, filed as
    §5 of `spring-bar/WASM_GAME_API_TODO_2026-09-25.md`;
  - two ports each of map-edge and fire.
- **File prefixes differ** between games (left alone on purpose).
- **`attach_existing()` is called in `init` by 5 games.** No game has units at the
  rules' `init` on a normal start, except Parts Needed (278, including map gates).

## 5. Decisions for the user

- **Hunted doesn't wake its unit scripts on Lua's schedule** (`CusHost::game_frame`). The other six
  do. In Hunted it moved rabbit poses further from the Lua gallery (2 → 4 differing shots, the hop
  included), so its agent reverted it. Keep Hunted as the exception, or investigate why?
