# CLAUDE.md

Guidance for Claude Code in this repository. README.md covers setup, layout and
the menu; this file lists what an agent needs on top of that.

## What this repo is

Dev tooling, the WASM game menu and release packaging for SpringCabal's Ludum
Dare games on the Recoil `rust-wip` engine (built from `../spring-bar`). Each
game has a Rust/WASM port (`*-wasm.sdd`) and its original Lua version (`*.sdd`).

The games and maps themselves live under `spring-linux/` in their own git
repositories (listed in `content.tsv`). They are gitignored here and must never
be pushed from here; only this repository is pushed
(`gajop/springcabal-dev`, private).

## Everyday commands

```bash
just --list                   # everything, grouped
./run-wasm.sh                 # the WASM menu (WASM and Lua buttons per game)
./run-wasm.sh --game flove    # one game directly: hunted, area17, flove, ttld, gravitas
just build-all                # fmt + clippy + build + install every game's modules
just verify <suite> [mode]    # see verification/README.md
just verify-all               # headless/static suites
just verify-visual            # screenshot suites against goldens
```

Rebuild the engine with `./docker-build-v2/build.sh linux` in `../spring-bar`.
Rebuild one game's modules with `just copy` in its `wasm-src/`.

## Rules

- Tests must not modify `spring-linux/`. Suites stage copies and build into
  `verification/cache/`. `release/package.sh` ships the checkouts as they are
  and rejects test builds.
- `launch/` holds the start scripts and configs used for play. Test-only
  options (`test_mode=1`, ...) are added by the suites, never committed there.
- After an intended visual change, run `just update-goldens <suite>`, look at
  the images, then commit them.
- `TODO.md` holds the current rating of every WASM and Lua version.

## Logs

- `run-wasm.sh` writes `wasm-test/write/infolog.txt` and a per-session copy in
  `wasm-test/write/logs/`, and prints an error/warning summary on exit.
- Verification runs write to `verification/out/<suite>/` (`last.combined.txt`,
  screenshots, goldens diffs).
- `spring-headless` only flushes `infolog.txt` on a clean exit; when a run is
  killed by a timeout, read its stdout instead.
