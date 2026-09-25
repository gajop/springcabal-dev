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
./run-wasm.sh --game flove    # one game directly (--lua for the original)
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
- `launch/` is the only source of launch settings. `springsettings.cfg` is the
  graphics profile, and `games/<game>/{wasm,lua}.txt` plus `graphics.cfg` are
  what each menu button starts. The menu compiles them in, and `run-wasm.sh`,
  verification, the smoke test and the release read them. Don't duplicate them
  elsewhere. Rebuild the menu after editing them. Suites add test-only options
  (`test_mode=1`, ...) on top; those are never committed to `launch/`.
- After an intended visual change, run `just update-goldens <suite>`, look at
  the images, then commit them.
- `TODO.md` holds the current rating of every WASM and Lua version.
- `BASELINE.md` holds the counts every change must reproduce, and
  `docs/open-problems.md` the known open problems (delete entries when fixed).
- In a WASM port, unit scripts are hosted by the engine SDK's
  `spring::cus::host::CusHost`. Rules code attaches scripts in `UnitCreated`
  and calls them through `with_cus_module_or_defer` (from `export_core_cus!`),
  which queues the call while the CUS state is busy. The engine delivers
  `Create` exactly once; never run it yourself.
- Don't hide engine errors behind `let _ =` where failure breaks gameplay
  (orders, unit creation, script calls, document loads): log them. For
  months every `call_unit_script` with arguments failed with ApiError 1 (a
  crate bug, fixed in spring-bar `d1d5b0188c`), and `let _ =` hid it: Parts
  Needed's piece masks, Gravitas' jumps and TTLD's spell animations were all
  silently dropped.

## Conventions in the WASM ports

- Addon names (`Widget::name` / `Gadget::name`) are PascalCase: the type's
  name without its `Widget` / `Gadget` suffix (`GuiCamera`, `UnitScripts`).
- Cargo features mean the same in every game: `headless-integration` builds
  the headless assertion suite, `e2e` the visual scenario (it may enable
  `headless-integration` too). Probes are `*-probe`; `diagnostics` only adds
  log lines.
- Use the shared crate (`springcabal-rs`) instead of per-game copies:
  `springcabal::message` for encoding and parsing messages and for sending
  them (`send_to_rules` from the UI, `send_to_ui` from the rules; both log a
  failure), `check::Suite::new(tag, title, expected)` for test tallies with the
  suite's exact check count, `gallery` for gallery mode and `defs::DefCache`
  for defs resolved once. Warnings go through the SDK (`spring::log_warning!`,
  `log_once!`, `ResultExt::log_err` / `log_err_once`), not game helpers.
- The games pin the crate with `rev = "..."` in `wasm-src/Cargo.toml`; the
  `[patch]` in `.cargo/config.toml` builds against the local checkout. After
  pushing `springcabal-rs`, bump the rev in all seven games.

## Logs

- `run-wasm.sh` writes `wasm-test/write/infolog.txt` and a per-session copy in
  `wasm-test/write/logs/`, and prints an error/warning summary on exit.
- Verification runs write to `verification/out/<suite>/` (`last.combined.txt`,
  screenshots, goldens diffs).
- `spring-headless` only flushes `infolog.txt` on a clean exit. Headless
  suites quit themselves once their markers appear (`vf_quit_when`); when a
  run is still killed by its timeout, read its stdout instead.
