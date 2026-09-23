# Baseline: known-good state before the code-review refactors

Recorded 2026-09-23, around 23:00 JST, as the reference for the work in
[`docs/wasm-code-review-2026-09-23.md`](docs/wasm-code-review-2026-09-23.md).

Every refactor step has to reproduce these results: the same headless assertion counts, and
visual suites that pass or have deliberate golden updates. If a change is meant to alter a
number here (the RNG switch, bug fixes), update this file in the same commit and say why.

## Source state

| repo | branch | commit | working tree |
|---|---|---|---|
| springcabal-games (this repo) | `main` | `715df74` | clean |
| spring-bar (engine and crates) | `rust-wip` | `adb3b7aa5e` | untracked notes only |
| Area17-wasm.sdd | `area17-wasm-port` | `7c376b4` | clean |
| Flove-wasm.sdd | `flove-wasm-port` | `20ae01c` | clean |
| Gravitas-wasm.sdd | `gravitas-wasm-port` | `c480db7` | **dirty**, see below |
| Hunted-wasm.sdd | `hunted-wasm-port` | `156dc90` | clean |
| MyCube-wasm.sdd | `mycube-wasm-port` | `33a2d69` | clean |
| PartsNeeded-wasm.sdd | `partsneeded-wasm-port` | `e46f17a` | clean |
| ToTheLastDrop-wasm.sdd | `ttld-wasm-port` | `6aedc58` | **dirty**, see below |

**Uncommitted work that the baseline includes.** It is not ours, and it must be committed (or
discarded) by its owner before the refactors start:

- **Gravitas** (fire effects work; `git diff` sha256 prefix `27504512bc638a0b`, 8 files, +175/−58):
  - modified: `ui/Cargo.toml`, `ui/src/fire/{distortion,effects,emit,mod,render}.rs`, `ui/src/shaders/fire_distortion.frag`, `ui/src/widgets/gfx_fire.rs`
  - untracked: `ui/src/fire/probe.rs`
- **TTLD** (`git diff` sha256 prefix `4dc8c9c25225fe71`, 11 files, +380/−97):
  - `GameData/weapondefs_post.lua`, `wasm-src/README.md`
  - `rules-synced/src/combat/{orks,story}.rs`, `integration.rs`, `unit_scripts/mod.rs`
  - `ui/src/{enlarger,input}.rs`, `lights/projectiles.rs`, `widgets/{dbg_e2e,gui_input}.rs`

**Build inputs:**
- The Rust crates `spring` and `spring-addons` come from the spring-bar working tree, through the `[patch]` in `~/.cargo/config.toml`.
- Engine binaries are in `../spring-bar/build-amd64-linux/install`:
  - `spring` built 20:22, sha256 prefix `a6b700cfc5cf4a0a`
  - `spring-headless` built 17:03, sha256 prefix `93d9bee33696e9d8`
  - both report `2026.07.01-247-g72e9784 rust-wip`
- The `rust-wip` commits after 17:03 are profiling, crash-handler and build-script changes; none touch the WASM API.

## `just verify-all` (all 10 runs passed)

| run | result |
|---|---|
| area17 static | passed |
| area17 headless | Rust integration assertions **18**, Lua gameplay assertions **12**; log: 2 errors, 8 warnings |
| flove headless | Rust rules assertions **68**, Rust UI input **6**, scenario **14**; log: 2 errors, 18 warnings |
| gravitas e2e | **14/14** stages PASS: spawn, invulnerable, electrafi, barrel, respawn, impulse, falldamage, terrain, plate, input, visuals, jump, fire, restart. Also PASS on: no test code in the shipped rules/ui modules, clippy clean with and without the feature, no lua error, no def warning, no undefined CEG, every model textured, no zero-power unit, **no re-entered world state** |
| hunted headless | **4** rabbit waves (the suite requires at least 2); log: 2 errors, 0 warnings |
| mycube headless | **21** assertions, then "ALL MYCUBE INTEGRATION TESTS PASSED" |
| mycube lua-headless | passed; log: 2 errors, 0 warnings |
| partsneeded headless | **48** assertions, then "ALL PARTS NEEDED INTEGRATION TESTS PASSED" |
| ttld headless | **31** assertions ("ALL TO THE LAST DROP INTEGRATION TESTS PASSED (31 assertions)") |
| unit-scripts partsneeded | passed. It prints `SKIP unit-script source comparison: no table-driven rules-synced/src/unit_scripts/`. Splitting Parts Needed's `unit_scripts.rs` into a `unit_scripts/` directory will turn that comparison on. |

