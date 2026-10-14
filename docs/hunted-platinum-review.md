# Hunted Platinum review

Lua is being reviewed before WASM. Do not update `TODO.md` as part of this work.
The FX branches are future work and are outside this review.

## Preserved history

- Original Lua: `master`, `d71d869`. Its four commits above `origin/master`
  (`14f5bc9`) remain available, unchanged.
- Original WASM: `hunted-wasm-port`, `a3e379b`, also saved as
  `codex/hunted-pre-platinum-wasm`. Its exact tree including the OSD color fix
  is saved as `codex/hunted-pre-platinum-wasm-with-osd` (`86106eb`). The former
  working change is also in a named stash and
  `codex-work/hunted-osd-before-platinum.patch`.
- Revised Lua: `codex/hunted-platinum-lua`, `fcb7ab7`, checked out at
  `spring-linux/games/Hunted.sdd`: 32 focused commits above upstream.
- Revised WASM: `codex/hunted-platinum-wasm`, `88668b0`, checked out at
  `spring-linux/games/Hunted-wasm.sdd`, with rebuilt release modules installed.

WASM is exactly two commits above the revised Lua tip:

1. `3b768e4`: gameplay/UI port. `git diff fcb7ab7 3b768e4 -- Scripts` is
   empty; the reviewed Lua unit scripts remain unchanged.
2. `88668b0`: CUS unit-script port. Replaces those scripts and the temporary
   named-call adapter with CUS, including the Lua animation fixes.

The preceding draft pair (`4cb2bb6`, `14de903`) is preserved on
`codex/hunted-platinum-wasm-before-lua-ui-fix`. Its first and second trees are
identical to the corresponding final trees; the rebase changed their Lua
ancestor after the leaderboard fix. Existing `master`, `hunted-wasm-port`, and
all FX refs retain their original hashes.

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
| `e3eacbb` | Reset the HUD's kill streak when restarting resets the kill count. |
| `d6d49fd` | Let reload finish during continuous aiming; restore the recoil parent to neutral. |
| `790444b` | Keep the optional external menu shortcut from crashing on an off-map Space-click. |
| `626261f` | Give the idle reset helper an array of pieces and pass the tail speed to `Turn`. |
| `fcb7ab7` | Offer leaderboard controls only with an analytics service; preserve upload hooks and independent Enter-to-restart. |

## Verification

- All 120 game-owned Lua files pass `luac -p` (libraries are not rewritten).
- `lua verification/fixtures/hunted/lua_regressions.lua spring-linux/games/Hunted.sdd`:
  fourteen cases pass, including both analytics availability states and both
  initial cheat states. The earlier twelve-case version reproduced eleven
  failures against the original Lua snapshot.
- `./verification/verify probe hunted-lua-review` runs those cases, then a short
  isolated engine check of drawing, shooting, mine placement, the loss screen,
  and restart with cheats already enabled. Restart restores 100 carrots,
  clears shot/mine counts, and preserves cheats. It passed with zero errors or
  warnings. The original Lua build
  logged rabbit-shader compilation/callback errors and a map-edge shader error.
- Reviewed images: `verification/out/hunted-lua-platinum/screens/screen_lua_1.png`
  (hunt), `screen_lua_2.png` (loss) and `screen_lua_3.png` (restart). This is a
  focused Linux check, not a Windows or full playthrough certification. The
  probe stages its extra scripts outside the game checkout.

Both WASM stages passed all 33 integration assertions and the five-shot visual
suite, including the HUD/end-screen crops, with zero errors or warnings. The
final port also passed all 28 AI unit tests. Stage logs and captures are retained
under `verification/out/hunted-platinum-stages/{lua-unitscripts,cus}/`.

The final Lua/CUS pose gallery compares nine unit types. Eight match exactly;
the rabbit retains the previously documented 0.5-elmo translation difference at
`move f30 BLeg1` (no rotation difference). The current WASM captures also pass
the existing animation goldens: 15 poses match exactly and 15 images are within
tolerance. No golden changes were required.

## Conservative behavior choices

- The optional gait question was unanswered, so the existing zero offset and
  its synced RNG draw remain in both versions. No animation variation was
  introduced. The definite idle reset and tail-speed errors were fixed first
  in Lua, then in CUS.
- The leaderboard question was also unanswered. The proposed conditional
  visibility was implemented: unavailable analytics offers no dead submission
  controls; available analytics retains the name field, submission behavior,
  and event hooks. Both paths are exercised without sending real analytics.

## Carrying Lua fixes into WASM

- Stealing now publishes the correct rabbit's `stealing` flag. Completing a
  theft queues its stop hook before consumption. The existing Rust memory
  model already releases reservations and dropped-carrot ownership.
- The HUD resets streak state when the kill count resets, as the corrected Lua
  HUD does. Its OSD event classes/colors are unchanged from the saved OSD fix.
- CUS aiming leaves reload alive, the recoil parent returns to zero, resting
  pieces reset, and the tail turns at speed 8. Initial lighthouse beam x/z
  coordinates were already correct in CUS.
- Lua shader fixes are retained in the inherited material assets. The WASM
  presentation replaces the Lua shader/menu/command-color widget code paths;
  the removed APIs and absent external-menu hook are not reintroduced.
- The existing native restart and keyboard improvements remain. The Rust
  restart requires no cheat toggles; the Lua fix preserves its original cheat
  state around the legacy reload.

The original gameplay/UI port (`24bb6bf`) changed seven files in `Scripts/`
to provide exports and destruction helpers. Simply replaying the old first two
commits would therefore not meet the requested separation. The reconstructed
first commit instead keeps the agreed Lua scripts unchanged and provides the
adapters outside `Scripts/`. Native named calls, dynamic Lua callin registration,
and numeric unit rules-parameter reads support the verified intermediate version.

Compared with the exact saved pre-reconstruction port tree, the final tree has
only twelve modified files and no added/deleted paths. Those modifications are
the fixes above, a beam-read forwarding helper used by the two-stage split, and
documentation. Existing port improvements, content, and the OSD correction are
preserved. No commits or FX work were dropped.

## Limits of the result

The existing SDK `AnimFinished` scheduling difference remains: a completion
after the frame's scheduler drain resumes the script next frame, where Lua
resumes inside the callback. It explains the one rabbit pose difference above
and is already tracked in `docs/open-problems.md`; no game-specific timing hack
was added. This review verifies the focused Linux scenarios and the requested
history structure. It does not claim exhaustive playtesting or Windows
certification, and does not change the ratings in `TODO.md`.
