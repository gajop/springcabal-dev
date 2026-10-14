# Hunted Platinum review

Lua is being reviewed before WASM. Do not update `TODO.md` as part of this work.
The FX branches are future work and are outside this review.

## Preserved history

- Original Lua: `master`, `d71d869`. Its four commits above `origin/master`
  (`14f5bc9`) remain available, unchanged.
- Original WASM: `hunted-wasm-port`, `a3e379b`, also saved as
  `codex/hunted-pre-platinum-wasm`. The outstanding OSD color fix remains in
  that checkout; a patch copy is in `codex-work/hunted-osd-before-platinum.patch`.
- Revised Lua: `codex/hunted-platinum-lua`, checked out at
  `spring-linux/games/Hunted.sdd`.

The four local Lua commits were regrouped into 18 focused commits through
`ba28432`. `git diff d71d869 ba28432` is empty: every previous file change is
preserved, including the movement diagnostics, sounds, inactive analytics-stub
deletion, key bindings, script exports, and archive exclusions. New bug fixes
follow those commits.

## Lua fixes so far

| Commit | Fix |
| --- | --- |
| `841b8f9` | Compile the rabbit visibility shader on Mesa; refresh uniform locations when its program changes. |
| `be75504` | Use writable vertex coordinates and explicit float comparisons in map-edge GLSL; use its fallback in both draw passes. |
| `5f9164c` | Rebuild materials through gadget methods rather than nonexistent global functions. |
| `5e0f6b0` | Remove destroyed lighthouses from the flashlight update index. |
| `1156ecc` | Restore command colors through the correctly named `Shutdown` callin. |
| `0061b21` | Set the actual rabbit's stealing parameter, release destroyed-food reservations, and finish theft safely across synchronous destruction callbacks. |
| `d0a648c` | Detach dropped food from its former owner so destroying it cannot clear a newly carried carrot. |
| `a89d864` | Restart with cheats already enabled, and preserve the previous cheat state. |
| `e2a7858` | Register initial lighthouse scare areas at the actual beam's x/z coordinates. |

## Verification

- All 120 game-owned Lua files pass `luac -p` (libraries are not rewritten).
- `lua verification/fixtures/hunted/lua_regressions.lua spring-linux/games/Hunted.sdd`:
  eight cases pass. Against original `master`, seven cases fail and the existing
  cheats-disabled restart case passes.
- A short isolated engine run exercised drawing, shooting, mine placement,
  and the loss screen with zero errors or warnings. The original Lua build
  logged rabbit-shader compilation/callback errors and a map-edge shader error.
- Reviewed images:
  `verification/out/hunted-lua-platinum/run/write/screenshots/lua-1.png` and
  `lua-2.png`. This is a focused Linux check, not a Windows or full playthrough
  certification. The smoke script is `/tmp/hunted-lua-platinum-smoke.sh`.

## Behavior decisions under discussion

- Rabbit gait: `math.random(-0.2, 0.2)` currently produces zero because its
  bounds are integers. Whether to restore the apparent intended variation is
  awaiting the user's choice; the current animation is preserved meanwhile.
- Leaderboard: analytics was disabled upstream, but the end screen still
  offers name submission. Whether to hide unavailable controls or show an
  unavailable notice is awaiting the user's choice. The code and hooks remain.

## Remaining review

- Check the shotgun reload cancellation: `SetPitch` signals the reload thread
  every frame. Its recoil return target also applies `math.rad` to a pitch
  already in radians. Establish intended animation before changing it.
- Check the rabbit idle tail's speed argument and its idle pose reset before
  carrying fixes to CUS. The tail speed is passed to `math.rad`, which ignores
  it; `reseT` loops over an array but receives a table keyed by piece name.
- Review restart/UI state, input handling, and the WASM improvements that should
  also exist in Lua. Keep diagnostics unless a replacement is presented.
- After Lua behavior is agreed, reconstruct WASM directly above that Lua tip
  as exactly two commits: gameplay/UI, then unit scripts. Both intermediate
  versions must work. Preserve the OSD fix and all existing port improvements;
  document how Lua fixes are implemented or already satisfied in the port.

Lua is not yet declared Platinum. No existing history or FX work has been dropped.