The "2 errors" in several runs are present in the baseline. Any new error or warning in a later
run is a regression until explained.

## `just verify-visual`

The first full run failed 3 of 9. Each failure was re-run on its own to separate flakiness from
real drift.

| run | result |
|---|---|
| area17 visual | PASS: frame_020 0.9%, frame_080 5.3%, frame_450 3.7% (limit 8%) |
| flove visual | 9/9 on rerun. The first run failed `05_tree_promoted_to_level_2` at 5.2% against the 5% limit; the rerun got 4.4%, so this shot is **flaky** at the limit. |
| gravitas shots | PASS: arena 1.1%, HUD unchanged 0.0%, fire renders 3184 lit pixels (golden 3190) |
| hunted visual | PASS: 4.3 / 4.5 / 4.8% (limit 10%) |
| mycube visual | PASS: 4.4 / 4.4 / 4.4% (limit 9%) |
| partsneeded visual | PASS: 0.3 / 0.0 / 5.3% (limit 8%) |
| ttld visual | PASS: 0.1 / 0.4 / 0.4% (limit 1%) |
| gallery ceg all | PASS on rerun. The first run failed flove `barftrail/near/f02` ("never visible", golden visible in 69% of samples), and the next two runs of `gallery ceg flove` passed, so it is **flaky**. |
| gallery anim all | **FAILS reproducibly, for partsneeded only.** Identical numbers on two runs:<br>• `wisp`/`npcwisp` idle 30: Hair3 moved 5.18 elmos<br>• move 15: ArmL 3.62<br>• move 30: Ears 4.97<br>• images 4.2–5.9% off, limit 1.5% |

**The Parts Needed anim drift is already in the baseline.** Its goldens were recorded
2026-09-23T08:14Z on the same game commit (`e46f17a`) but engine `72e97847e9`. The engine now
includes, among others:
- `4fc79bdbb9` "Add synced random API; use streflop in synced MathExtra"
- `9a8cfd7aea` "Don't warn about weapon pieces at CUS attach"

So the drift probably comes from the engine, not the game. Until someone decides whether the new
poses are correct (then `just update-goldens gallery`), treat `gallery anim partsneeded` as
**failing by these exact numbers**. A refactor must not change them.

## Gravitas and TTLD: refactors happen in worktrees

The uncommitted work in those two checkouts is left untouched. The refactors run in git
worktrees on a new branch, `code-review`, cut from the committed HEAD:

- `~/worktrees/springcabal-review/games/Gravitas-wasm.sdd` (from `c480db7`)
- `~/worktrees/springcabal-review/games/ToTheLastDrop-wasm.sdd` (from `6aedc58`)

`~/worktrees/springcabal-review/games/` symlinks every other game to `spring-linux/games`. Point
the suites at it with `VF_GAMES_DIR=~/worktrees/springcabal-review/games`.

Committed-HEAD baseline for those two, without the uncommitted work:
- **ttld headless:** **24** assertions. The uncommitted work adds 7, which is where the 31 above comes from.
- **gravitas e2e:** passes, with the same 14 stages and checks as above.

Engine runs must be serialized, because every launch script uses `HostPort=8452`. Wrap them as
`flock /tmp/springcabal-verify.lock ./verification/verify ...`.

