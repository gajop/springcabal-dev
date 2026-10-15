use alloc::vec::Vec;

use spring::owned::rml_ui::{RmlDataFieldDef, RmlDataValue};
use spring::{ApiError, ErrorCode, Result, rml_ui as rml};

use crate::catalog::{Action, GAMES, Game, Variant};
use crate::entry;

pub const INT: u8 = 1;
const BOOL: u8 = 0;
const STRING: u8 = 3;

const GAME_FIELDS: [(&str, u8); 8] = [
    ("index", INT),
    ("name", STRING),
    ("built", STRING),
    ("image", STRING),
    ("wasm_action", INT),
    ("lua_action", INT),
    ("editor_action", INT),
    ("has_editor", BOOL),
];
const PARAGRAPH_FIELDS: [(&str, u8); 1] = [("text", STRING)];
const RATING_FIELDS: [(&str, u8); 4] = [
    ("label", STRING),
    ("value", STRING),
    ("image", STRING),
    ("has_image", BOOL),
];

#[derive(Clone, Copy)]
pub struct Bindings {
    model: u64,
    selected_action: u64,
    selected_game: u64,
    name: u64,
    authors: u64,
    built: u64,
    image: u64,
    introduction: u64,
    ratings: u64,
    has_ratings: u64,
    error: u64,
    has_error: u64,
}

impl Bindings {
    pub fn create(context: u64, actions: &[Action]) -> Result<Self> {
        let created = rml::context_create_data_model(context, "menu")?;
        require(created.success)?;
        let model = created.data_model_handle;
        let games = bind_rows(model, "games", &GAME_FIELDS)?;
        let quit = actions
            .iter()
            .position(|action| *action == Action::Quit)
            .ok_or(ApiError::new(ErrorCode::InvalidArgument as i32))?;
        bind_int(model, "quit_action", quit as i32)?;
        let bindings = Self {
            model,
            selected_action: bind_int(model, "selected_action", 0)?,
            selected_game: bind_int(model, "selected_game", 0)?,
            name: bind_string(model, "name")?,
            authors: bind_string(model, "authors")?,
            built: bind_string(model, "built")?,
            image: bind_string(model, "image")?,
            introduction: bind_rows(model, "introduction", &PARAGRAPH_FIELDS)?,
            ratings: bind_rows(model, "ratings", &RATING_FIELDS)?,
            has_ratings: bind_bool(model, "has_ratings")?,
            error: bind_string(model, "error")?,
            has_error: bind_bool(model, "has_error")?,
        };
        let mut values = Vec::with_capacity(GAMES.len() * GAME_FIELDS.len());
        for (index, game) in GAMES.iter().enumerate() {
            let action_id = |variant| {
                actions
                    .iter()
                    .position(|action| {
                        *action
                            == Action::Launch {
                                game: index,
                                variant,
                            }
                    })
                    .map_or(-1, |index| index as i32)
            };
            values.extend([
                int(index as i32),
                text(game.name),
                text(game.built),
                text(game.image),
                int(action_id(Variant::Wasm)),
                int(action_id(Variant::Lua)),
                int(action_id(Variant::Editor)),
                boolean(game.editor.is_some()),
            ]);
        }
        require(rml::data_model_set_rows(games, &values)?)?;
        Ok(bindings)
    }

    pub fn bind_event(self, name: &str, id: u32) -> Result<()> {
        let event = rml::data_model_bind_event(
            self.model,
            name,
            spring::callback::RetainedCallback::new(id, 0, 0),
            &[INT],
        )?;
        require(event.success && event.handle != 0)
    }

    pub fn select(self, action: usize, game: Option<usize>) -> Result<()> {
        require(rml::data_model_set_int(
            self.selected_action,
            action as i32,
        )?)?;
        require(rml::data_model_set_int(
            self.selected_game,
            game.map_or(-1, |i| i as i32),
        )?)
    }

    pub fn preview(self, game: &Game) -> Result<()> {
        for (handle, value) in [
            (self.name, game.name),
            (self.authors, game.authors),
            (self.built, game.built),
            (self.image, game.image),
        ] {
            require(rml::data_model_set_string(handle, value)?)?;
        }
        let paragraphs = entry::introduction(game.article)
            .into_iter()
            .map(text)
            .collect::<Vec<_>>();
        require(rml::data_model_set_rows(self.introduction, &paragraphs)?)?;
        let ratings = entry::ratings(game.article);
        require(rml::data_model_set_bool(
            self.has_ratings,
            !ratings.is_empty(),
        )?)?;
        let mut values = Vec::with_capacity(ratings.len() * RATING_FIELDS.len());
        for rating in ratings {
            values.extend([
                text(&rating.label),
                text(&rating.value),
                text(rating.image.as_deref().unwrap_or("")),
                boolean(rating.image.is_some()),
            ]);
        }
        require(rml::data_model_set_rows(self.ratings, &values)?)
    }

    pub fn show_error(self, message: &str) -> Result<()> {
        require(rml::data_model_set_string(self.error, message)?)?;
        require(rml::data_model_set_bool(self.has_error, true)?)
    }
}

pub fn require(success: bool) -> Result<()> {
    if success {
        Ok(())
    } else {
        Err(ApiError::new(ErrorCode::InvalidArgument as i32))
    }
}

fn bind_int(model: u64, name: &str, value: i32) -> Result<u64> {
    let binding = rml::data_model_bind_int(model, name, value)?;
    require(binding.success && binding.variable_handle != 0)?;
    Ok(binding.variable_handle)
}

fn bind_string(model: u64, name: &str) -> Result<u64> {
    let binding = rml::data_model_bind_string(model, name, "")?;
    require(binding.success && binding.variable_handle != 0)?;
    Ok(binding.variable_handle)
}

fn bind_bool(model: u64, name: &str) -> Result<u64> {
    let binding = rml::data_model_bind_bool(model, name, false)?;
    require(binding.success && binding.variable_handle != 0)?;
    Ok(binding.variable_handle)
}

fn bind_rows(model: u64, name: &str, fields: &[(&str, u8)]) -> Result<u64> {
    let fields = fields
        .iter()
        .map(|(name, type_)| RmlDataFieldDef {
            name: (*name).into(),
            type_: *type_,
        })
        .collect::<Vec<_>>();
    let binding = rml::data_model_bind_rows(model, name, &fields)?;
    require(binding.success && binding.rows_handle != 0)?;
    Ok(binding.rows_handle)
}

fn text(value: &str) -> RmlDataValue {
    RmlDataValue {
        type_: STRING,
        string_value: value.into(),
        ..Default::default()
    }
}

fn int(value: i32) -> RmlDataValue {
    RmlDataValue {
        type_: INT,
        int_value: value,
        ..Default::default()
    }
}

fn boolean(value: bool) -> RmlDataValue {
    RmlDataValue {
        type_: BOOL,
        bool_value: value,
        ..Default::default()
    }
}
