use super::{
    GAME_DETAILS, LUA_GAMES, WASM_GAMES, apply_game_graphics, make_editor_start_script,
    make_start_script,
};
use alloc::{format, string::String};
use core::cell::{Cell, RefCell};
use spring::callback::RetainedCallback;
use spring::{gfx, rml_ui as rml, system_control};

spring::export_callin_scratch!(4096);
spring::export_environment_mask!(spring::menu::ENVIRONMENT_MASK);
spring::export_callback_dispatch!(dispatch);
spring::export_update!(update);
spring::export_draw_screen!(draw_screen);
spring::export_key_press!(key_press);

const CLICK: u32 = 1;
const HOVER: u32 = 2;
const KEY: u32 = 3;
const MOUSE: u32 = 4;
const COUNT: usize = WASM_GAMES.len();
const EDIT_GRAVITAS: usize = COUNT * 2;
const QUIT: usize = EDIT_GRAVITAS + 1;
const BUTTON_COUNT: usize = QUIT + 1;

thread_local! {
    static CONTEXT: Cell<u64> = const { Cell::new(0) };
    static DOCUMENT: Cell<u64> = const { Cell::new(0) };
    static BUTTONS: Cell<[u64; BUTTON_COUNT]> = const { Cell::new([0; BUTTON_COUNT]) };
    static SELECTED: Cell<usize> = const { Cell::new(0) };
    static PREVIEW: Cell<Option<usize>> = const { Cell::new(None) };
    static HOVERED: Cell<usize> = const { Cell::new(0) };
    static MOUSE_ACTIVE: Cell<bool> = const { Cell::new(false) };
    static PENDING: Cell<Option<usize>> = const { Cell::new(None) };
    static INIT_ATTEMPTED: Cell<bool> = const { Cell::new(false) };
    static ERROR: RefCell<Option<String>> = const { RefCell::new(None) };
}

fn menu_active() -> bool {
    system_control::get_game_name(0).is_ok_and(|name| name.is_empty())
}

fn require(success: bool) -> spring::Result<()> {
    if success {
        Ok(())
    } else {
        Err(spring::ApiError::new(1))
    }
}

fn element(document: u64, id: &str) -> spring::Result<u64> {
    let found = rml::element_get_element_by_id(document, id)?;
    require(found.exists)?;
    Ok(found.element_handle)
}

