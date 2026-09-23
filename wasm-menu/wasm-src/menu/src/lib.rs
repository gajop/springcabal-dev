extern crate alloc;

use alloc::format;
use alloc::string::String;
use spring::config;

mod entry;
mod ui;

struct GameEntry {
    name: &'static str,
    game_type: &'static str,
    map_name: &'static str,
    authors: &'static str,
}

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
        game_type: "Gravitas WASM 0.1.0-wasm",
        map_name: "Gravitas Enterprise",
        authors: "Anarchid, ashdnazg, gajop, Picasso, Silentwings",
    },
    GameEntry {
        name: "Zeus vs Bunnies (WASM)",
        game_type: "Hunted WASM 0.1.0-wasm",
        map_name: "Hunted - v04",
        authors: "ashdnazg, FLOZi, ForbodingAngel, gajop, GoogleFrog, Picasso",
    },
    GameEntry {
        name: "Area 17 (WASM)",
        game_type: "Area 17 WASM 0.1.0-wasm",
        map_name: "Area 17 - v01",
        authors: "Anarchid, ashdnazg, ForbodingAngel, gajop, GoogleFrog",
    },
    GameEntry {
        name: "Flove (WASM)",
        game_type: "Flove WASM 0.1.0-wasm",
        map_name: "The Grove 0.3",
        authors: "Anarchid, ForbodingAngel, gajop, Jared Bauer, Krystal, Silentwings, smoth",
    },
    GameEntry {
        name: "Parts Needed (WASM)",
        game_type: "Parts Needed WASM 0.1.0-wasm",
        map_name: "LD35 map 0.1",
        authors: "Anarchid, gajop, greze, smoth",
    },
    GameEntry {
        name: "MyCube (WASM)",
        game_type: "MyCube WASM 0.1.0-wasm",
        map_name: "MyCube v1 WASM",
        authors: "Anarchid, gajop, PicassoCT",
    },
    GameEntry {
        name: "To the Last Drop (WASM)",
        game_type: "To the Last Drop WASM 0.1.0-wasm",
        map_name: "Eyam",
        authors: "ashdnazg, gajop, GoogleFrog, J3Jumby, silentwings",
    },
];

static LUA_GAMES: &[GameEntry] = &[
    GameEntry {
        name: "Gravitas",
        game_type: "Scenario Editor Gravitas git",
        map_name: "Gravitas Enterprise",
        authors: "Anarchid, ashdnazg, gajop, Picasso, Silentwings",
    },
    GameEntry {
        name: "Zeus vs Bunnies",
        game_type: "Hunted $VERSION",
        map_name: "Hunted - v04",
        authors: "ashdnazg, FLOZi, ForbodingAngel, gajop, GoogleFrog, Picasso",
    },
    GameEntry {
        name: "Area 17",
        game_type: "Area 17 $VERSION",
        map_name: "Area 17 - v01",
        authors: "Anarchid, ashdnazg, ForbodingAngel, gajop, GoogleFrog",
    },
    GameEntry {
        name: "Flove",
        game_type: "Flove $VERSION",
        map_name: "The Grove 0.3",
        authors: "Anarchid, ForbodingAngel, gajop, Jared Bauer, Krystal, Silentwings, smoth",
    },
    GameEntry {
        name: "Parts Needed",
        game_type: "Parts Needed $VERSION",
        map_name: "LD35 map 0.1",
        authors: "Anarchid, gajop, greze, smoth",
    },
    GameEntry {
        name: "My Cube",
        // Lua archive title: ModInfo.lua name + version.
        game_type: "Ludum Dare 42 Git",
        map_name: "MyCube",
        authors: "Anarchid, gajop, PicassoCT",
    },
    GameEntry {
        name: "To the Last Drop",
        game_type: "To the last Drop $VERSION",
        map_name: "Eyam",
        authors: "ashdnazg, gajop, GoogleFrog, J3Jumby, silentwings",
    },
];

fn apply_game_graphics(game: &GameEntry) {
    if game.game_type.starts_with("Area 17") {
        let _ = config::set_config_int("MaxParticles", 200_000, true);
        let _ = config::set_config_int("Shadows", 1, true);
        let _ = config::set_config_int("Water", 4, true);
    } else if game.game_type.starts_with("Hunted") {
        let _ = config::set_config_int("Shadows", 0, true);
    }
}

fn format_start_script(game: &GameEntry, mod_options: &str) -> String {
    // Flove assigns the grove to team 1 and mushrooms to team 0.
    let (player_team, ai_team) = if game.game_type.starts_with("Flove") {
        (1, 0)
    } else {
        (0, 1)
    };
    format!(
        r#"[GAME]
{{
    MapName={map};
    GameMode=0;
    GameType={game_type};

    NumTeams=2;
    NumUsers=2;

    HostIP=127.0.0.1;
    HostPort=8452;
    IsHost=1;
    NumPlayers=1;
    GameStartDelay=0;

    StartMetal=1000;
    StartEnergy=1000;

    StartposType=3;
    LimitDGun=0;
    DiminishingMMs=0;
    GhostedBuildings=1;
    MyPlayerNum=1;
    MyPlayerName=0;
    NumRestrictions=0;
    MaxSpeed=20;
    MinSpeed=0.1;

    [TEAM0]
    {{
        AllyTeam=0;
        Side=;
        RGBColor=0.35294118523598 0.35294118523598 1;
        TeamLeader=1;
        Handicap=0;
        StartPosX=0;
        StartPosZ=0;
    }}
    [PLAYER1]
    {{
        Name=0;
        Spectator=0;
        Team={player_team};
    }}
    [TEAM1]
    {{
        AllyTeam=1;
        Side=;
        RGBColor=0.7843137383461 0 0;
        TeamLeader=1;
        Handicap=0;
        StartPosX=0;
        StartPosZ=0;
    }}
    [AI1]
    {{
        Name=1: NullAI;
        ShortName=NullAI;
        Team={ai_team};
        IsFromDemo=0;
        Host=1;
        [Options] {{}}
    }}
    [ALLYTEAM0]
    {{
        NumAllies=0;
    }}
    [ALLYTEAM1]
    {{
        NumAllies=0;
    }}
{mod_options}
}}
"#,
        map = game.map_name,
        game_type = game.game_type,
        mod_options = mod_options,
    )
}

fn make_start_script(game: &GameEntry) -> String {
    let mod_options = if game.game_type.starts_with("Area 17") {
        "    [MODOPTIONS]\n    {\n        DisableMapDamage=0;\n    }\n"
    } else if game.game_type.starts_with("Parts Needed") {
        // The original defaults to its editor when this is absent.  Play mode
        // locks the camera/input and removes the developer play/stop widget.
        "    [MODOPTIONS]\n    {\n        gamemode=play;\n    }\n"
    } else if game.game_type.starts_with("Scenario Editor Gravitas") {
        "    [MODOPTIONS]\n    {\n        play_mode=1;\n        deathmode=neverend;\n        has_scenario_file=0;\n        project_dir=projects/Gravity-Enterprise;\n    }\n"
    } else {
        ""
    };
    format_start_script(game, mod_options)
}

fn make_editor_start_script(game: &GameEntry) -> String {
    let mod_options = "    [MODOPTIONS]\n    {\n        play_mode=0;\n        deathmode=neverend;\n        has_scenario_file=0;\n        project_dir=projects/Gravity-Enterprise;\n    }\n";
    format_start_script(game, mod_options)
}
