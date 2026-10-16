# Area 17 Lua review

The user approved all five Lua groups. `master` is active in
`spring-linux/games/Area-17.sdd`, with exactly five commits above upstream
`1a8581e`:

1. `1895b7f` — Current-engine API/library compatibility, definitions, sounds and archive metadata.
2. `291de73` — Direct controls, UFO camera, RTS-order blocking, menu return, command-color restoration and end-screen lifecycle.
3. `2b95cc8` — Projectile lighting, shadows, transparent beam rendering and beam lifetime safeguards.
4. `91c81f0` — One scream per lift, repeatable human floating, missing-script guards and the tank turret's correct aim wait axis, and clearing active abilities on UFO death while retaining cooldowns.
5. `e9d9410` — Slope projection/rebound, point-defense reload formula, haste preserving upgrades and effects after successful purchases.

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
- All 12 callback regression cases pass, including ability cancellation on UFO death.
- The focused engine probe covers upgrades, movement, RTS-order blocking,
  death/respawn, queen capture and the victory UI. Tests stage their added
  scripts outside the game checkout. The latest run passed with zero errors
  and zero warnings. Results are in
  `verification/out/area17-lua-platinum/`.

This is a focused Linux review, with the known gallery-fixture issues remaining
in `docs/open-problems.md`. Ratings in `TODO.md` remain for the user to manage.

## WASM history aligned

The user resumed WASM work after approving Lua. In `Area17-wasm.sdd`, `master`
is now the exact approved Lua tip `e9d9410`; the active `rust` branch adds exactly
two commits:

1. `004b4a9` — Gameplay/UI, keeping `Scripts/` byte-for-byte identical to Lua.
2. `c390826` — Core-CUS unit scripts.

`rust` therefore has five Lua commits plus two WASM commits above upstream.
It no longer inherits the obsolete 11-commit Lua grouping. The initial regrouping removed the same three redundant build-time declarations
as Lua. The subsequently approved Rust review fixes are included in the
gameplay/UI commit. No Lua fixes were omitted.

Release modules were rebuilt against the current local SDK. The headless
suite passes with 22 Rust checks and six Lua observer checks, zero errors and
the existing four headless RmlUi texture warnings.

The previous WASM history is preserved at
`refs/backups/area17/rust-before-approved-lua-base`; its old local `master` is at
`refs/backups/area17/master-before-approved-lua-base`. Original WASM `2ce7c7e`
remains at `refs/backups/area17/pre-platinum-wasm`; old installed modules remain
in `codex-work/area17-pre-platinum-installed/`.

Branch-name correction: the approved Lua tip is on `master`, and the current
WASM tip is on `rust`. No file contents changed during this
correction. All added review branch names were removed; their commit references
remain under `refs/backups/area17/`. Further work stays on the user's existing
branches unless the user explicitly requests another branch.

## Approved Rust review fixes

The user approved all four review findings. The existing lifecycle commit now
cancels Lua ability durations and restores civilian fear on UFO death, keeping
cooldowns. Rust applies the same fix and floors its signed timers at zero.
Movement, teleport, drone/civilian destinations and off-map damage use actual
map dimensions. Replacing a technology panel invalidates its tooltip handle;
missing element lookups retry. A single cache skips unchanged HUD markup and
records only successful writes, replacing the three separate technology caches.

Validation: 12 Lua regressions; 22 Rust and six Lua headless checks; the visual
suite, including actual-engine tooltip reopening and unchanged-markup checks.
All three existing goldens pass (0.7%, 4.6%, 3.8%). Release modules were rebuilt.
The unit-script port diff is unchanged, and the first port still retains the
exact Lua Scripts tree. Both repositories remain on their original branches.
The preceding tips are retained in both repositories at
`refs/backups/area17/before-rust-review-fixes-20261015`.

## Technology panel and chat corrections (2026-10-16)

The two stray `0/5` labels belonged to other cards: their stacking order placed them above the old tooltip. RmlUi also needed explicit block layout for the tooltip rows. The panel now separates the tree from its inspection area, distinguishes affordable, unaffordable, prerequisite-locked and completed cards, and displays the current level, total effect, next cost and available resources. Its footer button reads `Close (T)`. Purchase requests use the same affordability predicate as the card display.

The dedicated `verify area17 tech-ui` GPU fixture checks Armor 3/10 at +120%, Pulse 2/5 at +200%, native hover callbacks and exact-budget, insufficient-budget, locked and completed purchase gates. It produces a visible screenshot and exits with zero errors and warnings. The existing headless suite still passes 22 Rust and six Lua assertions with clean logs. The older visual scenario that omits HUD pixels remains documented separately; its goldens were not replaced.

Area17 also maintained an independent `engine_console_open` flag, toggled by Enter even when engine chat was disabled. That flag is removed. Shared controls now restore real chat and editing bindings; shared movement reads the engine's actual writing state. Native tests exercise movement before and after chat submission/cancellation, including chat while the technology panel is open. The engine consumes chat typing before native or RmlUi shortcuts and draws its prompt above game overlays.

These changes are folded into the gameplay/UI port. `rust` still contains exactly two commits above Lua `master`; the CUS commit's delta is byte-for-byte unchanged, and the first port's unit scripts still match Lua. Prior tips remain under `refs/codex/before-chat-speed-controls` and `refs/codex/before-modal-enter-fix`. No game repository was pushed, and `TODO.md` was not edited.

Final control checks cover all seven games in both Lua and WASM: Alt +/−, physical Pause freeze/resume, F12, visible chat, editing/submission and Escape cancellation. All fourteen runs exit cleanly without runtime errors or warnings. Lua games with Chonsole keep that console and its existing command syntax. The fixture observes its actual text focus; it accepts public, ally and spectator chat output. UI typing checks run paused so accelerated simulation cannot end a round during the check. Native MyCube checks additionally assign a control group with Ctrl+1 and activate Move with M in both versions.

The Lua follow-up fixes held-key polling during Chonsole input in Area17 and Parts Needed, using the shared `controls.IsWriting()` utility. Focused checks verify moving → typing stops movement → closing chat permits movement again. The obsolete TTLD `No Enter` widget was removed because it swallowed chat; its stale local widget-order entry is removed by the recorded compatibility patch. Intro/restart Enter shortcuts remain available before ordinary chat handling. Existing MyCube and Parts Needed script whitespace edits remain untouched.