fn escape(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

fn initialize() -> spring::Result<()> {
    let created = rml::create_rml_context("springcabal-menu")?;
    require(created.success)?;
    CONTEXT.set(created.context_handle);
    let loaded = rml::load_rml_document(created.context_handle, "WasmMenu/menu.rml")?;
    require(loaded.success)?;
    DOCUMENT.set(loaded.document_handle);
    let mut markup = String::new();
    for (i, game) in WASM_GAMES.iter().enumerate() {
        let details = &GAME_DETAILS[i];
        let image = details
            .image
            .strip_prefix("WasmMenu/")
            .unwrap_or(details.image);
        if i == 0 {
            markup.push_str(&format!(
                "<div class='game' id='row-{i}'><img class='thumbnail' src='{}'/><div class='details'><div class='name'>{}</div><div class='built'>{}</div></div><button class='launch wasm' id='game-{i}'><img src='images/webassembly-logo.png'/><span>WASM</span></button><button class='launch lua' id='game-{}'><img src='images/lua-logo.gif'/><span>Lua</span></button><button class='launch lua editor' id='game-{EDIT_GRAVITAS}'><img src='images/lua-logo.gif'/><span>Editor</span></button></div>",
                escape(image), escape(game.name.trim_end_matches(" (WASM)")), escape(details.built), i + COUNT
            ));
        } else {
            markup.push_str(&format!(
                "<div class='game' id='row-{i}'><img class='thumbnail' src='{}'/><div class='details'><div class='name'>{}</div><div class='built'>{}</div></div><button class='launch wasm' id='game-{i}'><img src='images/webassembly-logo.png'/><span>WASM</span></button><button class='launch lua' id='game-{}'><img src='images/lua-logo.gif'/><span>Lua</span></button></div>",
                escape(image), escape(game.name.trim_end_matches(" (WASM)")), escape(details.built), i + COUNT
            ));
        }
    }
    require(rml::element_set_inner_rml(
        element(loaded.document_handle, "games")?,
        &markup,
    )?)?;
    for i in 0..COUNT {
        require(
            rml::element_add_event_listener(
                element(loaded.document_handle, &format!("row-{i}"))?,
                "mouseover",
                false,
                RetainedCallback::new(HOVER, i as u32, 0),
            )?
            .success,
        )?;
    }
    let mut buttons = [0; BUTTON_COUNT];
    for (i, handle) in buttons.iter_mut().enumerate() {
        let id = if i == QUIT {
            String::from("quit")
        } else {
            format!("game-{i}")
        };
        *handle = element(loaded.document_handle, &id)?;
        require(
            rml::element_add_event_listener(
                *handle,
                "click",
                false,
                RetainedCallback::new(CLICK, i as u32, 0),
            )?
            .success,
        )?;
    }
    BUTTONS.set(buttons);
    for event in ["mousemove", "mousescroll"] {
        require(
            rml::context_add_event_listener(
                created.context_handle,
                event,
                true,
                RetainedCallback::new(MOUSE, 0, 0),
            )?
            .success,
        )?;
    }
    require(
        rml::context_add_event_listener(
            created.context_handle,
            "keydown",
            true,
            RetainedCallback::new(KEY, 0, 0),
        )?
        .success,
    )?;
    require(rml::show_rml_document(loaded.document_handle)?)?;
    select(0, true);
    Ok(())
}

fn select(index: usize, focus: bool) {
    if index >= BUTTON_COUNT {
        return;
    }
    let previous = SELECTED.replace(index);
    let buttons = BUTTONS.get();
    if buttons[index] == 0 {
        return;
    }
    if previous != index {
        let _ = rml::element_set_class(buttons[previous], "selected", false);
    }
    let _ = rml::element_set_class(buttons[index], "selected", true);
    for row in [previous, index] {
        if row < QUIT
            && let Ok(handle) = element(DOCUMENT.get(), &format!("row-{}", row % COUNT))
        {
            let _ = rml::element_set_class(
                handle,
                "keyboard",
                index < QUIT && row % COUNT == index % COUNT,
            );
        }
    }
    preview(index);
    if focus {
        let _ = rml::element_focus(buttons[index]);
        let _ = rml::element_scroll_into_view(buttons[index], false);
    }
}

// Mouse hover only changes the artwork preview. Never overwrite SELECTED:
// RmlUi also sends mouseover when scrolling moves a row under a stationary mouse.
fn preview(index: usize) {
    let index = if index < QUIT { index % COUNT } else { index };
    if index < QUIT && PREVIEW.replace(Some(index)) != Some(index) {
        if let Ok(handle) = element(DOCUMENT.get(), "spotlight") {
            let _ = rml::element_set_scroll_top(handle, 0);
        }
        let game = if index < COUNT {
            &WASM_GAMES[index]
        } else {
            &LUA_GAMES[index - COUNT]
        };
        let details = &GAME_DETAILS[index % COUNT];
        for (id, markup) in [
            (
                "hero-introduction",
                super::entry::introduction(index % COUNT),
            ),
            ("hero-ratings", super::entry::ratings(index % COUNT)),
        ] {
            if let Ok(handle) = element(DOCUMENT.get(), id) {
                let _ = rml::element_set_inner_rml(handle, &markup);
            }
        }
        for (id, text) in [
            ("hero-name", game.name.trim_end_matches(" (WASM)")),
            ("hero-built", details.built),
            ("hero-authors", game.authors),
        ] {
            if let Ok(handle) = element(DOCUMENT.get(), id) {
                let _ = rml::element_set_inner_rml(handle, &escape(text));
            }
        }
        if let Ok(handle) = element(DOCUMENT.get(), "hero-image") {
            let _ = rml::element_set_attribute(
                handle,
                "src",
                details
                    .image
                    .strip_prefix("WasmMenu/")
                    .unwrap_or(details.image),
            );
        }
    }
}

fn dispatch(id: u32, data: u32) {
    if !menu_active() {
        return;
    }
    match id {
        CLICK if (data as usize) < BUTTON_COUNT => {
            PENDING.set(Some(data as usize));
        }
        HOVER => {
            HOVERED.set(data as usize);
            if MOUSE_ACTIVE.get() {
                preview(data as usize);
            }
        }
        MOUSE => {
            MOUSE_ACTIVE.set(true);
            preview(HOVERED.get());
        }
        KEY => {
            let Ok(event) = rml::event_get_current(0) else {
                return;
            };
            if !event.exists {
                return;
            }
            let Ok(key) = rml::event_get_parameter_int(event.event_handle, "key_identifier") else {
                return;
            };
            let current = SELECTED.get();
            // RmlUi key identifiers, not SDL codes.
            let next = match key.value {
                90 if current == EDIT_GRAVITAS => Some(COUNT),
                90 if (COUNT..QUIT).contains(&current) => Some(current - COUNT),
                92 if current == COUNT => Some(EDIT_GRAVITAS),
                92 if current < COUNT => Some(current + COUNT),
                90 | 92 if current == QUIT => {
                    Some(if key.value == 90 { COUNT - 1 } else { QUIT - 1 })
                }
                91 if current == QUIT => Some(COUNT - 1),
                91 if current == 0 || current == COUNT || current == EDIT_GRAVITAS => Some(QUIT),
                91 => Some(current - 1),
                93 if current == QUIT => Some(0),
                93 if current == EDIT_GRAVITAS => Some(COUNT + 1),
                93 if current == COUNT - 1 || current == QUIT - 1 => Some(QUIT),
                93 => Some(current + 1),
                70 => {
                    let backward = rml::event_get_parameter_int(event.event_handle, "shift_key")
                        .is_ok_and(|value| value.value != 0);
                    let slot = if current == QUIT {
                        QUIT
                    } else if current == EDIT_GRAVITAS {
                        EDIT_GRAVITAS
                    } else {
                        (current % COUNT) * 2 + usize::from(current >= COUNT)
                    };
                    let slot = if backward {
                        (slot + BUTTON_COUNT - 1) % BUTTON_COUNT
                    } else {
                        (slot + 1) % BUTTON_COUNT
                    };
                    Some(if slot == QUIT {
                        QUIT
                    } else if slot == EDIT_GRAVITAS {
                        EDIT_GRAVITAS
                    } else {
                        slot / 2 + (slot % 2) * COUNT
                    })
                }
                1 | 72 => {
                    PENDING.set(Some(current));
                    None
                }
                81 => {
                    PENDING.set(Some(QUIT));
                    None
                }
                _ => return,
            };
            if let Some(index) = next {
                MOUSE_ACTIVE.set(false);
                select(index, true);
            }
            let _ = rml::event_stop_propagation(event.event_handle);
        }
        _ => {}
    }
}

fn show_error(message: String) {
    ERROR.with(|error| *error.borrow_mut() = Some(message.clone()));
    if DOCUMENT.get() != 0
        && let Ok(banner) = element(DOCUMENT.get(), "error")
    {
        let _ = rml::element_set_inner_rml(banner, &escape(&message));
        let _ = rml::element_set_class(banner, "visible", true);
    }
}

fn update(_delta: f32) {
    if !menu_active() {
        return;
    }
    if !INIT_ATTEMPTED.replace(true)
        && let Err(error) = initialize()
    {
        let context = CONTEXT.replace(0);
        if context != 0 {
            let _ = rml::remove_context(context);
        }
        DOCUMENT.set(0);
        BUTTONS.set([0; BUTTON_COUNT]);
        show_error(format!(
            "Menu UI could not load (error {}). Escape to quit.",
            error.code
        ));
    }
    // Reload after the RmlUi callback stack has unwound.
    if let Some(index) = PENDING.take() {
        if index == QUIT {
            let _ = system_control::quit(0);
        } else if index == EDIT_GRAVITAS {
            let game = &LUA_GAMES[0];
            apply_game_graphics(game);
            match system_control::reload(&make_editor_start_script(game)) {
                Ok(true) => {}
                Ok(false) => show_error(format!("Failed to launch {} Editor.", game.name)),
                Err(error) => show_error(format!(
                    "Failed to launch {} Editor (error {}).",
                    game.name, error.code
                )),
            }
        } else {
            let game = if index < COUNT {
                &WASM_GAMES[index]
            } else {
                &LUA_GAMES[index - COUNT]
            };
            apply_game_graphics(game);
            match system_control::reload(&make_start_script(game)) {
                Ok(true) => {}
                Ok(false) => show_error(format!("Failed to launch {}.", game.name)),
                Err(error) => show_error(format!(
                    "Failed to launch {} (error {}).",
                    game.name, error.code
                )),
            }
        }
    }
}

// Escape remains available even if the RML document fails to load.
fn key_press(
    key: i32,
    _alt: bool,
    _ctrl: bool,
    _meta: bool,
    _shift: bool,
    _repeat: bool,
    _label: &[u8],
    _utf32: i32,
    _scan: i32,
    _actions: impl Iterator<Item = (&'static [u8], &'static [u8], &'static [u8])>,
) -> bool {
    if menu_active() && key == 27 {
        PENDING.set(Some(QUIT));
        return true;
    }
    false
}

fn draw_screen(width: i32, height: i32) {
    if !menu_active() || DOCUMENT.get() != 0 {
        return;
    }
    ERROR.with(|error| {
        if let Some(message) = error.borrow().as_ref() {
            let _ = gfx::color(0.04, 0.06, 0.08, 1.0);
            let _ = gfx::rect(0.0, 0.0, width as f32, height as f32);
            let _ = gfx::begin_text(false);
            let _ = gfx::color(1.0, 0.7, 0.7, 1.0);
            let _ = gfx::text(
                message,
                width as f32 / 2.0,
                height as f32 / 2.0,
                18.0,
                "con",
            );
            let _ = gfx::end_text(0);
        }
    });
}
