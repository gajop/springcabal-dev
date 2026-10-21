# Releasing

A release is one self-contained folder per platform: the engine, the WASM menu,
every game (WASM port and original Lua version) and their maps. The player
extracts it and runs `springcabal.sh` (Linux) or `SpringCabal.bat` (Windows).

Releases are built locally, from whatever is checked out under `spring-linux/`.
Nothing is pushed or uploaded by these scripts.

## 1. Pick the engine

Bundles use a published engine release from
[gajop/spring-rust](https://github.com/gajop/spring-rust/releases). Both the
`recoil_<TAG>_amd64-linux.7z` and `recoil_<TAG>_amd64-windows.7z` assets have
to exist:

```bash
gh release view 2026.09.23 -R gajop/spring-rust
```

The games have to build against the same engine revision, so check that the
`spring-sdk`/`spring-addons` crates the games compile against match that tag.

## 2. Prepare the content

1. Commit the work in each game and map checkout. The packager records every
   checkout's branch and commit in `BUILDINFO.txt` and warns about uncommitted
   changes. It ships them anyway, but then the bundle can't be reproduced.
2. Rebuild the WASM modules: pass `--build` to the packager, or run
   `just build-all`. The packager refuses modules that contain test markers
   (a leftover `e2e`/`headless-integration` build).
   It also warns when source inputs, embedded templates/shaders, manifests or local dependency sources are newer than the installed modules. Dependency inspection uses `cargo metadata --offline --locked`, so the dependencies must already be cached; it does not fetch or build them. `BUILDINFO.txt` records this current dependency resolution, including commit and dirty state for local patches. Use `--build` to ensure those inputs match the shipped modules.
3. If you add a game or map, add it to `content.tsv`, give it
   `launch/games/<game>/{wasm,lua}.txt`, and add it to the menu.
4. The packager refuses a menu built before the latest change to
   `launch/games/`, because the menu compiles those files in.

## 3. Package

```bash
just package 2026.09.23                      # Linux + Windows
./release/package.sh --engine-tag 2026.09.23 --platform linux --version 2026.09.23-rc1
```

Output, in `release/out/`:

| Path | Contents |
|------|----------|
| `content-<ver>/` | the shared `.sdz` game and `.sd7` map archives |
| `SpringCabal-<ver>-linux/`, `.tar.gz` | the Linux bundle |
| `SpringCabal-<ver>-windows/`, `.zip` | the Windows bundle |

Engine downloads are cached in `release/cache/`. To test a bundle before an
engine release exists, point the packager at a local install instead:

```bash
./release/package.sh --platform linux --no-archive --version test \
    --engine-dir linux=../spring-bar/build-amd64-linux/install
```

What the packager does:

- Each game `.sdd` becomes a `.sdz`. It drops the archive's own `springignore.txt`
  patterns plus dev-only content (`wasm-src/`, `port-reference/`,
  `verification/`, `.git`, `target/`).
- Map `.sdd` folders become `.sd7`. `Area17.sd7` gets the patched dual-fog gadget
  from `patches/area17-map/` (`scripts/area17-map.sh`).
- `wasm-menu/` becomes `WasmMenu.sdz`. Both platforms use the locally built
  Wasm menu; native menu libraries from development builds are excluded.
- It adds `springsettings.cfg` (portable mode, `launch/springsettings.cfg`),
  the launcher, `README.txt`
  (from `release/README.txt.in`) and `BUILDINFO.txt`.

## 4. Test

```bash
just smoke-test release/out/SpringCabal-<ver>-linux
```

The smoke test starts every menu entry and the menu with the bundle's `spring` binary through `SDL_VIDEODRIVER=offscreen`, using the real GPU without opening desktop windows or falling back to Xvfb. It uses the shipped settings and per-game graphics overrides, with a 1280×720 window at origin (0, 0) and muted sound, and checks the engine's logged drawable size. Every game must load and remain running until the timeout; the frame count is informational. The menu must load its manifest and either exit cleanly or remain running at the timeout. Both Lua and WASM runs fail on any `Error:` or `Warning:`, runtime failure, missing renderer identity or software renderer. Full logs are kept in the printed temporary directory.

After that, play at least one WASM and one Lua game from the menu on each platform, and return to the menu from inside a game.

## 5. Publish

Releases are published manually to
[gajop/springcabal-dev](https://github.com/gajop/springcabal-dev/releases).
For a numbered release, pass the version to the existing packager:

```bash
./release/package.sh --engine-tag 2026.10.21 --platform all --version 1.0.0 --build
```

Commit and push the framework/menu revision and tag it `v<version>` (for example,
`v1.0.0`). Attach both platform bundles and their SHA-256 checksums to that tag's
GitHub release. Include a source snapshot of the committed framework, shared
crate, games, maps and local support content when individual game branches have
not been pushed. Record those revisions and the engine tag in the snapshot.
The source snapshot excludes Git history, local caches and generated binaries.

Release notes should state the engine tag, launch instructions, validation
results and known limitations. Windows checks run under Wine should be described
as Wine checks; native Windows hardware validation is separate.
