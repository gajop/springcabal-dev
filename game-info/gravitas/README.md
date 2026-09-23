# Gravitas

Original entry: https://ldj.am/32/gravitas

Ludum Dare #32 · jam

By **springcabal**.

## Ratings

| Category | Score |
| --- | --- |
| Overall | 3.17 |
| Fun | 2.60 |
| Innovation | 3.04 |
| Theme | 3.14 |
| Graphics | 3.74 |
| Audio | 3.10 |
| Humor | 2.57 |
| Mood | 3.00 |
| Coolness | 100% |

## How to run (original submission)

Remember to extract the whole archive, then launch `Gravitas` bash script on Linux or `Gravitas.bat` on windows. On Linux, you'll need to have SDL2 installed.

NOTE: If you use the post-jam version, just run Gravitas or Gravitas.exe (there are no bash or bat scripts).

## Controls

right-click to move or attack, W + left click to jump. Q to switch pull/push mode, S to stop movement/attacking.

## About game

This is a puzzle/shooting game made on an RTS engine, with all the ensuing hilarity. You control a character who can jump around and shoot gravity beams that either attract or repulse objects, including enemies. You can kill enemies (except ones who cannot be killed) by projecting them into danger zones like ion storms, fires, or space, or just by smashing them against each other fast enough.

## About stuff

Some code were reused (UI framework and such), but all art from ground textures to unit animations was done from scratch with exception of a few cursors and icons.

## About engine

The game was made on the pretty versatile if somewhat difficult to learn Spring RTS engine (springrts.com/ ), using its interesting physicsy bits to try to make something less ordinary and RTS-y.

## About us

we're a few guys who've some different stuff using Spring, so we decided to also do a Ludum Dare event for epic fun.

## About bugs

you can submit them on github.com/SpringCabal/Gravitas/issues

## Developers (alphabetically)

- Anarchid
- ashdnazg
- gajop
- Picasso
- Silentwings

PS: We want to thank everyone who has played our game. We're also thankful for all the feedback that has been provided, keep it coming ;)

We also provide a post-jam version you can use for better enjoyment. The changes are mentioned below.

## Update 22.04.2015

- Fixed one resource hog
- Fixed room 12 bug
- Made the game easier
- Made the character control slightly better
- Changed distribution archive from 7z to zip

## Update 23.04.2015

- Fixed robot explosions
- Added restart button/win condition

## Update 26.04.2015

- Using a better pathfinder system: should result in smoother movement
- Changed (improved) the control system
- Easier to right click on robots
- Units avoid electric fields better
- Added wall explosion
- Some other minor fixes

## Update 07.05.2015

- Using a newer engine version which removes the need for .bat and .bash files and contains some additional fixes

## Images

Four website screenshots supplied from the user's Downloads directory, preserved
unchanged with their downloaded filenames. All are 900×489. Original page captions
were not supplied; the descriptions below identify their visible content.

- [52862-fa1529e24d7479130ddd28570ff13343.jpg.webp](images/52862-fa1529e24d7479130ddd28570ff13343.jpg.webp) — electric fields, floor switches, and crates.
- [52862-77c27906c15feb379b9e6d8359cafacd.jpg.webp](images/52862-77c27906c15feb379b9e6d8359cafacd.jpg.webp) — line of fires across a room.
- [52862-2559e55d4c7d8864a1e5293487b275d3.jpg.webp](images/52862-2559e55d4c7d8864a1e5293487b275d3.jpg.webp) — central fire and scattered crates.
- [52862-81d6380d54dccb1042bf86c3df911954.jpg.webp](images/52862-81d6380d54dccb1042bf86c3df911954.jpg.webp) — gravity beam aimed at a crate.

These are distinct from `Bitmaps/LoadPictures/7BTPEvN.jpg` in the existing game,
which shows a different camera view without the gameplay HUD. No matching images
were found in the checked local Gravitas, Gravitas-wasm, or Scenario-Editor-Gravitas
game folders. Upstream artwork rights remain with their original owners.
