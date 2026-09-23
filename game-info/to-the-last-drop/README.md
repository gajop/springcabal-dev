# To the Last Drop

Ludum Dare #43 · jam

By **gajop**. Co-authored: **@googlefrog, @j3jumby, @ashdnazg, @silentwings**.

The supplied excerpt listed **Download**, **ldjam.com**, **Linux**, and **Source**.
Their link targets and the exact entry URL were not supplied.

## Ratings

| Category | Score |
| --- | --- |
| Overall | 3.45 |
| Fun | 3.33 |
| Innovation | 3.38 |
| Theme | 3.93 |
| Graphics | 3.43 |
| Audio | 2.67 |
| Mood | 3.17 |

## Description

Usually the militia is more than a match for the occasional orkish raid. As the towns blood mage your contribution tends to be limited to patching up any wounded (at a heavy discount, of course). This time is different. Everyone who can wield a pitchfork is being urged to fight. A gigantic army headed by a fearsome (and massive) leader is approaching. There is no way the militia is up to the task, and, alas, your spells and effects are too weak to tip the balance.

Unless... you were to crack open your book of Forbidden Magic. Powered by more than pricked fingers and vials of sheep's blood, these spells may just be the tool required to save us. Well, most of us. The townsfolk will understand as, if any of us are to see the dawn...

How many sacrifices must be made?

## Technical details (original submission)

Built with SpringRTS. A modern desktop PC supporting OpenGL 3.x+ is required to run the game. Linux users should install libsdl2.

## Changelog

- Fix Linux release
- Fix spell sounds

## Controls

Cast spells by draining life from nearby allies.

- Hold Left Mouse: move
- Hold Right Mouse: attack
- 1 Transfusion: Heal yourself
- 2 Heartburn: Cast a fireball
- 3 Adrenaline: Increase the speed of yourself and nearby allies
- 4 Migraine: Disable enemies
- 5 Dialysis: Throw away your enemies

All spells require nearby allies to be used as source.

## Images

The supplied page listed `unknown2.jpg`, `unknown4.jpg`, and the label `screenshot`.
Two WebP downloads were supplied. Their exact mapping to those original captions
is not established, so the downloaded filenames are preserved rather than guessed.

- [1e3ff.jpg.webp](images/1e3ff.jpg.webp) — 1915×1012; town combat, 87% health.
- [1e422.jpg.webp](images/1e422.jpg.webp) — 1923×1015; fireball and smoke, 89% health.

These screenshots were not found among the image assets in either
`spring-linux/games/ToTheLastDrop.sdd` or `ToTheLastDrop-wasm.sdd`.
Their existing `Bitmaps/LoadPictures/loadscreen.png` is different artwork.
The supplied WebPs are preserved unchanged here; upstream artwork rights remain
with their original owners.
