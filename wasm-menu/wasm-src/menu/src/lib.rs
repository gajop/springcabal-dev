extern crate alloc;

use alloc::string::String;
use spring::config;

mod entry;
mod ui;

// Start scripts and graphics overrides live in launch/games/ at the repository
// root, the one source that run-wasm.sh, verification and the release smoke
// test also read.  They are compiled in, so rebuild the menu after editing them.
struct GameEntry {
    name: &'static str,
    authors: &'static str,
    start_script: &'static str,
    graphics: &'static str,
}

macro_rules! launch_file {
    ($game:literal, $file:literal) => {
        include_str!(concat!("../../../../launch/games/", $game, "/", $file))
    };
}

const NO_GRAPHICS: &str = "";
const AREA17_GRAPHICS: &str = launch_file!("area17", "graphics.cfg");
const HUNTED_GRAPHICS: &str = launch_file!("hunted", "graphics.cfg");
const GRAVITAS_EDITOR: &str = launch_file!("gravitas", "editor.txt");

struct GameDetails {
    built: &'static str,
    image: &'static str,
}

// Original jam dates, shared by the WASM and Lua versions in matching order.
// Sources and image provenance: WasmMenu/images/README.md.
static GAME_DETAILS: &[GameDetails] = &[
    GameDetails {
        built: "Apr 2015  |  Ludum Dare 32",
        image: "WasmMenu/images/gravitas.jpg",
    },
    GameDetails {
        built: "Aug 2015  |  Ludum Dare 33 warmup",
        image: "WasmMenu/images/hunted.png",
    },
    GameDetails {
        built: "Aug 2015  |  Ludum Dare 33",
        image: "WasmMenu/images/area17.jpg",
    },
    GameDetails {
        built: "Dec 2015  |  Ludum Dare 34",
        image: "WasmMenu/images/flove.png",
    },
    GameDetails {
        built: "Apr 2016  |  Ludum Dare 35",
        image: "WasmMenu/images/partsneeded.png",
    },
    GameDetails {
        built: "Aug 2018  |  Ludum Dare 42",
        image: "WasmMenu/images/mycube.png",
    },
    GameDetails {
        built: "Dec 2018  |  Ludum Dare 43",
        image: "WasmMenu/images/ttld.png",
    },
];

static WASM_GAMES: &[GameEntry] = &[
    GameEntry {
        name: "Gravitas (WASM)",
        authors: "Anarchid, ashdnazg, gajop, Picasso, Silentwings",
        start_script: launch_file!("gravitas", "wasm.txt"),
        graphics: NO_GRAPHICS,
    },
    GameEntry {
        name: "Zeus vs Bunnies (WASM)",
        authors: "ashdnazg, FLOZi, ForbodingAngel, gajop, GoogleFrog, Picasso",
        start_script: launch_file!("hunted", "wasm.txt"),
        graphics: HUNTED_GRAPHICS,
    },
    GameEntry {
        name: "Area 17 (WASM)",
        authors: "Anarchid, ashdnazg, ForbodingAngel, gajop, GoogleFrog",
        start_script: launch_file!("area17", "wasm.txt"),
        graphics: AREA17_GRAPHICS,
    },
    GameEntry {
        name: "Flove (WASM)",
        authors: "Anarchid, ForbodingAngel, gajop, Jared Bauer, Krystal, Silentwings, smoth",
        start_script: launch_file!("flove", "wasm.txt"),
        graphics: NO_GRAPHICS,
    },
    GameEntry {
        name: "Parts Needed (WASM)",
        authors: "Anarchid, gajop, greze, smoth",
        start_script: launch_file!("partsneeded", "wasm.txt"),
        graphics: NO_GRAPHICS,
    },
    GameEntry {
        name: "MyCube (WASM)",
        authors: "Anarchid, gajop, PicassoCT",
        start_script: launch_file!("mycube", "wasm.txt"),
        graphics: NO_GRAPHICS,
    },
    GameEntry {
        name: "To the Last Drop (WASM)",
        authors: "ashdnazg, gajop, GoogleFrog, J3Jumby, silentwings",
        start_script: launch_file!("ttld", "wasm.txt"),
        graphics: NO_GRAPHICS,
    },
];

static LUA_GAMES: &[GameEntry] = &[
    GameEntry {
        name: "Gravitas",
        authors: "Anarchid, ashdnazg, gajop, Picasso, Silentwings",
        start_script: launch_file!("gravitas", "lua.txt"),
        graphics: NO_GRAPHICS,
    },
    GameEntry {
        name: "Zeus vs Bunnies",
        authors: "ashdnazg, FLOZi, ForbodingAngel, gajop, GoogleFrog, Picasso",
        start_script: launch_file!("hunted", "lua.txt"),
        graphics: HUNTED_GRAPHICS,
    },
    GameEntry {
        name: "Area 17",
        authors: "Anarchid, ashdnazg, ForbodingAngel, gajop, GoogleFrog",
        start_script: launch_file!("area17", "lua.txt"),
        graphics: AREA17_GRAPHICS,
    },
    GameEntry {
        name: "Flove",
        authors: "Anarchid, ForbodingAngel, gajop, Jared Bauer, Krystal, Silentwings, smoth",
        start_script: launch_file!("flove", "lua.txt"),
        graphics: NO_GRAPHICS,
    },
    GameEntry {
        name: "Parts Needed",
        authors: "Anarchid, gajop, greze, smoth",
        start_script: launch_file!("partsneeded", "lua.txt"),
        graphics: NO_GRAPHICS,
    },
    GameEntry {
        name: "My Cube",
        authors: "Anarchid, gajop, PicassoCT",
        start_script: launch_file!("mycube", "lua.txt"),
        graphics: NO_GRAPHICS,
    },
    GameEntry {
        name: "To the Last Drop",
        authors: "ashdnazg, gajop, GoogleFrog, J3Jumby, silentwings",
        start_script: launch_file!("ttld", "lua.txt"),
        graphics: NO_GRAPHICS,
    },
];

// Applies launch/games/<game>/graphics.cfg ("Key = value" lines) for this
// session only, on top of the player's springsettings.cfg.
fn apply_game_graphics(game: &GameEntry) {
    for line in game.graphics.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some((key, value)) = line.split_once('=') {
            let _ = config::set_config_string(key.trim(), value.trim(), true);
        }
    }
}

fn make_start_script(game: &GameEntry) -> String {
    String::from(game.start_script)
}

fn make_editor_start_script(_game: &GameEntry) -> String {
    String::from(GRAVITAS_EDITOR)
}