## After the refactors (2026-09-24)

The refactors are done: seven game branches, none pushed.

- **Final run.** Engine `rust-wip` `1bed8d7086` (`2026.07.01-273-g1bed8d7`):
  - `spring` sha256 prefix `5a524fd0cb41074c`, `spring-headless` sha256 prefix `56a921da3c3442e9`, both built 04:40.
  - Run with `VF_GAMES_DIR=~/worktrees/springcabal-review/games`.
- **Checking a failure against the baseline.** Worktrees at the baseline commits above, built against the same crates, are in `~/worktrees/springcabal-baseline/games`. Run the same suite there to tell engine drift from a refactor change.

| game | branch | HEAD |
|---|---|---|
| Area17 | `area17-wasm-port` | `2d12ece` |
| Flove | `flove-wasm-port` | `202fbda` |
| Gravitas | `code-review` (worktree) | `b79e24c` |
| Hunted | `hunted-wasm-port` | `6b36414` |
| MyCube | `mycube-wasm-port` | `960aef0` |
| PartsNeeded | `partsneeded-wasm-port` | `32ca96b` |
| TTLD | `code-review` (worktree) | `39be341` |

### Headless

Everything matches the baseline, except for these:

- **Flove rules assertions: 68 → 70.** A new restart test adds two.
- **Parts Needed ending test flaked at the refactor's last commit.** That commit moved the ending's spawn offsets to the synced RNG, and the frame-260 check assumed a fixed spawn distance. It failed 20–35% of runs. `32ca96b` now checks that the wisp approaches the player instead; it passed 6 of 6 runs.
- **TTLD: 24 assertions.** That is the committed-HEAD baseline; the WIP's 7 are not on `code-review`.

### Visual

| run | result |
|---|---|
| area17 visual | `frame_080` is **flaky**. Details below. |
| flove visual | 9/9 on rerun. The first run failed 3 shots at 5.1–7.2% against the 5% limit under load average 15–30. |
| gravitas, hunted, mycube, partsneeded visual | PASS |
| ttld visual | fails `selection fixture did not select the player` on both the baseline and `code-review`. That marker only exists in the uncommitted TTLD WIP (`dbg_e2e.rs`). |
| gallery ceg all | PASS |
| gallery anim area17, flove, gravitas | PASS (goldens re-recorded for the RNG switch) |
| gallery anim partsneeded | fails by exactly the baseline numbers (engine drift) |
| gallery anim hunted, mycube, ttld | fail. Bisected; the causes are below. Goldens not re-recorded yet. |

**Area17 `frame_080`.** The test camera sits at ground height over the crater point. Whether the beam digs that spot before frame 80 depends on real-time pacing. `8d54f3a` removed a quadratic start-up stall (0.5–0.7 s), which exposed the problem; the game itself did not change. Making the test timing-independent needs a test change and a golden re-record.

**Why the anim galleries changed** (no bugs found):

- **Hunted:**
  - The roster now iterates in unit-id order (`e596b3b`), which changes the unit ids the gallery units get.
  - `6b36414` switched the scripts to the engine RNG; the draws match the Lua scripts.
- **MyCube:** only `960aef0`, the engine RNG, both in the story spawns and in the iglu and drill-ship scripts. It matches the Lua's `math.random` ranges.
- **TTLD:**
  - `8c7c554` applies def `hscale`/`vscale` without the UI, as the Lua `unit_enlarger` gadget does.
  - `d985abd` moved the ork bob phase to the engine RNG.
  - The `crossbowman attack 15` failure is engine drift; the baseline shows it too.

## How to re-check

```bash
just verify-all        # must reproduce the counts above
just verify-visual     # must pass, or have reviewed golden updates
```

Per game: `just verify <suite> headless` (Gravitas: `e2e`) and `just verify <suite> visual`
(Gravitas: `shots`).
