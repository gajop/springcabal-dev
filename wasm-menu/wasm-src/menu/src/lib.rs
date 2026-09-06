extern crate alloc;

use alloc::format;
use alloc::string::String;
use core::cell::Cell;
use spring::{config, gfx, system_control};

spring::export_callin_scratch!(4096);
spring::export_environment_mask!(spring::menu::ENVIRONMENT_MASK);
spring::export_draw_screen!(draw_screen);
spring::export_key_press!(key_press);
spring::export_mouse_move!(mouse_move);
spring::export_mouse_press!(mouse_press);
spring::export_view_resize!(view_resize);

// Public API

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum MenuSelection {
    Wasm(usize),
    Lua(usize),
    Quit,
}

pub fn draw_screen(view_size_x: i32, view_size_y: i32) {
    // The engine keeps the menu registered as an event client while a game
    // runs, so DrawScreen keeps arriving. Input already gates on menu_active();
    // without the same gate here the menu paints over the running game.
    if !menu_active() {
        return;
    }
    let vw = view_size_x as f32;
    let vh = view_size_y as f32;

    VIEW_SIZE.with(|v| v.set((vw, vh)));

    let selection = SELECTED.with(|s| s.get());

    // Deep dark background
    let _ = gfx::color(0.04, 0.06, 0.08, 0.95);
    let _ = gfx::rect(0.0, 0.0, vw, vh);

    let _ = gfx::begin_text(false);

    // Header Title
    let title_y = vh * 0.90;
    let _ = gfx::color(1.0, 1.0, 1.0, 1.0);
    let _ = gfx::text("SPRING CABAL GAMES", vw / 2.0, title_y, 36.0, "cson");

    let _ = gfx::color(0.55, 0.75, 0.85, 1.0);
    let _ = gfx::text(
        "WASM & Lua Game Selector",
        vw / 2.0,
        title_y - 34.0,
        17.0,
        "con",
    );

    let (col_wasm_x, col_lua_x, card_w, start_y, item_spacing) = compute_layout(vw, vh);

    let header_y = vh * 0.77;
    let header_sub_y = vh * 0.735;

    // WASM Column Header
    let _ = gfx::color(0.2, 0.85, 1.0, 1.0);
    let _ = gfx::text("WASM PORTS", col_wasm_x, header_y, 22.0, "cson");
    let _ = gfx::color(0.5, 0.75, 0.85, 0.8);
    let _ = gfx::text(
        "(Rust Core-WASM + RmlUi)",
        col_wasm_x,
        header_sub_y,
        13.0,
        "con",
    );

    // Lua Column Header
    let _ = gfx::color(1.0, 0.75, 0.3, 1.0);
    let _ = gfx::text("ORIGINAL LUA", col_lua_x, header_y, 22.0, "cson");
    let _ = gfx::color(0.85, 0.65, 0.45, 0.8);
    let _ = gfx::text(
        "(Legacy Engine Scripts)",
        col_lua_x,
        header_sub_y,
        13.0,
        "con",
    );

    // Render WASM Games
    for (i, game) in WASM_GAMES.iter().enumerate() {
        let y = start_y - (i as f32) * item_spacing;
        let is_sel = selection == MenuSelection::Wasm(i);
        draw_card(col_wasm_x, y, card_w, game.name, game.authors, is_sel, true);
    }

    // Render Lua Games
    for (i, game) in LUA_GAMES.iter().enumerate() {
        let y = start_y - (i as f32) * item_spacing;
        let is_sel = selection == MenuSelection::Lua(i);
        draw_card(col_lua_x, y, card_w, game.name, game.authors, is_sel, false);
    }

    // Quit Button
    let (quit_cx, quit_y) = (vw / 2.0, vh * 0.12);
    let is_quit_sel = selection == MenuSelection::Quit;
    if is_quit_sel {
        let _ = gfx::color(0.85, 0.25, 0.25, 0.5);
        let _ = gfx::rect(quit_cx - 90.0, quit_y - 20.0, quit_cx + 90.0, quit_y + 20.0);
        let _ = gfx::color(1.0, 0.95, 0.95, 1.0);
    } else {
        let _ = gfx::color(0.2, 0.22, 0.28, 0.4);
        let _ = gfx::rect(quit_cx - 90.0, quit_y - 20.0, quit_cx + 90.0, quit_y + 20.0);
        let _ = gfx::color(0.7, 0.7, 0.7, 1.0);
    }
    let _ = gfx::text("QUIT", quit_cx, quit_y - 7.0, 20.0, "cson");

    // Instructions footer
    let _ = gfx::color(0.6, 0.65, 0.7, 0.85);
    let _ = gfx::text(
        "Click to launch  |  Arrow keys to navigate  |  Enter to start  |  ESC to quit",
        vw / 2.0,
        vh * 0.05,
        14.0,
        "con",
    );

    // Error banner if any reload error occurred
    ERROR_MSG.with(|err| {
        let err_borrow = err.borrow();
        if let Some(msg) = err_borrow.as_ref() {
            let _ = gfx::color(0.8, 0.1, 0.1, 0.9);
            let _ = gfx::rect(vw * 0.1, vh * 0.01, vw * 0.9, vh * 0.08);
            let _ = gfx::color(1.0, 1.0, 1.0, 1.0);
            let _ = gfx::text(msg, vw / 2.0, vh * 0.035, 15.0, "cson");
        }
    });

    let _ = gfx::end_text(0);
}

