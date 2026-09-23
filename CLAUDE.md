# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SpringCabal Games is a collection of Spring RTS games developed by SpringCabal, primarily created for Ludum Dare game jams and experimental projects. The games run on the Recoil engine (a fork of the Spring RTS engine) and are written primarily in Lua.

## Setup and Running

### Initial Setup
```bash
# Clone every game/map repo listed in content.tsv into spring-linux/, and
# optionally download a Linux engine release into engine/<tag>
./setup.sh --engine-tag 2026.09.23
```
`content.tsv` is the single list of games, maps and projects: source repo,
branch, and whether the release ships it. Entries marked `local`/`download`
(and the unpublished `*-wasm-port` branches) exist only on this machine.

`springsettings-custom.cfg` holds the settings the games are tuned for
(GroundDetail, MaxMapDetail, LODScale, ...); release bundles append it to
their portable `springsettings.cfg`.

### Running Games

The WASM games are the active work, and they run on the locally built
experimental engine, **not** on `spring-linux/spring`:
```bash
# Launch the WASM menu and pick a game
./run-wasm.sh

# Launch one WASM game directly
./run-wasm.sh --game flove      # also: hunted, area17, ttld
```
`run-wasm.sh` runs `$SPRING_ENGINE_DIR/spring`, else
`$SPRING_BAR_DIR/build-amd64-linux/install/spring` (default `../spring-bar`),
else `engine/current/spring` from setup. It builds an isolated
launch view under `wasm-test/`, and prints an error/warning summary from the
session log when it exits. Rebuild that engine with
`./docker-build-v2/build.sh linux` in the spring-bar checkout. Rebuild a game's
guest modules with `just copy` in its `wasm-src/`.

The original Lua versions are launched from the same WASM menu (each row has
WASM and Lua buttons).

### Releases

`release/package.sh` builds Linux/Windows bundles locally from the checkouts;
`release/smoke-test.sh` checks one. See `RELEASING.md`.

## Project Structure

- `spring-linux/` - engine installation plus all game and map archives. The
  `spring` binary here is **not** the 2025.01.6 release; it is a local
  `rust-wip` build (check `Spring Engine Version` in any infolog). There is no
  pre-fork engine checked in to compare rendering against.
- `spring-linux/games/*.sdd/` - Individual game directories
- `spring-linux/maps/*.sdd/` - Map directories
- `projects/` - Additional project files and scenario editors

### Game Directories Structure
Each game follows this pattern:
- `modinfo.lua` - Game metadata and version info
- `engineoptions.lua` - Engine configuration
- `modoptions.lua` - Game-specific options
- `GameData/` - Core game rules and definitions
- `LuaRules/` - Server-side Lua scripts
- `LuaUI/` - Client-side UI scripts  
- `Units/` - Unit definitions
- `Objects3d/` - 3D models (DAE format)
- `Scripts/` - Unit behavior scripts
- `sounds/` - Audio files
- `effects/` - Visual effects definitions

## Game Status

`TODO.md` has the current rating of every WASM and Lua version and the rating
scale.

## Development Guidelines

### Lua Conventions
- Use existing Lua libraries from games like Flove (SpringABC, analytics, lcs, i18n)
- Follow Spring engine Lua API patterns
- Game logic goes in `LuaRules/`, UI in `LuaUI/`
- Unit definitions use Spring's unit definition format

### Git Workflow  
- Use `git clone --recursive` for repositories with submodules
- Many games depend on shared resources and libraries
- Check existing games for reference implementations

### Common File Patterns
- `*.lua` - Lua scripts and configuration
- `*.dae` - 3D models with optional `.lua` material files
- `*.sdd` - Spring game/map directories
- `*.sdz` - Spring archive files (zipped .sdd)

### Debugging

#### Log Analysis Workflow
1. Run game via `./run-wasm.sh`
2. Check for visual defects during gameplay
3. Analyze error logs: `wasm-test/write/infolog.txt` plus the per-session copy
   under `wasm-test/write/logs/`

#### Verification Suites

Every game's automated checks live in `verification/`:

```bash
./verification/verify list
./verification/verify flove              # default mode (headless)
./verification/verify flove visual
./verification/verify all                # every suite
```

Modes are per game: `static` (build hygiene), `headless` (in-game assertions
under spring-headless), `visual` (xvfb + software GL, screenshot checks), plus
image comparisons (`flove outline`, `gravitas shots`). Logs and screenshots land
in `verification/out/<suite>/`. Shared plumbing is `verification/lib/common.sh`;
see `verification/README.md` before adding a suite.

#### Automated Error Detection
Claude can automatically analyze infolog.txt for errors and suggest solutions:

```bash
# To analyze current log for errors:
# Ask Claude: "Analyze spring-linux/infolog.txt for errors and suggest fixes"

# For continuous monitoring during testing:
# Ask Claude: "Monitor spring-linux/infolog.txt for new errors while I test games"
```

**Common Error Patterns to Look For:**
- Lua script errors and stack traces
- Missing file/resource errors
- OpenGL/shader compilation failures
- Unit definition errors
- Sound system issues
- Network/multiplayer errors

#### Manual Debugging Steps
- Games may need specific engine options or shadow settings disabled
- Use Spring's built-in Lua debugging capabilities
- Check mod-specific logs in game directories

## Technical Notes

- Engine: Recoil `rust-wip` (Spring RTS fork), built from the spring-bar checkout
- Primary language: Lua for game logic, configuration, and UI
- 3D graphics: OpenGL with GLSL shaders
- Audio: WAV and OGG support
- Supports mod/scenario editor for Gravitas game

When working on broken games, prioritize understanding the specific error patterns mentioned in TODO.md and test with minimal configurations first.