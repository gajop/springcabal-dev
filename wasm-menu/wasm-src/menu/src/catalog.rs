use alloc::vec::Vec;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Variant {
    Wasm,
    Lua,
    Editor,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Action {
    Launch { game: usize, variant: Variant },
    Quit,
}

pub struct Game {
    pub name: &'static str,
    pub authors: &'static str,
    pub built: &'static str,
    pub image: &'static str,
    pub article: &'static str,
    pub wasm: &'static str,
    pub lua: &'static str,
    pub editor: Option<&'static str>,
    pub graphics: &'static str,
}

impl Game {
    pub fn script(&self, variant: Variant) -> Option<&'static str> {
        match variant {
            Variant::Wasm => Some(self.wasm),
            Variant::Lua => Some(self.lua),
            Variant::Editor => self.editor,
        }
    }
}

macro_rules! launch_file {
    ($game:literal, $file:literal) => {
        include_str!(concat!("../../../../launch/games/", $game, "/", $file))
    };
}

pub static GAMES: &[Game] = &[
    Game {
        name: "Gravitas",
        authors: "Anarchid, ashdnazg, gajop, Picasso, Silentwings",
        built: "Apr 2015  |  Ludum Dare 32",
        image: "images/gravitas.jpg",
        article: include_str!("../../../../game-info/gravitas/README.md"),
        wasm: launch_file!("gravitas", "wasm.txt"),
        lua: launch_file!("gravitas", "lua.txt"),
        editor: Some(launch_file!("gravitas", "editor.txt")),
        graphics: "",
    },
    Game {
        name: "Zeus vs Bunnies",
        authors: "ashdnazg, FLOZi, ForbodingAngel, gajop, GoogleFrog, Picasso",
        built: "Aug 2015  |  Ludum Dare 33 warmup",
        image: "images/hunted.png",
        article: include_str!("../../../../game-info/zeus-vs-bunnies/README.md"),
        wasm: launch_file!("hunted", "wasm.txt"),
        lua: launch_file!("hunted", "lua.txt"),
        editor: None,
        graphics: launch_file!("hunted", "graphics.cfg"),
    },
    Game {
        name: "Area 17",
        authors: "Anarchid, ashdnazg, ForbodingAngel, gajop, GoogleFrog",
        built: "Aug 2015  |  Ludum Dare 33",
        image: "images/area17.jpg",
        article: include_str!("../../../../game-info/area-17/README.md"),
        wasm: launch_file!("area17", "wasm.txt"),
        lua: launch_file!("area17", "lua.txt"),
        editor: None,
        graphics: launch_file!("area17", "graphics.cfg"),
    },
    Game {
        name: "Flove",
        authors: "Anarchid, ForbodingAngel, gajop, Jared Bauer, Krystal, Silentwings, smoth",
        built: "Dec 2015  |  Ludum Dare 34",
        image: "images/flove.png",
        article: include_str!("../../../../game-info/flove/README.md"),
        wasm: launch_file!("flove", "wasm.txt"),
        lua: launch_file!("flove", "lua.txt"),
        editor: None,
        graphics: "",
    },
    Game {
        name: "Parts Needed",
        authors: "Anarchid, gajop, greze, smoth",
        built: "Apr 2016  |  Ludum Dare 35",
        image: "images/partsneeded.png",
        article: include_str!("../../../../game-info/parts-needed/README.md"),
        wasm: launch_file!("partsneeded", "wasm.txt"),
        lua: launch_file!("partsneeded", "lua.txt"),
        editor: None,
        graphics: "",
    },
    Game {
        name: "MyCube",
        authors: "Anarchid, gajop, PicassoCT",
        built: "Aug 2018  |  Ludum Dare 42",
        image: "images/mycube.png",
        article: include_str!("../../../../game-info/my-cube/README.md"),
        wasm: launch_file!("mycube", "wasm.txt"),
        lua: launch_file!("mycube", "lua.txt"),
        editor: None,
        graphics: "",
    },
    Game {
        name: "To the Last Drop",
        authors: "ashdnazg, gajop, GoogleFrog, J3Jumby, silentwings",
        built: "Dec 2018  |  Ludum Dare 43",
        image: "images/ttld.png",
        article: include_str!("../../../../game-info/to-the-last-drop/README.md"),
        wasm: launch_file!("ttld", "wasm.txt"),
        lua: launch_file!("ttld", "lua.txt"),
        editor: None,
        graphics: "",
    },
];

pub fn actions() -> Vec<Action> {
    let mut actions = Vec::new();
    for (game, entry) in GAMES.iter().enumerate() {
        for variant in [Variant::Wasm, Variant::Lua, Variant::Editor] {
            if entry.script(variant).is_some() {
                actions.push(Action::Launch { game, variant });
            }
        }
    }
    actions.push(Action::Quit);
    actions
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn catalogue_metadata_and_shipped_assets_are_valid() {
        let assets = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../WasmMenu");
        let mut names = std::collections::BTreeSet::new();
        for game in GAMES {
            assert!(!game.name.trim().is_empty());
            assert!(
                names.insert(game.name),
                "duplicate game name: {}",
                game.name
            );
            assert!(
                game.authors
                    .split(',')
                    .all(|author| !author.trim().is_empty())
            );
            assert!(
                !game.built.trim().is_empty(),
                "missing date for {}",
                game.name
            );
            assert!(
                assets.join(game.image).is_file(),
                "missing image for {}: {}",
                game.name,
                game.image
            );
            for line in game.graphics.lines().map(str::trim) {
                if line.is_empty() || line.starts_with('#') {
                    continue;
                }
                let (key, value) = line
                    .split_once('=')
                    .expect("graphics override needs key=value");
                assert!(
                    !key.trim().is_empty() && !value.trim().is_empty(),
                    "invalid graphics override for {}: {line}",
                    game.name
                );
            }
        }
    }

    #[test]
    fn launch_actions_follow_the_visible_row_order() {
        let actions = actions();
        assert_eq!(actions.len(), 16);
        assert_eq!(
            &actions[..4],
            &[
                Action::Launch {
                    game: 0,
                    variant: Variant::Wasm
                },
                Action::Launch {
                    game: 0,
                    variant: Variant::Lua
                },
                Action::Launch {
                    game: 0,
                    variant: Variant::Editor
                },
                Action::Launch {
                    game: 1,
                    variant: Variant::Wasm
                },
            ]
        );
        assert_eq!(actions.last(), Some(&Action::Quit));
        for action in actions {
            if let Action::Launch { game, variant } = action {
                assert!(GAMES[game].script(variant).is_some());
            }
        }
    }
}
