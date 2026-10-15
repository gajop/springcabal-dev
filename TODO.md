## Wasm

1. Gravitas: GOLD+
   reported: in gravitas wasm, i can only jump once..
   (reviewing code..)
3. Zeus vs Bunnies: GOLD+
   substantial review
4. Area17: GOLD+
5. Flove: GOLD+
   Broken again, LMB doesn't shoot... this was fixed at one point.. it was actually broken twice I think?
6. Parts Needed: GOLD+
7. My Cube: GOLD+
8. To the Last Drop: GOLD+

## Lua

1. Gravitas: GOLD
	(reviewing code..)
3. Zeus vs Bunnies: Platinum
4. Area17: GOLD
	Status: Lua commits approved, but need to play test
6. Flove: GOLD
	Status: Lua commits approved, but need to play test
8. Parts Needed: GOLD
9. My Cube: GOLD
10. To the Last Drop: GOLD

## Overall

---

Terminology:
- Platinum+: play tested on linux and windows
- Platinum: code reviewed
- Gold+: unit scripts ported to Rust
- Gold: works with only very small issues
- Silver: playable but with large issues
- Bronze: playable with some large issues or complex workarounds
- Broken: doesn't work no matter what you do


Platinum goal:
- Each commit in Lua must be reasonable with only sensible changes inside
  - This doesn't mean you discard random changes.. many changes were made like that for a reason
  - Probably makes sense to split things into multiple changes
- If there are bugs in Lua, we should probably fix them in Lua first, and then replicate the _fix_ in WASM, instead of replicating the bug
  - If unsure, discuss with me
- WASM should be strictly on top of Lua, as two commits:
  - first introducing the port to wasm, of everything besides unitscripts
  - second, porting unitscripts as well
- Never manually alter todo.md
- Never drop commits/changes without presenting