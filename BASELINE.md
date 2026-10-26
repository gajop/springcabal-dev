# Baseline: the known-good state

Every change has to reproduce these results: the same headless assertion counts, and visual
suites that pass or have deliberate golden updates. If a change is meant to alter a number here,
update this file in the same commit and say why. Known problems are in
[`docs/open-problems.md`](docs/open-problems.md). Earlier baselines are in git history.

Recorded 2026-10-25.

## Source state

**Engine:** released `2026.10.25`, spring-bar
`dd05f8647458ff5541a8aee8d43b6218a64eaef8`. Tests use the downloaded Linux
binary via `SPRING_ENGINE_DIR` and its matching, clean SDK worktree via
`SPRING_BAR_DIR`; no engine build changed during the campaign. The generated
`.cargo/config.toml` patches `spring-sdk` and `spring-addons` to that SDK.
The local `springcabal-rs` dependency is `d6b9817`.

| Game | Lua (`master`) | Rust (`rust`) |
| --- | --- | --- |
| Area 17 | `cf172327d24f` | `b99b0a1dfeb5` |
| Flove | `50f6ca64bee6` | `03d572ca98b2` |
| Gravitas | `3d6aea2bac0a` | `41aa0b92e5b1` |
| Hunted | `80615da2c9b6` | `5bc14750293b` |
| MyCube | `4698657d927b` | `64cc3e4ad56b` |
| Parts Needed | `e9bb6f0e8a26` | `8c415fed5ed5` |
| To the Last Drop | `e0a36052f911` | `88193d52c4c3` |

## `just verify-all` (every run passes)

Every headless run plays at 100x. The speed is a `[modoptions]` key; before round 7 phase B, every
suite ran at 1x.

| run | result |
|---|---|
| host tests | **139** tests: springcabal-rs workspace 51, area17-shared 6, flove-shared 6, gravitas-shared 9, hunted-common 43, mycube-shared 9, partsneeded-shared 4, ttld-shared 11 (2026-10-26) |
| installed all | the installed modules of all seven games match their source |
| area17 static / headless | pass; Rust **23**, Lua **6**; no errors or warnings (2026-10-25) |
| flove headless | rules **66**, UI input **10**, scenario **8**; no errors or warnings (2026-10-25) |
| flove animation-trace | skeletons and 19,760 pose samples match Lua within 2e-3 |
| gravitas e2e / headless | **19/19** cases, plus the build and log checks / pass |
| gravitas lua-rules | **3/3** cases (collision damage 266, boss 10 shots in 11 s), no def, CEG or texture warning |
| gravitas lua-play | **8/8** steps through real input, Ctrl+Q back to the menu (the Lua game; xvfb) |
| hunted headless | **38** Rust assertions and **20** Lua regressions, `ALL HUNTED INTEGRATION TESTS PASSED`; no errors or warnings (2026-10-25) |
| mycube headless / lua-headless | **32** assertions / pass |
| partsneeded headless | **58** + **4** ending + **4** restart + **5** same-pass |
| ttld headless / pose-parity | **54** / 105 samples, exact |
| unit-scripts partsneeded | pass; the source comparison covers walk legs, walk arms, hover arms and idle |

Each suite passes its exact count to `Suite::new`, so a run with fewer checks fails. Every suite
also fails on any runtime failure (`verification/lib/failures.sh`).

Area 17 gained its 23rd Rust check on 2026-10-25: every initial scenario unit
must have its CUS script attached before the gameplay checks. This catches
scene creation during module loading, before creation-event delivery is active.

The host count includes shared music-loop, matched f32 math and Hunted behavior tests.
Hunted's common crate has 43 tests, including spatial boundaries, rounded falloff
ties, cosmetic RNG and attribute rounding.

Hunted's 36th check (2026-10-25) requires global LOS for all ally teams,
matching the Lua startup widget. This prevents redundant native LOS work;
flashlight-controlled rabbit visibility remains active.

The current offscreen GPU runs report no engine errors or warnings. The older
headless renderer's groundFX-atlas warning is not part of these runs.

## `just verify-visual`

Every scenario suite passes. A renderer other than the goldens' fails unless
`VF_ALLOW_RENDERER_MISMATCH=1`.

| suite | shots compared |
|---|---|
| Area17 | 3, each paused on its frame (0.0 / 3.5 / 2.0% after the re-record) |
| Flove | 9 (soft particles on) |
| Gravitas | arena, HUD, fire pixels |
| Hunted | 5, plus the HUD crops and the end screen |
| MyCube | 5 |
| Parts Needed | 4, plus the ending's final frame |
| TTLD | 3, plus the e2e wheel, Poultice and tracking checks |

The 2026-10-25 NVIDIA run compares Flove's GPU goldens. The other scenario
suites complete their assertions and skip old Mesa pixels using
`VF_ALLOW_RENDERER_MISMATCH=1`; their goldens and tolerances are unchanged.
The direct five-frame fire comparison passes below 0.1% in every frame on
Linux/NVIDIA and the released Windows engine under Wine/Mesa.

The galleries:
- **Anim galleries** pass for all seven games, every pose exact. Each unit is captured alone
  with the synced RNG reseeded per frame (`fixtures/gallery/gallery.lua`), so one unit's logic
  can't move another's poses.
- **Parity gallery** (WASM vs Lua poses, report only). Flove, Gravitas, MyCube and Parts Needed
  match Lua in every shot. The rest:
  - **Hunted**, 1 shot: rabbit move f30, by 0.5 elmos (the engine's `Wait*` lag).
    Subsequently fixed in the shared `spring` crate by `spring-bar` commit
    `ca1985b144`; the rebuilt port now matches Lua for all nine gallery unit types.
  - **TTLD**, 4 shots: the builder. Its Lua script was never shipped, so the port deliberately
    gives it the crossbowman's (see the README).
  - **Area17**, 259 shots: all pieces missing from Lua's capture, because Lua's respawned player
    UFO abducts the gallery UFO (see open problems). Wherever both captured the UFO, its poses
    match exactly.
- **CEG galleries** pass. These captures flake on engine particle noise, so rerun once before
  concluding. Seen failing once each: Area17 `sickfires/near/f02`,
  `genericbunnyexplosion-medium-red/far/f12`, `explosion/near/f12`; Flove `barftrail/near/f02`,
  `explosion/near/f12`; Hunted `genericbunnyexplosion-large-red/{near,far}/f12`.

Every golden re-record is explained in its commit message. The evidence is under
`~/worktrees/golden-diffs-2026-09-24/<game>/`.

## How to re-check

```bash
just verify-all        # must reproduce the counts above
just verify-visual     # must pass, or have reviewed golden updates
```

Per game: `just verify <suite> headless` (Gravitas: `e2e`) and `just verify <suite> visual`
(Gravitas: `shots`). `verify` takes its own lock. Another session's tools sometimes kill `spring`
processes: a run that dies within a second with status 137 was killed, not failed, so rerun it.
