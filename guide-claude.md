# guide-claude.md

Instructions from the user, recorded verbatim:

you are to work on this folder, along-side codex which is currently in the process of improving the hunted wasm game, which _mostly_ works but has some issues still
there is no single git repo here so you must be careful, each game has its own folder and there's a repo there; because of this you MUST NOT be destructive; deleting folders, running aggressive checkout or replace.. bad.. do NOT do it

you are to port other games from lua to rust (wasm)
- Flove.sdd -> Flove-wasm.sdd
- Gravitas.sdd -> Gravitas-wasm.sdd (not sure if you really need the Scenario-Editor-{Core,Gravitas}.sdd ported too; we really do not need the full editor anymore, maybe take just the bits you need and port those, and drop the Scenario Editor dependency)
- LD43.sdd -> LD43-wasm.sdd (Can rename it to be ToTheLastDrop-wasm.sdd)

engine is ~/projects/spring-projects/spring-bar

other AI writes its stuff in ai-changelog.md, answers.md, engine-issues.md, summary.md, and so on
you can do the same, for your own work, but in your own files; you must not touch these shared files

anything unclear here? please don't spend forever inspecting all of these games

technical aspects:
- rust + wasm (both are quite immature and still freshly done in the engine dir); if you run into engine limtations, prefer to write it in a markdown instead so you don't conflict with AI; avoid huge hacks as the point of these ports is to also improve the AI
- modular Rust code, mod.rs should be thin, with only pub use and mod; code must be written in step-down style, with public functions in the top and private in the bottom, ordered in the falling order of abstraction and call order, so it reads like a book; you CAN write one-line separator comments here (exception to the below), but not more than // Public API, // Helpers  kind of stuff
- for rmlui prefer to use the data binding model rather than purely dynamic HTML (inner rml); use rmlui heavily for UI; you will likely see some annoyances there but prefer to do this anyway; see Hunted-wasm.sdd as the best (closest working example)
- if certain things still don't exist in Rust+WASM, note them; don't create huge piles of lua hacks to workaround things
- no unsafe, avoid panics; keep cargo lints strict, but do not lint too many args things; strong typing; fail fast if data/assumptions are wrong
- do NOT write comments, NO COMMENTS; this is key; you can ONLY maintain comments in their EXACT form as they were in the original, but you must NOT reword them and you must NOT write new ones
