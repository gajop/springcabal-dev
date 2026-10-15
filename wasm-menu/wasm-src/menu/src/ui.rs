use alloc::format;
use alloc::string::String;
use alloc::vec::Vec;
use core::cell::{Cell, RefCell};

use spring::callback::RetainedCallback;
use spring::{ResultExt, gfx, rml_ui as rml, system_control};

use crate::catalog::{self, Action, GAMES};
use crate::model::{Bindings, require};
use crate::navigation::{self, Direction};

spring::export_callin_scratch!(4096);
spring::export_environment_mask!(spring::menu::ENVIRONMENT_MASK);
spring::export_callback_dispatch!(dispatch);
spring::export_update!(update);
spring::export_draw_screen!(draw_screen);
spring::export_key_press!(key_press);

const LAUNCH: u32 = 1;
const PREVIEW: u32 = 2;
const SELECT: u32 = 3;
const POINTER: u32 = 4;
const KEY: u32 = 5;

mod key {
    pub const SPACE: i32 = 1;
    pub const RETURN: i32 = 72;
    pub const ESCAPE: i32 = 81;
    pub const LEFT: i32 = 90;
    pub const UP: i32 = 91;
    pub const RIGHT: i32 = 92;
    pub const DOWN: i32 = 93;
}

struct Button {
    action: Action,
    element: Cell<u64>,
}

struct Menu {
    buttons: Vec<Button>,
    context: Cell<u64>,
    document: Cell<u64>,
    bindings: Cell<Option<Bindings>>,
    selected: Cell<usize>,
    previewed: Cell<Option<usize>>,
    hovered: Cell<usize>,
    mouse_active: Cell<bool>,
    pending: Cell<Option<Action>>,
    error: RefCell<Option<String>>,
}

thread_local! {
    static MENU: Menu = Menu::new();
}

impl Menu {
    fn new() -> Self {
        Self {
            buttons: catalog::actions()
                .into_iter()
                .map(|action| Button {
                    action,
                    element: Cell::new(0),
                })
                .collect(),
            context: Cell::new(0),
            document: Cell::new(0),
            bindings: Cell::new(None),
            selected: Cell::new(0),
            previewed: Cell::new(None),
            hovered: Cell::new(0),
            mouse_active: Cell::new(false),
            pending: Cell::new(None),
            error: RefCell::new(None),
        }
    }

    fn initialize(&self) -> spring::Result<()> {
        let context = rml::create_rml_context("springcabal-menu")?;
        require(context.success && context.context_handle != 0)?;
        self.context.set(context.context_handle);
        let actions = self
            .buttons
            .iter()
            .map(|button| button.action)
            .collect::<Vec<_>>();
        let bindings = Bindings::create(context.context_handle, &actions)?;
        for (name, id) in [("launch", LAUNCH), ("preview", PREVIEW), ("select", SELECT)] {
            bindings.bind_event(name, id)?;
        }
        let loaded = rml::load_rml_document(context.context_handle, "WasmMenu/menu.rml")?;
        require(loaded.success && loaded.document_handle != 0)?;
        let document = loaded.document_handle;
        let games = element(document, "games")?;
        require(rml::element_set_inner_rml(
            games,
            include_str!("../../../WasmMenu/game-row.rml"),
        )?)?;
        require(rml::show_rml_document(document)?)?;
        require(rml::context_update(context.context_handle)?)?;
        for (index, button) in self.buttons.iter().enumerate() {
            let id = if button.action == Action::Quit {
                String::from("quit")
            } else {
                format!("action-{index}")
            };
            button.element.set(element(document, &id)?);
        }
        for (name, id) in [
            ("mousemove", POINTER),
            ("mousescroll", POINTER),
            ("keydown", KEY),
        ] {
            let listener = rml::context_add_event_listener(
                context.context_handle,
                name,
                true,
                RetainedCallback::new(id, 0, 0),
            )?;
            require(listener.success)?;
        }
        self.document.set(document);
        self.bindings.set(Some(bindings));
        self.select(0, true);
        spring::log_info!("menu", "SpringCabal menu initialized");
        Ok(())
    }

    fn select(&self, index: usize, focus: bool) {
        let Some(button) = self.buttons.get(index) else {
            return;
        };
        self.selected.set(index);
        let game = match button.action {
            Action::Launch { game, .. } => Some(game),
            Action::Quit => None,
        };
        if let Some(bindings) = self.bindings.get() {
            bindings
                .select(index, game)
                .log_err_once("selecting a menu action");
        }
        if let Some(game) = game {
            self.preview(game);
        }
        if focus && button.element.get() != 0 {
            let _ = rml::element_focus(button.element.get());
            let _ = rml::element_scroll_into_view(button.element.get(), false);
        }
    }

    fn preview(&self, index: usize) {
        let Some(game) = GAMES.get(index) else {
            return;
        };
        if self.previewed.get() == Some(index) {
            return;
        }
        let Some(bindings) = self.bindings.get() else {
            return;
        };
        match bindings.preview(game) {
            Ok(()) => {
                self.previewed.set(Some(index));
            }
            Err(error) => {
                self.show_error(format!(
                    "Could not show {} (error {}).",
                    game.name, error.code
                ));
            }
        }
        if let Ok(spotlight) = element(self.document.get(), "spotlight") {
            let _ = rml::element_set_scroll_top(spotlight, 0);
        }
    }

