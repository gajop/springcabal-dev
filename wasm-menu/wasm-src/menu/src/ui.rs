use alloc::format;
use alloc::string::String;
use alloc::vec::Vec;
use core::cell::{Cell, RefCell};

pub use spring::Menu as MenuEnvironment;
use spring::callbacks::{Event, Value};
use spring::{Result, ResultExt, Spring, module::Module};

use crate::catalog::{self, Action, GAMES};
use crate::model::{Bindings, require};
use crate::navigation::{self, Direction};

#[cfg(target_arch = "wasm32")]
spring::export_callin_scratch!(4096);
spring::export_module!(MENU, MenuEnvironment, Menu);
spring::export_update!(MENU, update);
spring::export_draw_screen!(MENU, draw_screen);
spring::export_key_press!(MENU, key_press);

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
    bindings: RefCell<Option<Bindings>>,
    selected: Cell<usize>,
    previewed: Cell<Option<usize>>,
    hovered: Cell<usize>,
    mouse_active: Cell<bool>,
    pending: Cell<Option<Action>>,
    error: RefCell<Option<String>>,
}

impl Module<MenuEnvironment> for Menu {
    fn initialize(_spring: &mut Spring<'_, MenuEnvironment>) -> Result<Self> {
        Ok(Self::new())
    }
    fn shutdown(&self, spring: &mut Spring<'_, MenuEnvironment>) -> Result<()> {
        let bindings = self.bindings.borrow_mut().take();
        if let Some(bindings) = bindings {
            bindings.close(spring)?;
        }
        let context = self.context.replace(0);
        if context != 0 {
            require(spring.rml_ui().remove_context(context)?)?;
        }
        Ok(())
    }
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
            bindings: RefCell::new(None),
            selected: Cell::new(0),
            previewed: Cell::new(None),
            hovered: Cell::new(0),
            mouse_active: Cell::new(false),
            pending: Cell::new(None),
            error: RefCell::new(None),
        }
    }

    fn initialize_ui(&self, spring: &mut Spring<'_, MenuEnvironment>) -> spring::Result<()> {
        let context = spring.rml_ui().create_context("springcabal-menu")?;
        require(context.success && context.context_handle != 0)?;
        self.context.set(context.context_handle);
        let actions = self
            .buttons
            .iter()
            .map(|button| button.action)
            .collect::<Vec<_>>();
        let bindings = Bindings::create(spring, context.context_handle, &actions)?;
        for (name, id) in [("launch", LAUNCH), ("preview", PREVIEW), ("select", SELECT)] {
            bindings.bind_event(spring, name, id)?;
        }
        let loaded = spring
            .rml_ui()
            .context_load_document(context.context_handle, "WasmMenu/menu.rml")?;
        require(loaded.success && loaded.document_handle != 0)?;
        let document = loaded.document_handle;
        let games = element(spring, document, "games")?;
        require(
            spring
                .rml_ui()
                .element_set_inner_rml(games, include_str!("../../../WasmMenu/game-row.rml"))?,
        )?;
        require(
            spring
                .rml_ui()
                .document_show(document, Default::default())?,
        )?;
        require(spring.rml_ui().context_update(context.context_handle)?)?;
        for (index, button) in self.buttons.iter().enumerate() {
            let id = if button.action == Action::Quit {
                String::from("quit")
            } else {
                format!("action-{index}")
            };
            button.element.set(element(spring, document, &id)?);
        }
        for (name, id) in [
            ("mousemove", POINTER),
            ("mousescroll", POINTER),
            ("keydown", KEY),
        ] {
            let listener = spring.rml_ui().context_add_event_listener(
                context.context_handle,
                name,
                true,
                move |spring, event| dispatch(spring, id, event),
            )?;
            require(listener.success)?;
        }
        self.document.set(document);
        *self.bindings.borrow_mut() = Some(bindings);
        self.select(spring, 0, true);
        spring::log_info!(spring, "menu", "SpringCabal menu initialized");
        Ok(())
    }

    fn select(&self, spring: &mut Spring<'_, MenuEnvironment>, index: usize, focus: bool) {
        let Some(button) = self.buttons.get(index) else {
            return;
        };
        self.selected.set(index);
        let game = match button.action {
            Action::Launch { game, .. } => Some(game),
            Action::Quit => None,
        };
        if let Some(bindings) = self.bindings.borrow().clone() {
            bindings
                .select(spring, index, game)
                .log_err_once(spring, "selecting a menu action");
        }
        if let Some(game) = game {
            self.preview(spring, game);
        }
        if focus && button.element.get() != 0 {
            let _ = spring.rml_ui().element_focus(button.element.get());
            let _ = spring
                .rml_ui()
                .element_scroll_into_view(button.element.get(), false);
        }
    }

    fn preview(&self, spring: &mut Spring<'_, MenuEnvironment>, index: usize) {
        let Some(game) = GAMES.get(index) else {
            return;
        };
        if self.previewed.get() == Some(index) {
            return;
        }
        let Some(bindings) = self.bindings.borrow().clone() else {
            return;
        };
        match bindings.preview(spring, game) {
            Ok(()) => {
                self.previewed.set(Some(index));
            }
            Err(error) => {
                self.show_error(
                    spring,
                    format!("Could not show {} (error {}).", game.name, error.code),
                );
            }
        }
        if let Ok(spotlight) = element(spring, self.document.get(), "spotlight") {
            let _ = spring.rml_ui().element_set_scroll_top(spotlight, 0);
        }
    }

    fn dispatch(&self, spring: &mut Spring<'_, MenuEnvironment>, id: u32, event: &Event) {
        match id {
            LAUNCH => {
                if let Some(index) = event_index(event)
                    && let Some(button) = self.buttons.get(index)
                {
                    self.pending.set(Some(button.action));
                }
            }
            PREVIEW => {
                if let Some(index) = event_index(event) {
                    self.hovered.set(index);
                    if self.mouse_active.get() {
                        self.preview(spring, index);
                    }
                }
            }
            SELECT => {
                if let Some(index) = event_index(event) {
                    self.select(spring, index, false);
                }
            }
            POINTER => {
                self.mouse_active.set(true);
                self.preview(spring, self.hovered.get());
            }
            KEY => self.navigate(spring, event),
            _ => {}
        }
    }

    fn navigate(&self, spring: &mut Spring<'_, MenuEnvironment>, event: &Event) {
        let Ok(key) = spring
            .rml_ui()
            .event_get_parameter_int(event.event_handle, "key_identifier")
        else {
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
            self.select(spring, next, true);
        }
        let _ = spring.rml_ui().event_stop_propagation(event.event_handle);
    }

    fn show_error(&self, spring: &mut Spring<'_, MenuEnvironment>, message: String) {
        *self.error.borrow_mut() = Some(message.clone());
        if let Some(bindings) = self.bindings.borrow().clone() {
            bindings
                .show_error(spring, &message)
                .log_err_once(spring, "showing a menu error");
        }
    }

    fn update(&self, spring: &mut Spring<'_, MenuEnvironment>) {
        let failed = self.error.borrow().is_some();
        if self.document.get() == 0
            && !failed
            && spring.rml_ui().is_ready() == Ok(true)
            && let Err(error) = self.initialize_ui(spring)
        {
            let context = self.context.replace(0);
            if context != 0 {
                let _ = spring.rml_ui().remove_context(context);
            }
            self.document.set(0);
            *self.bindings.borrow_mut() = None;
            for button in &self.buttons {
                button.element.set(0);
            }
            self.show_error(
                spring,
                format!(
                    "Menu UI could not load (error {}). Escape to quit.",
                    error.code
                ),
            );
        }
        // Reload only after the RmlUi event callback has returned.
        match self.pending.take() {
            Some(Action::Quit) => {
                let _ = spring.system_control().quit();
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
                        let _ = spring
                            .config()
                            .set_config_string(key.trim(), value.trim(), true);
                    }
                }
                if spring.system_control().reload(script) != Ok(true) {
                    self.show_error(
                        spring,
                        format!("Failed to launch {} ({variant:?}).", game.name),
                    );
                }
            }
            None => {}
        }
    }

    fn draw_error(&self, spring: &mut Spring<'_, MenuEnvironment>, width: i32, height: i32) {
        if self.document.get() != 0 {
            return;
        }
        let message = self.error.borrow().clone();
        let Some(message) = message else {
            return;
        };
        let _ = spring.gfx().color(0.04, 0.06, 0.08, 1.0);
        let _ = spring.gfx().rect(0.0, 0.0, width as f32, height as f32);
        let _ = spring.gfx().begin_text(false);
        let _ = spring.gfx().color(1.0, 0.7, 0.7, 1.0);
        let _ = spring.gfx().text(
            &message,
            width as f32 / 2.0,
            height as f32 / 2.0,
            18.0,
            "con",
        );
        let _ = spring.gfx().end_text();
    }
}

