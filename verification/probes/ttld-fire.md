# To the Last Drop fire

Run from the workspace root with a frozen UI built with `--features fire-probe`:

```sh
VF_GAMES_DIR=/path/to/games \
VF_EFFECTS_MODULE=/path/to/ttld_ui_wasm.wasm \
verification/verify probe ttld-fire lua
VF_GAMES_DIR=/path/to/games \
VF_EFFECTS_MODULE=/path/to/ttld_ui_wasm.wasm \
verification/verify probe ttld-fire wasm
```

Use an engine/SDK providing `Game.GetWindVector`. The two game directories are
`ToTheLastDrop.sdd` and `ToTheLastDrop-wasm.sdd`.

This reuses the Gravitas fixed-age capture method with TTLD's real fire config,
particle class, textures and shader. Camera, emissions and random samples are
fixed. It holds particle ages 9, 10, 45, 60 and 90 for screenshot capture. The
first two images continue the same GPU allocation across a ten-frame opaque
particle's expiry; an invisible older allocation prevents it being reclaimed
from the front. That checks expiry masking of an interior allocation, including
an opaque endpoint. Later stages reconstruct the regular fire at fixed ages.

Both variants log five `[TTLDWind]` vectors for float32 comparison of Lua
`Spring.GetWind()` with the SDK vector API. The frozen module avoids rebuilding
one side during a source comparison. Screenshots and logs are in
`verification/out/ttld-fire-{lua,wasm}/`; use the same 420×300 crop at 480,80 as
`gravitas-fire-compare` for the effects region. Regular TTLD gameplay, visuals
and poses remain covered by `verification/verify ttld` suites.