    fn dispatch(&self, id: u32) {
        match id {
            LAUNCH => {
                if let Some(index) = event_index()
                    && let Some(button) = self.buttons.get(index)
                {
                    self.pending.set(Some(button.action));
                }
            }
            PREVIEW => {
                if let Some(index) = event_index() {
                    self.hovered.set(index);
                    if self.mouse_active.get() {
                        self.preview(index);
                    }
                }
            }
            SELECT => {
                if let Some(index) = event_index() {
                    self.select(index, false);
                }
            }
            POINTER => {
                self.mouse_active.set(true);
                self.preview(self.hovered.get());
            }
            KEY => self.navigate(),
            _ => {}
        }
    }

    fn navigate(&self) {
        let Ok(event) = rml::event_get_current(0) else {
            return;
        };
        if !event.exists {
            return;
        }
        let Ok(key) = rml::event_get_parameter_int(event.event_handle, "key_identifier") else {
            return;
        };
        let direction = match key.value {
            key::LEFT => Some(Direction::Left),
            key::RIGHT => Some(Direction::Right),
            key::UP => Some(Direction::Up),
            key::DOWN => Some(Direction::Down),
            key::SPACE | key::RETURN => {
                if let Some(button) = self.buttons.get(self.selected.get()) {
                    self.pending.set(Some(button.action));
                }
                None
            }
            key::ESCAPE => {
                self.pending.set(Some(Action::Quit));
                None
            }
            _ => return,
        };
        if let Some(direction) = direction {
            let actions = self
                .buttons
                .iter()
                .map(|button| button.action)
                .collect::<Vec<_>>();
            let next = navigation::next(&actions, self.selected.get(), direction);
            self.mouse_active.set(false);
            self.select(next, true);
        }
        let _ = rml::event_stop_propagation(event.event_handle);
    }

    fn show_error(&self, message: String) {
        *self.error.borrow_mut() = Some(message.clone());
        if let Some(bindings) = self.bindings.get() {
            bindings
                .show_error(&message)
                .log_err_once("showing a menu error");
        }
    }

    fn update(&self) {
        let failed = self.error.borrow().is_some();
        if self.document.get() == 0
            && !failed
            && rml::is_ready(0) == Ok(true)
            && let Err(error) = self.initialize()
        {
            let context = self.context.replace(0);
            if context != 0 {
                let _ = rml::remove_context(context);
            }
            self.document.set(0);
            self.bindings.set(None);
            for button in &self.buttons {
                button.element.set(0);
            }
            self.show_error(format!(
                "Menu UI could not load (error {}). Escape to quit.",
                error.code
            ));
        }
        // Reload only after the RmlUi event callback has returned.
        match self.pending.take() {
            Some(Action::Quit) => {
                let _ = system_control::quit(0);
            }
            Some(Action::Launch { game, variant }) => {
                let Some(game) = GAMES.get(game) else {
                    return;
                };
                let Some(script) = game.script(variant) else {
                    return;
                };
                for line in game.graphics.lines().map(str::trim) {
                    if !line.starts_with('#')
                        && let Some((key, value)) = line.split_once('=')
                    {
                        let _ = spring::config::set_config_string(key.trim(), value.trim(), true);
                    }
                }
                if system_control::reload(script) != Ok(true) {
                    self.show_error(format!("Failed to launch {} ({variant:?}).", game.name));
                }
            }
            None => {}
        }
    }

    fn draw_error(&self, width: i32, height: i32) {
        if self.document.get() != 0 {
            return;
        }
        let message = self.error.borrow().clone();
        let Some(message) = message else {
            return;
        };
        let _ = gfx::color(0.04, 0.06, 0.08, 1.0);
        let _ = gfx::rect(0.0, 0.0, width as f32, height as f32);
        let _ = gfx::begin_text(false);
        let _ = gfx::color(1.0, 0.7, 0.7, 1.0);
        let _ = gfx::text(
            &message,
            width as f32 / 2.0,
            height as f32 / 2.0,
            18.0,
            "con",
        );
        let _ = gfx::end_text(0);
    }
}

fn element(document: u64, id: &str) -> spring::Result<u64> {
    let found = rml::element_get_element_by_id(document, id)?;
    require(found.exists && found.element_handle != 0)?;
    Ok(found.element_handle)
}

fn event_index() -> Option<usize> {
    match rml::data_model_current_value(0, &mut []).ok()? {
        spring::DataEventValue::Int(index) => usize::try_from(index).ok(),
        _ => None,
    }
}

fn menu_active() -> bool {
    system_control::get_game_name(0).is_ok_and(|name| name.is_empty())
}
fn dispatch(id: u32, _data: u32) {
    if menu_active() {
        MENU.with(|menu| menu.dispatch(id));
    }
}
fn update(_delta: f32) {
    if menu_active() {
        MENU.with(Menu::update);
    }
}
fn draw_screen(width: i32, height: i32) {
    if menu_active() {
        MENU.with(|menu| menu.draw_error(width, height));
    }
}
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
        MENU.with(|menu| menu.pending.set(Some(Action::Quit)));
        true
    } else {
        false
    }
}
