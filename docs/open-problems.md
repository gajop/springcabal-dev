# Open problems in the WASM ports

What's still wrong in the seven ports, the shared crate and the harness. Nothing fixed is listed;
git history has the reviews and fixes. Delete an entry when it's fixed.

A port matches its Lua original's gameplay but keeps its own improvements. Those are listed in each
game's README under "Improvements over the Lua version", and aren't problems.

Paths are relative to `spring-linux/games/<Game>-wasm.sdd/wasm-src/` unless stated otherwise.

## Games

- **Hunted: the end screen lacks Lua's "Kills: N" line.** (In progress.)
- **Hunted: rabbit speed has a floor of 0.25 with no recorded reason,** in `ai/src/mood.rs:30`.
  Check it against `rabbit_ai.lua`. (In progress.)
- **Flove: the big mushroom's muzzle turns 0.42 rad differently from Lua's in attack shots**
  (`gallery parity flove`). Turn acceleration was ruled out. (In progress.)

## Waiting on the engine

These are filed in `spring-bar/WASM_GAME_API_TODO_2026-09-25.md`:
- **§4, Hunted's pellet count and spray are hard-coded:** `WeaponDefInfo` has no `projectiles` or
  `sprayAngle`.
- **§7, scripts resume one frame late after a blocking `Wait*`:** the SDK resumes them on the frame
  after `AnimFinished`, while Lua resumes them inside it. Hunted's rabbit hop is 0.5 elmos off Lua's
  in the parity gallery because of it, and it applies to every game.
- **§5, the unit-script attach gadget is copied 7×:** it belongs in `spring-addons`.
- **§8, no typed getter for a game rules param:** so MyCube's test handshake and Flove's status
  ride on a carrier unit.

## Checks

- **CEG gallery captures flake on engine particle noise,** now and then; rerun once before
  concluding. BASELINE.md lists the captures seen failing.
- **Parts Needed's visual shots 3–4 can fail "camera not settled"** on a heavily loaded machine
  (load average about 45); a rerun passes.
- **The whole `verify visual` wasn't rerun after the last Flove anim re-record,** though
  `gallery anim flove` passed twice after it. The next full run covers it.
