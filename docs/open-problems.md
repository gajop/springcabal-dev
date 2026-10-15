# Open problems in the WASM ports

What's still wrong in the seven ports, the shared crate and the harness. Nothing fixed is listed;
git history has the reviews and fixes. Delete an entry when it's fixed.

A port matches its Lua original's gameplay but keeps its own improvements. Those are listed in each
game's README under "Improvements over the Lua version", and aren't problems.

Paths are relative to `spring-linux/games/<Game>-wasm.sdd/wasm-src/` unless stated otherwise.

## Waiting on the engine

These are filed in `spring-bar/WASM_GAME_API_TODO_2026-09-25.md`:
- **§4: Hunted's pellet count and spray are hard-coded.** `WeaponDefInfo` has no `projectiles` or
  `sprayAngle`.
- **§5: the unit-script attach gadget is copied 7×.** It belongs in `spring-addons`.
- **§8: there is no typed getter for a game rules param.** So MyCube's test handshake and Flove's
  status ride on a carrier unit.

## Gameplay

- **Gravitas: the player can jump only once, and a middle click breaks aiming.** On
  `gravitas-wasm-port`, `verify gravitas play` fails every jump after the first and every shot after
  a middle-click jump (the engine's mouse-look pins the cursor to the screen centre). Both are fixed
  on the branch `fix-jump-once` (two commits on `6fd2d55`, in the worktree
  `verification/cache/worktrees/games/Gravitas-wasm.sdd`), not merged yet: the main checkout has
  another session's uncommitted edits. With them, only `push-beyond-range` fails: the port clamps
  a target beyond the gun's range in 2D, to the ground, and refuses a crate just out of range,
  where the Lua game aims at the furthest point in range towards it. `gravitas play` stays out of
  `verify all` until both land.
- **Gravitas: collisions and the boss differ from Lua.** `verify gravitas rules`: a robot thrown
  into a crate takes the engine's 7 damage, not the game's ~266 (`lua-rules`); the boss fires no
  shot in 11 s where Lua fires two bursts of five. Out of `verify all` until fixed.

## Parity gallery (report only)

- **Area17's parity run loses its UFO in the Lua capture.** Lua's `unit_spawner.lua` respawns the
  player UFO every 105 frames at the last UFO's spawn point, which is the gallery UFO's. The
  respawned UFO's beam then abducts the gallery UFO, so 259 shots have pieces missing on the Lua
  side. Fixing this means disabling the spawner in gallery runs, which touches every game's gallery.
- **Area17's `building2` is missing in the Lua capture.** Not investigated.
- **Area17's drone takes off about 10 frames later in the port than in Lua.** Its poses match.

## Checks

- **CEG gallery captures sometimes flake on engine particle noise.** Rerun once before concluding.
  BASELINE.md lists the captures seen failing.
- **Parts Needed's visual shots 3–4 can fail "camera not settled" on a heavily loaded machine**
  (load average about 45). A rerun passes.
