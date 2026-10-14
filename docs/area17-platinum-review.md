# Area 17 Lua review

The user approved all five Lua groups. `master` is active in
`spring-linux/games/Area-17.sdd`, with exactly five commits above upstream
`1a8581e`:

1. `1895b7f` — Current-engine API/library compatibility, definitions, sounds and archive metadata.
2. `291de73` — Direct controls, UFO camera, RTS-order blocking, menu return, command-color restoration and end-screen lifecycle.
3. `2b95cc8` — Projectile lighting, shadows, transparent beam rendering and beam lifetime safeguards.
4. `d077e08` — One scream per lift, repeatable human floating, missing-script guards and the tank turret's correct aim wait axis.
5. `aa6b8d7` — Slope projection/rebound, point-defense reload formula, haste preserving upgrades and effects after successful purchases.

The final Lua files match the preceding reviewed version except for three
explicit `buildTime = 100` declarations. The engine already defaults to build
time 100. The cricket recording is retained: removing it produced a missing-audio
error, proving that the bundled Ambient Player loads it. Its earlier exclusion
was corrected and explained to the user.
No further gameplay changes were introduced during regrouping.
The intermediate version without the ambient asset is preserved at
`refs/backups/area17/five-commit-review-before-ambient-fix`.

## Preservation

- Original Lua `master`: `5f45c43`, saved as `refs/backups/area17/pre-platinum-lua`.
- Original working files: `1c4cff7`, saved as `refs/backups/area17/pre-platinum-working-tree`, and in the original Lua stash.
- The 44-commit audit history remains at `refs/backups/area17/before-11-commit-review`.
- The 11-commit review history remains at `refs/backups/area17/before-approved-five-commit-review`.
- The exact approved cleanup tree is saved as `refs/backups/area17/approved-cleanup-snapshot`.
- Cricket audio is also copied to `codex-work/area17-review/preserved-assets/cricket1.ogg`.
- Approval status and per-commit patches are in `codex-work/area17-review/`.

`TODO.md` was not edited. Nothing was pushed.

## Validation

- 125 game-owned Lua files pass `luac -p`.
- All 11 callback regression cases pass. The starting working tree fails each case.
- The focused engine probe covers upgrades, movement, RTS-order blocking,
  death/respawn, queen capture and the victory UI. Tests stage their added
  scripts outside the game checkout. The latest run passed with zero errors
  and zero warnings. Results are in
  `verification/out/area17-lua-platinum/`.

This is a focused Linux review, with the known gallery-fixture issues remaining
in `docs/open-problems.md`. Ratings in `TODO.md` remain for the user to manage.

## WASM: deferred

The user explicitly requested Lua completion before further WASM work.
`Area17-wasm.sdd` remains on `rust`; its files and installed modules were left unchanged during this
five-commit regrouping. The existing WASM commits were previously verified,
but still sit above the earlier Lua history. When the user resumes WASM work,
review them and rebuild exactly two commits directly above the finalized Lua
history: gameplay/UI with unchanged Lua scripts, then Core-CUS unit scripts.
Original WASM `2ce7c7e` remains at `refs/backups/area17/pre-platinum-wasm`; old installed
modules remain in `codex-work/area17-pre-platinum-installed/`.

Branch-name correction: the approved Lua tip is on `master`, and the current
WASM tip is on `rust`. No file contents changed during this
correction. All added review branch names were removed; their commit references
remain under `refs/backups/area17/`. Further work stays on the user's existing
branches unless the user explicitly requests another branch.