pub fn mouse_move(x: i32, y: i32, _dx: i32, _dy: i32, _button: i32) -> bool {
    if !menu_active() {
        return false;
    }
    let (vw, vh) = VIEW_SIZE.with(|v| v.get());
    if vw <= 0.0 || vh <= 0.0 {
        return false;
    }

    if let Some(sel) = hit_test(x as f32, y as f32, vw, vh) {
        SELECTED.with(|s| s.set(sel));
        return true;
    }
    false
}

pub fn mouse_press(x: i32, y: i32, button: i32) -> bool {
    if button != 1 || !menu_active() {
        return false;
    }
    let (vw, vh) = VIEW_SIZE.with(|v| v.get());
    if vw <= 0.0 || vh <= 0.0 {
        return false;
    }

    if let Some(sel) = hit_test(x as f32, y as f32, vw, vh) {
        SELECTED.with(|s| s.set(sel));
        match sel {
            MenuSelection::Wasm(idx) => launch_game(&WASM_GAMES[idx]),
            MenuSelection::Lua(idx) => launch_game(&LUA_GAMES[idx]),
            MenuSelection::Quit => {
                let _ = system_control::quit(0);
            }
        }
        return true;
    }
    false
}

#[allow(clippy::too_many_arguments)]
pub fn view_resize(
    _screen_size_x: i32,
    _screen_size_y: i32,
    _screen_pos_x: i32,
    _screen_pos_y: i32,
    _window_size_x: i32,
    _window_size_y: i32,
    _window_pos_x: i32,
    _window_pos_y: i32,
    _window_border_top: i32,
    _window_border_left: i32,
    _window_border_bottom: i32,
    _window_border_right: i32,
    view_size_x: i32,
    view_size_y: i32,
    _view_pos_x: i32,
    _view_pos_y: i32,
) {
    VIEW_SIZE.with(|v| v.set((view_size_x as f32, view_size_y as f32)));
}

