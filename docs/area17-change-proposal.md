# Area 17 approved Lua grouping

All five groups were approved by the user:

1. Current-engine compatibility.
2. Direct controls, camera and interface lifecycle.
3. Rendering.
4. Unit animations and safe script calls.
5. Gameplay calculations and upgrades.

The active Lua branch now has these five commits. Three redundant build-time
defaults are excluded. The cricket recording is retained: the bundled Ambient
Player requires it, as the engine smoke check confirmed.
All other final files are unchanged from the preceding review.

WASM now has exactly two commits above this approved Lua history. See
`area17-platinum-review.md` for exact commits, preservation and verification.
