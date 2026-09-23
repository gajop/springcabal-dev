# My Cube

Original entry: https://ldj.am/42/my-cube

Ludum Dare #42 · jam

By **gajop**. Co-authored: **@anarchid, @picassoct**.

## Ratings

| Category | Score |
| --- | --- |
| Overall | 3.42 |
| Fun | 2.95 |
| Innovation | 3.24 |
| Theme | 3.47 |
| Graphics | 3.90 |
| Mood | 3.25 |

No Audio score was included in the supplied excerpt.

## Description

It's been two years since our last LD submission, and we're excited to release our new game!

Stay on land, the water is freezing. Keep your people alive, heated and well fed. Survive.

## Controls

- Standard RTS controls (Left Click to select, Right Click to give orders, Mouse, WASD or Arrow to move Camera)
- 1 to sell ice
- 2 to buy heat
- 3 to buy food!

## Recommended spec (original submission)

- Linux (with libcurl3) or Windows
- OpenGL drivers and a relatively modern GFX card (at least GLSL 3.x + support)

## Images

The supplied page listed `default_loadscreen.png` and `screenshot`. Both downloaded
WebPs match existing game artwork, with differences from image compression;
their original filenames and retained asset paths are recorded here.

| Supplied download | Existing game asset (relative to repository root) |
| --- | --- |
| `102404-f20d451e4063ee1ceca4a806bc9b9e5a.png.webp` | `spring-linux/games/MyCube.sdd/Bitmaps/LoadPictures/Background2.png` |
| `18f09.png.webp` | `spring-linux/games/MyCube.sdd/Bitmaps/LoadPictures/default_loadscreen.png` |

Both PNGs are also present under `MyCube-wasm.sdd/Bitmaps/LoadPictures/`.
The existing gallery thumbnail `wasm-menu/WasmMenu/images/mycube.png` uses
`Background2.png`. No additional My Cube image copies are retained here.

Comparison: both pairs have dimensions 1924×1008 and visually identical scenes.
Normalized pixel RMSE was 0.0117087 and 0.0131984 respectively, consistent with
the lossy WebP versions rather than byte-identical duplicates.