fn element(spring: &mut Spring<'_, MenuEnvironment>, document: u64, id: &str) -> Result<u64> {
    let found = spring.rml_ui().element_get_element_by_id(document, id)?;
    require(found.exists && found.element_handle != 0)?;
    Ok(found.element_handle)
}
fn event_index(event: &Event) -> Option<usize> {
    match event.values.first()? {
        Value::Int(index) => usize::try_from(*index).ok(),
        _ => None,
    }
}
fn menu_active(spring: &mut Spring<'_, MenuEnvironment>) -> bool {
    spring
        .system_control()
        .get_game_name()
        .is_ok_and(|name| name.is_empty())
}
pub(crate) fn dispatch(
    _spring: &mut Spring<'_, MenuEnvironment>,
    id: u32,
    event: Event,
) -> Result<()> {
    MENU.with(|slot| {
        slot.invoke(|menu, spring| {
            if menu_active(spring) {
                menu.dispatch(spring, id, &event);
            }
            Ok(())
        })
    })
}
fn update(menu: &Menu, spring: &mut Spring<'_, MenuEnvironment>, _delta: f32) -> Result<()> {
    if menu_active(spring) {
        menu.update(spring);
    }
    Ok(())
}
fn draw_screen(
    menu: &Menu,
    spring: &mut Spring<'_, MenuEnvironment>,
    width: i32,
    height: i32,
) -> Result<()> {
    if menu_active(spring) {
        menu.draw_error(spring, width, height);
    }
    Ok(())
}
fn key_press(
    menu: &Menu,
    spring: &mut Spring<'_, MenuEnvironment>,
    key: i32,
    _alt: bool,
    _ctrl: bool,
    _meta: bool,
    _shift: bool,
    _repeat: bool,
    _label: &str,
    _utf32: i32,
    _scan: i32,
    _actions: &[spring::types::callins::KeyAction],
) -> Result<bool> {
    let quit = menu_active(spring) && key == 27;
    if quit {
        menu.pending.set(Some(Action::Quit));
    }
    Ok(quit)
}
