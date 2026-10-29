# Releasing

A release contains the published engine binaries, locally built WASM menu and
games, all seven original Lua games and their maps. Players extract a bundle
and run `SpringCabal` (Linux) or `SpringCabal.exe` (Windows) to open the menu.

`release/release.sh` automates the process used for 1.0.1: prepare all assets
locally, run the existing checks, then explicitly publish them. Preparation
does not push or upload anything. Publication pushes this framework repository.
Push the selected game commits separately to the public SpringCabal repositories:
Lua to `master`, Rust to `rust`, as listed in `content.tsv`. Push the shared crate
to `gajop/springcabal-rs` `main` too. The source archive includes their exact
committed revisions; publishing the framework does not push those repositories.

## Prerequisites

Use Linux with Bash, Python 3.11+, Git, `just`, `7z`, `rsync`, `zip`, `tar`,
`strings`, `sha256sum`, the Rust toolchain and an authenticated GitHub CLI
(`gh auth status`). Install the `wasm32-unknown-unknown` Rust target and populate
the checkouts and local/download entries listed in `content.tsv` (see README.md).
Cargo dependencies must be cached: provenance inspection uses
`cargo metadata --offline --locked`.

Choose a published release from
[gajop/spring-rust](https://github.com/gajop/spring-rust/releases) containing both
`recoil_<TAG>_amd64-linux.7z` and `recoil_<TAG>_amd64-windows.7z`. The SDK crates
used to build the games must match that engine release. The current SDK pins
match `2026.10.3001`. Use the pinned Git crates when preparing a public release:

```bash
gh release view 2026.10.3001 -R gajop/spring-rust
./setup.sh --no-dev-engine
```

The [2026.10.25 compatibility review](docs/engine-compatibility-2026-10-25.md)
records all engine changes since 1.0.2, including the weapon-number and module
startup changes applied for 1.0.3-rc.2.
The [next compatibility review](docs/engine-compatibility-2026-10-29.md) accounts
for the subsequent runtime, query, velocity, RNG, wind and rendering changes.

Commit the framework/menu, shared crate, games and maps before preparing a
release. Preparation refuses dirty source checkouts, including untracked files.
For a public release, confirm that each selected game revision is also the head
of its public branch. Keep game and shared-crate SDK pins consistent when pushing
them, since the games use the shared crate from the surrounding workspace.
The engine's released tag is resolved to its full commit; the source snapshot
links that public engine revision instead of copying a development engine tree.
When adding content, update `content.tsv`, `launch/games/` and the menu first.

## Prepare all five assets

Use a new version for each public release; the examples below use `1.0.3-rc.3`:

```bash
just release-prepare 1.0.3-rc.3 2026.10.3001
# Equivalent:
./release/release.sh prepare 1.0.3-rc.3 --engine-tag 2026.10.3001
```

This runs `just build-all` through the existing packager (fmt, Clippy, release
build and install for all WASM games and the menu), downloads the selected
engine binaries, assembles both platforms, archives the committed sources and
writes checksums. It checks that the sources have not changed during packaging.
Engine downloads are cached in `release/cache/`.

The five upload assets are written to `release/out/`:

| File | Contents |
| --- | --- |
| `SpringCabal-<version>-linux.tar.gz` | portable Linux bundle |
| `SpringCabal-<version>-windows.zip` | portable Windows bundle |
| `SpringCabal-<version>-source.tar.gz` | committed framework, shared crate, game and map sources, plus local support content |
| `BUILDINFO-<version>.txt` | content revisions, Cargo dependency provenance and the released engine commit |
| `SHA256SUMS-<version>.txt` | SHA-256 checksums for the other four files |

The source archive includes `SOURCEINFO.json` with full revisions (including
recursive submodules) and hashes of local support content, and
`BUILDING-RELEASE.txt` with rebuild instructions. Initialize any submodules at
their pinned commits before packaging (`git submodule update --init --recursive`
in the affected checkout).
Git history and ignored build outputs are excluded. The engine source is
available at the public tag recorded in those files.

Unarchived bundles and `content-<version>/` remain in `release/out/` for testing.
`SOURCES-<version>.json` is a local preparation record used by the publish
command; keep it alongside the assets. It is not an additional upload. After
changing a source checkout or rebuilding an asset, prepare again. Never run two
packagers for the same version at once.

## Portable bundle layout

`release/package.sh` owns the bundle layout for both platforms:

- Each game `.sdd` becomes a `.sdz`. Its `springignore.txt` patterns and
  development files (`wasm-src/`, `port-reference/`, `verification/`, `.git`,
  `target/`) are excluded. Original Lua games are packaged from their local
  checkouts; they do not need a Rust build.
- Map `.sdd` folders become `.sd7`; existing archives are copied. Area 17 gets
  the dual-fog patch from `patches/area17-map/` via `scripts/area17-map.sh`.
- `WasmMenu.sdz` contains the locally built WASM menu on both platforms.
  Development native-menu libraries are excluded.
- The graphical engine is renamed to `SpringCabal` / `SpringCabal.exe`.
  Dedicated/headless engines, downloader, unitsync, import/debug libraries,
  examples and unused skirmish AIs are removed. NullAI and its C interface stay
  because the games use them.
- `isolated.txt` makes the executable use its own directory for settings,
  caches and logs, including when started from another working directory.
- `springsettings.cfg` combines `launch/springsettings.cfg` and
  `launch/menu.cfg`. `DefaultLuaMenu = WasmMenu 1.0` opens the menu with no
  command-line arguments. No `script.txt` or wrapper launcher is needed.
  Keep the menu default out of the shared graphics profile, because isolated
  game verification does not stage a menu archive.
- `README.txt` comes from `release/README.txt.in`; `BUILDINFO.txt` records the
  shipped sources and resolved SDK/shared-crate dependencies.

The packager rejects WASM modules containing test markers and a menu older than
the embedded launch scripts. It warns about source inputs newer than installed
modules; release preparation always rebuilds them.

For a local development package without source archives or publishing, the
lower-level command remains available:

```bash
just package 2026.10.3001 --version test --platform linux
./release/package.sh --platform linux --no-archive --version test \
    --engine-dir linux=../spring-bar/build-amd64-linux/install
```

## Use the existing checks

```bash
just smoke-test release/out/SpringCabal-1.0.3-rc.3-linux
python3 verification/sdk-menu/run.py --packaged \
    --engine release/out/SpringCabal-1.0.3-rc.3-linux/SpringCabal \
    --output verification/out/packaged-menu-1.0.3-rc.3-linux
python3 verification/sdk-menu/run.py --packaged --wine wine \
    --engine release/out/SpringCabal-1.0.3-rc.3-windows/SpringCabal.exe \
    --output verification/out/packaged-menu-1.0.3-rc.3-windows
```

The smoke test runs all fourteen game entries and the menu offscreen on the
real GPU with the shipped settings. Errors, warnings, missing renderer identity
or software rendering fail it. The packaged-menu harness launches the actual
executable with no arguments from outside the bundle directory and checks
isolation, navigation, Lua Gravitas launch/return and clean exit. `--wine` takes
the Wine loader command or path; set `WINEPREFIX` for a dedicated prefix.
The keyboard menu checks require VirtualGL, Xvfb, xdotool and ImageMagick.
Set `VF_VGLRUN` if its launcher is outside `PATH`, and `VF_VGL_DISPLAY` to the
GPU's EGL device when needed (default: `egl`). These checks use the existing
verification lock and CPU/GPU idle guards, save `guard.json`, and reject software
rendering. `--max-minutes` controls how long they wait for an idle system.
Windows needs a working Wine installation or a native Windows play check. Check freshly
extracted archives too, and play at least one WASM and one Lua game on each
platform. See `verification/README.md` for the existing game-specific suites.
Packaged menu checks share read-only `.sdz` and `.sd7` files with their source
bundle when the filesystem supports hard links. Settings and other writable
files are copied separately, so testing does not change the prepared bundle.

## Publish

Write player-facing notes to a file outside the source tree (or commit them
before preparation). Release notes describe player-visible changes, the engine
tag and launch instructions. Keep validation reports in development logs; do
not add validation or known-limitations sections to release notes.

From the framework's clean `main` branch:

```bash
# Check assets/revisions and preview publication without changing Git or GitHub:
just release-publish 1.0.3-rc.3 /tmp/springcabal-1.0.3-rc.3-notes.md --dry-run --prerelease

# Push framework main + v1.0.3-rc.3, upload, verify checksums, and publish:
just release-publish 1.0.3-rc.3 /tmp/springcabal-1.0.3-rc.3-notes.md --prerelease

# Or upload and keep a draft for review:
./release/release.sh publish 1.0.3-rc.3 --notes /tmp/springcabal-1.0.3-rc.3-notes.md --draft --prerelease

# Publish a prerelease, leaving the latest stable release unchanged:
./release/release.sh publish 1.0.3-rc.3 --notes /tmp/springcabal-1.0.3-rc.3-notes.md --prerelease
```

The default title is `SpringCabal <version>`; pass `--title "..."` to change it.
Publication checks the exact prepared sources and asset checksums, creates an
annotated `v<version>` tag, and atomically pushes framework `main` and the tag
to `origin` (`gajop/springcabal-dev`). It uploads all five assets to a draft,
compares GitHub's SHA-256 digests with local files, then makes it the latest
stable release. `--prerelease` publishes a prerelease instead and preserves the
latest stable release; it can also be combined with `--draft`. `--draft` stops
after the digest check. The command can resume
an interrupted draft upload with the same prepared files. A checksum failure
leaves the release in draft form.

Already public releases and tags pointing at another commit are refused; use
a new version rather than replacing them. The scripts never build/push the
engine, trigger engine CI, or push individual content repositories. Publish
the engine binaries first when a new engine revision is needed.

To check changes to the release scripts themselves, run
`python3 release/test-release.py`. These tests use tiny temporary Git repositories
and a fake GitHub CLI; they do not build games or contact GitHub.