pub fn key_press(
    key_code: i32,
    _alt: bool,
    _ctrl: bool,
    _meta: bool,
    _shift: bool,
    _is_repeat: bool,
    _label: &[u8],
    _utf32_char: i32,
    _scan_code: i32,
    _action_list: impl Iterator<Item = (&'static [u8], &'static [u8], &'static [u8])>,
) -> bool {
    if !menu_active() {
        return false;
    }
    match key_code {
        276 => {
            // LEFT
            SELECTED.with(|s| {
                let next = match s.get() {
                    MenuSelection::Lua(idx) => MenuSelection::Wasm(idx.min(WASM_GAMES.len() - 1)),
                    MenuSelection::Quit => MenuSelection::Wasm(WASM_GAMES.len() - 1),
                    wasm => wasm,
                };
                s.set(next);
            });
            true
        }
        275 => {
            // RIGHT
            SELECTED.with(|s| {
                let next = match s.get() {
                    MenuSelection::Wasm(idx) => MenuSelection::Lua(idx.min(LUA_GAMES.len() - 1)),
                    MenuSelection::Quit => MenuSelection::Lua(LUA_GAMES.len() - 1),
                    lua => lua,
                };
                s.set(next);
            });
            true
        }
        273 => {
            // UP
            SELECTED.with(|s| {
                let next = match s.get() {
                    MenuSelection::Wasm(0) => MenuSelection::Quit,
                    MenuSelection::Wasm(idx) => MenuSelection::Wasm(idx - 1),
                    MenuSelection::Lua(0) => MenuSelection::Quit,
                    MenuSelection::Lua(idx) => MenuSelection::Lua(idx - 1),
                    MenuSelection::Quit => MenuSelection::Wasm(WASM_GAMES.len() - 1),
                };
                s.set(next);
            });
            true
        }
        274 => {
            // DOWN
            SELECTED.with(|s| {
                let next = match s.get() {
                    MenuSelection::Wasm(idx) if idx + 1 >= WASM_GAMES.len() => MenuSelection::Quit,
                    MenuSelection::Wasm(idx) => MenuSelection::Wasm(idx + 1),
                    MenuSelection::Lua(idx) if idx + 1 >= LUA_GAMES.len() => MenuSelection::Quit,
                    MenuSelection::Lua(idx) => MenuSelection::Lua(idx + 1),
                    MenuSelection::Quit => MenuSelection::Wasm(0),
                };
                s.set(next);
            });
            true
        }
        27 => {
            // ESC
            let _ = system_control::quit(0);
            true
        }
        13 => {
            // ENTER
            match SELECTED.with(|s| s.get()) {
                MenuSelection::Wasm(idx) => launch_game(&WASM_GAMES[idx]),
                MenuSelection::Lua(idx) => launch_game(&LUA_GAMES[idx]),
                MenuSelection::Quit => {
                    let _ = system_control::quit(0);
                }
            }
            true
        }
        _ => false,
    }
}

// Helpers

fn menu_active() -> bool {
    system_control::get_game_name(0).is_ok_and(|name| name.is_empty())
}

struct GameEntry {
    name: &'static str,
    game_type: &'static str,
    map_name: &'static str,
    authors: &'static str,
}

static WASM_GAMES: &[GameEntry] = &[
    GameEntry {
        name: "Flove (WASM)",
        game_type: "Flove WASM 0.1.0-wasm",
        map_name: "The Grove 0.3",
        authors: "Anarchid, ForbodingAngel, gajop, Jared Bauer, Krystal, Silentwings, smoth",
    },
    GameEntry {
        name: "Hunted (WASM)",
        game_type: "Hunted WASM 0.1.0-wasm",
        map_name: "Hunted - v04",
        authors: "ashdnazg, FLOZi, ForbodingAngel, gajop, GoogleFrog, Picasso",
    },
    GameEntry {
        name: "To the Last Drop (WASM)",
        game_type: "To the Last Drop WASM 0.1.0-wasm",
        map_name: "Eyam",
        authors: "gajop, Bluestone",
    },
    GameEntry {
        name: "Area 17 (WASM)",
        game_type: "Area 17 WASM 0.1.0-wasm",
        map_name: "Area 17 - v01",
        authors: "Anarchid, ashdnazg, ForbodingAngel, gajop, GoogleFrog",
    },
    GameEntry {
        name: "Gravitas (WASM)",
        game_type: "Gravitas WASM 0.1.0-wasm",
        map_name: "Gravitas Enterprise",
        authors: "Anarchid, ashdnazg, gajop, Picasso, Silentwings",
    },
    GameEntry {
        name: "MyCube (WASM)",
        game_type: "MyCube WASM 0.1.0-wasm",
        map_name: "MyCube v1 WASM",
        authors: "",
    },
    GameEntry {
        name: "Parts Needed (WASM)",
        game_type: "Parts Needed WASM 0.1.0-wasm",
        map_name: "LD35 map 0.1",
        authors: "",
    },
];

static LUA_GAMES: &[GameEntry] = &[
    GameEntry {
        name: "Flove",
        game_type: "Flove $VERSION",
        map_name: "The Grove 0.3",
        authors: "Anarchid, ForbodingAngel, gajop, Jared Bauer, Krystal, Silentwings, smoth",
    },
    GameEntry {
        name: "Hunted",
        game_type: "Hunted $VERSION",
        map_name: "Hunted - v04",
        authors: "ashdnazg, FLOZi, ForbodingAngel, gajop, GoogleFrog, Picasso",
    },
    GameEntry {
        name: "To the Last Drop",
        game_type: "To the last Drop $VERSION",
        map_name: "Eyam",
        authors: "gajop, Bluestone",
    },
    GameEntry {
        name: "Area 17",
        game_type: "Area 17 $VERSION",
        map_name: "Area 17 - v01",
        authors: "Anarchid, ashdnazg, ForbodingAngel, gajop, GoogleFrog",
    },
    GameEntry {
        name: "Gravitas",
        game_type: "Scenario Editor Gravitas git",
        map_name: "Gravitas Enterprise",
        authors: "Anarchid, ashdnazg, gajop, Picasso, Silentwings",
    },
    GameEntry {
        name: "MyCube",
        game_type: "Ludum Dare 42",
        map_name: "MyCube v1 WASM",
        authors: "",
    },
    GameEntry {
        name: "Parts Needed",
        game_type: "Parts Needed $VERSION",
        map_name: "LD35 map 0.1",
        authors: "",
    },
];

thread_local! {
    static SELECTED: Cell<MenuSelection> = const { Cell::new(MenuSelection::Wasm(0)) };
    static VIEW_SIZE: Cell<(f32, f32)> = const { Cell::new((0.0, 0.0)) };
    static ERROR_MSG: core::cell::RefCell<Option<String>> = const { core::cell::RefCell::new(None) };
}

fn compute_layout(vw: f32, vh: f32) -> (f32, f32, f32, f32, f32) {
    let gap = (vw * 0.12).clamp(100.0, 180.0);
    let card_w = ((vw - gap - 160.0) / 2.0).clamp(320.0, 420.0);
    let col_wasm_x = (vw / 2.0) - (card_w / 2.0) - (gap / 2.0);
    let col_lua_x = (vw / 2.0) + (card_w / 2.0) + (gap / 2.0);
    let item_spacing = 68.0;
    let start_y = vh * 0.65;
    (col_wasm_x, col_lua_x, card_w, start_y, item_spacing)
}

fn hit_test(mx: f32, my: f32, vw: f32, vh: f32) -> Option<MenuSelection> {
    let (col_wasm_x, col_lua_x, card_w, start_y, item_spacing) = compute_layout(vw, vh);

    let card_half_w = card_w / 2.0;

    // Check WASM column
    for i in 0..WASM_GAMES.len() {
        let y = start_y - (i as f32) * item_spacing;
        if mx >= col_wasm_x - card_half_w
            && mx <= col_wasm_x + card_half_w
            && my >= y - 26.0
            && my <= y + 26.0
        {
            return Some(MenuSelection::Wasm(i));
        }
    }

    // Check Lua column
    for i in 0..LUA_GAMES.len() {
        let y = start_y - (i as f32) * item_spacing;
        if mx >= col_lua_x - card_half_w
            && mx <= col_lua_x + card_half_w
            && my >= y - 26.0
            && my <= y + 26.0
        {
            return Some(MenuSelection::Lua(i));
        }
    }

    // Check Quit button
    let quit_cx = vw / 2.0;
    let quit_y = vh * 0.12;
    if mx >= quit_cx - 90.0 && mx <= quit_cx + 90.0 && my >= quit_y - 20.0 && my <= quit_y + 20.0 {
        return Some(MenuSelection::Quit);
    }

    None
}

fn draw_card(
    cx: f32,
    cy: f32,
    width: f32,
    name: &str,
    authors: &str,
    is_selected: bool,
    is_wasm: bool,
) {
    let left = cx - width / 2.0;
    let right = cx + width / 2.0;

    if is_selected {
        if is_wasm {
            let _ = gfx::color(0.12, 0.48, 0.82, 0.55);
        } else {
            let _ = gfx::color(0.72, 0.45, 0.18, 0.55);
        }
        let _ = gfx::rect(left, cy - 25.0, right, cy + 25.0);
        let _ = gfx::color(1.0, 1.0, 1.0, 1.0);
    } else {
        let _ = gfx::color(0.14, 0.16, 0.20, 0.4);
        let _ = gfx::rect(left, cy - 25.0, right, cy + 25.0);
        let _ = gfx::color(0.8, 0.8, 0.8, 1.0);
    }

    let _ = gfx::text(name, cx, cy + 7.0, 21.0, "cson");

    if is_selected {
        let _ = gfx::color(0.85, 0.95, 1.0, 0.9);
    } else {
        let _ = gfx::color(0.6, 0.6, 0.6, 0.8);
    }
    let _ = gfx::text(authors, cx, cy - 11.0, 11.0, "con");
}

fn launch_game(game: &GameEntry) {
    apply_game_graphics(game);
    let script = make_start_script(game);
    if let Err(err) = system_control::reload(&script) {
        ERROR_MSG.with(|msg| {
            *msg.borrow_mut() = Some(format!(
                "Failed to launch {}: error code {}",
                game.name, err.code
            ));
        });
    }
}

fn apply_game_graphics(game: &GameEntry) {
    if game.game_type.starts_with("Area 17") {
        let _ = config::set_config_int("MaxParticles", 200_000, true);
        let _ = config::set_config_int("Water", 4, true);
    }
}

fn make_start_script(game: &GameEntry) -> String {
    let mod_options = if game.game_type.starts_with("Area 17") {
        "    [MODOPTIONS]\n    {\n        DisableMapDamage=0;\n    }\n"
    } else if game.game_type.starts_with("Parts Needed") {
        // The original defaults to its editor when this is absent.  Play mode
        // locks the camera/input and removes the developer play/stop widget.
        "    [MODOPTIONS]\n    {\n        gamemode=play;\n    }\n"
    } else {
        ""
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
        Team=0;
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
        Team=1;
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
