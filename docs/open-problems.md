# Open problems in the WASM ports

What's still wrong in the seven ports, the shared crate and the harness. Nothing fixed is listed;
git history has the reviews and fixes. Delete an entry when it's fixed.

A port matches its Lua original's gameplay but keeps its own improvements. Those are listed in each
game's README under "Improvements over the Lua version", and aren't problems.

Paths are relative to `spring-linux/games/<Game>-wasm.sdd/wasm-src/` unless stated otherwise.

## Waiting on the engine

These are filed in `spring-bar/WASM_GAME_API_TODO_2026-09-25.md`:
- **§5: the unit-script attach gadget is copied 7×.** It belongs in `spring-addons`.
- **§8: there is no typed getter for a game rules param.** So MyCube's test handshake and Flove's
  status ride on a carrier unit.

Hunted now reads pellet count and spread through the SDK query added in `spring-bar` `c77a8b7054`; the old §4 gap is resolved.

## Gameplay

- **Gravitas: aiming beyond the gun's range differs from Lua.** The port clamps a target beyond the gun's range in 2D, to the ground, and refuses a crate just out of range, where the Lua game aims at the furthest point in range towards it. This is the remaining failure in `verify gravitas play`, which stays out of `verify all` until fixed. Repeated Space jumps, E, middle-button jumping and subsequent push/pull now pass on the current checkout.
- **Gravitas: the combined rules scenario still fails collision damage and existing B.O.B firing.** `verify gravitas rules` reports 7 collision damage where Lua reports 266, and zero B.O.B shots where Lua now reports 107 in 11 seconds. The focused `bob` / `lua-bob` checks both pass at 100 shots in each 10-second window with a maximum three-frame gap. Lua’s artificial five-second B.O.B cooldown is fixed; the combined WASM scenario remains unresolved and stays outside `verify all`.

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

## Area17 HUD rendering

Reproduce with `./verification/verify area17 visual`. The e2e scenario opens the technology panel at frame 30; frame 80 should show it together with the resources, health/shield and loadout HUD. The captured frames 20, 80 and 450 instead show only the world. The existing goldens also lack the HUD, so their passing comparisons do not verify HUD pixels.

The run uses normal UI setup: no gallery option, hide-interface command or scenario-owned HUD suppression. Logs confirm HUD initialization and its render callback; the native bindings test checks visible tooltip text, indexed hover, close/reopen and mouse-leave, and the technology toggle/weapon/ability callbacks pass. There are no RML texture errors in the rendered run. The cause of the missing pixels is not established; rendering state and the RML draw path need inspection. Evidence: `codex-work/wasm-structure-evidence/area17-final-visual/`.
