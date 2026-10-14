# Area 17 Platinum review

Lua was reviewed before reconstructing WASM. `TODO.md` was not edited.
Both normal game checkouts now use the revised branches; nothing was pushed.

## Preserved starting points

- Lua `master`: `5f45c43`, with its original mixed WIP and archive-ignore commits.
  Also saved as `codex/area17-pre-platinum-lua`.
- Lua working files: snapshot `1c4cff7`, available as
  `codex/area17-pre-platinum-working-tree`, including the untracked cricket
  sound and empty explosion generator. The original edits also remain in the
  Lua repository's stash, named “Original Area 17 Lua edits preserved before
  activating Platinum branch”.
- WASM `area17-wasm-port`: `2ce7c7e`, also saved as
  `codex/area17-pre-platinum-wasm`. Its installed modules were copied to
  `codex-work/area17-pre-platinum-installed/` before rebuilding.
- Intermediate review graphs remain under
  `codex/area17-platinum-before-history-polish` (Lua) and
  `codex/area17-platinum-before-lua-tip-update` (WASM).

The first 30 revised Lua commits reproduce the starting working tree exactly.
The checkpoint tree matches `1c4cff7`: no original edit was discarded. Those
commits separate loader formatting, disabled scenario orders, reload keys,
archive exclusions, engine compatibility, sounds, command-color preservation,
projectile lighting, beam lifetime/rendering, camera follow, end-screen fixes,
unit-definition hygiene, effects, optional lobby logging, library compatibility,
and bloom shader typing. Fixes follow that checkpoint.

## Revised history

- Lua: `codex/area17-platinum-lua`, `f59af26`, 44 focused commits above
  upstream `1a8581e`, checked out at `spring-linux/games/Area-17.sdd`.
- WASM: `codex/area17-platinum-wasm`, `aaed53e`, checked out at
  `spring-linux/games/Area17-wasm.sdd`. Exactly two commits above that Lua tip:
  1. `47898f5`: gameplay/UI, with `Scripts/` byte-for-byte unchanged from Lua.
     `wasm_script_bridge.lua` registers numeric calls outside the scripts;
     the normal Lua loader still owns their creation and scheduling.
  2. `aaed53e`: Core-CUS unit scripts, removing the Lua scripts and temporary
     adapter. Gameplay callers keep the same `script_bridge.rs` interface.

`codex/area17-gameplay-with-lua-scripts` names the first port commit for separate
inspection or execution. Both intermediate versions were built and exercised.
The review worktrees under `codex-work/` remain detached at the reviewed tips.

## Lua fixes

- Restore command colors through the correctly named `Shutdown` callback.
- Rebuild unit materials through gadget methods instead of absent globals.
- Sound and start a human's float animation once per lift; allow later lifts
  after walking or stopping.
- Wait for the tank turret on Z, the axis actually turned by aiming.
- Project impact velocity onto the ground normal and reverse its normal
  component for restitution. The former flat-ground result accelerated a
  downward velocity of 10 to 11; the revised result rebounds upward at 5.
- Keep movement attributes from overwriting upgraded weapon reload times;
  recognize acceleration-only changes.
- Close technology with Escape.
- Divide each point-defense weapon's base reload by the fire-rate multiplier.
  This formula was explicitly selected by the user.
- Block ordinary RTS UI commands while preserving development-mode orders.
  The formation widget's per-unit notification hook is guarded too. Saved
  non-build scenario orders remain disabled as requested.
- Skip delayed animation calls when a unit or script has disappeared.
- Move the volume utility outside the widget scan directory, preserving its
  contents and fixing its include path.
- Apply upgrade effects only after a successful purchase.
- Show “Leaderboard unavailable” when the optional analytics backend is
  absent. Submission hooks remain when the backend exists. This is the stated
  reversible assumption pending a different user preference.

## How WASM incorporates them

Slope rebound and the reload formula are fixed in rules code. The existing
human state machine already resets floating and plays one scream per lift;
Escape already closes technology. The intermediate port executes the revised
Lua scripts directly, including their guards and fixed tank wait.

The Core-CUS tank now alternates its barrels; tank and AA aim tasks wait for
piece turns before reporting readiness. Normal RTS selection is disabled in
WASM. Tank source definitions now match Lua, with the intended slow speed
applied through live movement attributes. The old reduced definitions could
otherwise be reduced a second time when wandering resumed.

The original port's Rust implementation, tests, diagnostics, HUD assets, and
shared-crate integration remain. Definition/library compatibility fixes from
Lua are inherited. The NOWEAPON fallback retains its empty explosion generator
now that Lua supplies that generator, rather than deleting its reference.
Civilian/scientist speed comments from the old port are preserved.

The old port's deliberate exclusions remain: custom Lua unit materials, LUPS
presentation, Chonsole and development commands are outside the active WASM
port. Its RmlUi HUD remains. No additional presentation system was removed.
The game's `original-vs-wasm.md` maps the replaced files to implementations.

## Verification

- All 125 game-owned Lua files pass `luac -p`.
- `lua verification/fixtures/area17/lua_regressions.lua <Lua game>`: 11 pass.
  Every case fails against the preserved starting working tree.
- `./verification/verify probe area17-lua-review`: upgrade effects, direct
  controls, blocked RTS orders, movement, death/respawn, queen capture, and
  victory UI pass with zero errors and warnings. The latest run also includes
  the unavailable leaderboard notice. Tests stage their scripts outside the
  game checkouts. Gameplay and victory screenshots were inspected.
- Both WASM versions pass `area17 headless`: 22 Rust assertions and six Lua
  observer assertions, including actual point-defense reload during haste.
  Four headless-only RmlUi texture warnings remain, as in the existing suite.
- Both versions pass `area17 visual`: input reaches rules, the HUD renders,
  and the crater appears. All three existing goldens pass: the final run is
  0.4%, 4.4%, and 3.8% from them, below the existing 8% tolerance.
- Formatting and release clippy pass. Installed release modules are rebuilt
  for the normal checkout, and `area17 static` verifies them against source.

Logs/screens live in `verification/out/area17-lua-platinum/`,
`verification/out/area17-platinum-gameplay-lua-scripts/`,
`verification/out/area17-headless/` and `verification/out/area17-visual/`.
No goldens were rewritten.

This is a conservative source/history review with focused Linux checks, not
an exhaustive playthrough or a new platform certification. Existing parity
gallery issues in `docs/open-problems.md` were not retested: UFO respawns can
interfere with Lua gallery fixtures, a building is absent from one Lua capture,
and the drone takes off later in WASM. The known engine delay after blocking
CUS animation waits remains. Ratings are left to the user; `TODO.md` is intact.
