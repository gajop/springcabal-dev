# WASM ports quality review, round 3 (2026-09-25)

The third review, done after rounds 4–6: the round-2 fixes, the move onto the engine's `CusHost`,
and dropping the workarounds for engine bugs the engine fixed. The earlier ones are
[round 1](../wasm-code-review-2026-09-23.md) and [round 2](../wasm-quality-review-2026-09-24.md).
Four read-only reviewers wrote the files in this directory. The coordinator re-checked the
findings marked ✔ in the code and the Lua originals.

## Grades

| Area | Round 2 | Now | Worst open problem |
|---|---|---|---|
| MyCube | B+ | **A−** | The village is cut off at the top; all five visual shots are mostly sea |
| Gravitas | B | **B+** (rules A−, ui C+) | Object collisions never damage (Lua damages those with an attacker); the ui module still has global state, and the fire WIP blocks moving it |
| Hunted | B | **B+** | ✔ Lua's `unit_invulnerable` and `unit_blocking` gadgets were never ported: shots and mines destroy carrots, burrows and the gun |
| Flove | B | **B+** | Story Skip works on every story: on the king's, each press gives 3 trees, resets mana and respawns wave 1 |
| Parts Needed | B | **B+** | ✔ Visual shots 3–4 catch a camera pan and pass on the wrong room (an all-black frame would be 10–13% off, limit 8%) |
| TTLD | B+ | **B+** | Poultice throws enemies instead of pulling them; stunned attacking orks never fire again |
| Area17 | B− | **B** | ✔ The UFO's 3 silent gravity beams and 3 silent napalm beams get no special handling: they damage (≈180 dps) the civilians they should pull |
| Crate | B− | **B−** | None of round 2's API findings fixed (unpinned git dependency, unescaped encoder, `flag("false")`); the host tests run nowhere |
| Tooling | C+ / C | **B−** | ✔ Every suite's speed override is ignored (`maxspeed=` vs `MaxSpeed=`); pixel checks are skipped, and pass, when the renderer differs from the goldens' |
| Cross-game | – | **B−** | About 1,070 `let _ =` (mostly GL, but some gameplay); rules/UI sharing done four ways; `e2e` means three things |

## What improved

- **Structure is no longer the problem.** Every game is gadgets and widgets that own their state.
  Files are small, and borrows are released before engine calls. No reviewer found a new
  re-entrancy risk. The only global state left is in Gravitas' ui.
- **Every round-2 bug is fixed**, in all seven games.
- **Hand-written plumbing is gone.** Rounds 5–6 replaced about 2,200 lines with engine and SDK code:
  the unit-script hosts, cylinder queries, clock and damage workarounds, and constants.
- **Tests grew and got more honest.** There are more checks, counts aren't doubled, messages go
  through the network, and there's a mine-on-a-hill check.

## What's left: themes

1. **Lua fidelity is still the weakest point.** A careful read against the Lua code finds real
   gameplay bugs in five games. Each is something the port never had, not a regression:
   - Area17: silent beams, impulse lift, God Gun cost (7,500 instead of 37,500).
   - Hunted: two gadgets missing, recoil sign.
   - Flove: Skip.
   - TTLD: Poultice direction, stun.
   - Gravitas: collision damage.

   A per-gadget checklist ("every Lua gadget → its Rust counterpart, or a README line on why
   not") would catch the missing-gadget class cheaply.
2. **Tests still prove less than they claim.** Examples:
   - timing-dependent or loose shots (Parts Needed, MyCube, Hunted, Gravitas);
   - checks that call internals instead of the engine (Parts Needed's Lua messages, MyCube scenery,
     Area17's "RmlUi callbacks");
   - checks that can't fail (Gravitas' clippy check, TTLD's re-entry check);
   - suites whose speed setting never applies.
3. **The crate needs a maintenance pass.**
   - Pin it (a tag or rev).
   - Run its host tests (`just test` in the crate, or in `verify static`).
   - Fix the encoder.
   - Pull in what the games still copy: `send_to_rules` (6×), the gallery-mode check (7×),
     warning helpers (6×), and the attach gadget for unit scripts (5×).
4. **The harness has quiet failure modes.**
   - The speed overrides are ignored.
   - A different renderer skips the pixel checks and still passes.
   - Trap detection looks for a message the engine never prints.
   - The "installed module matches source" check exists only for Area17.

## Notes for the user

- **TTLD's Lua original checkout (`ToTheLastDrop.sdd`) has 22 uncommitted edits.** They include a
  new `GameData/weapondefs_post.lua` that flips Poultice. The Lua comparisons run against this
  modified copy. Whose are they?
- **Engine-side items** from this round are in `spring-bar/WASM_GAME_API_TODO_2026-09-25.md`:
  - a pre-game `Initialize` for Wasm modules;
  - allegiance constants;
  - the headless groundFX error.
- **`CusHost::game_frame`** would wake unit scripts on Lua's schedule. It's optional and would
  move the anim goldens.
