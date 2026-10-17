use alloc::{string::String, vec::Vec};

use crate::ui::MenuEnvironment;
use spring::rml::{DataModel, Rows, Value, ValueType, Variable};
use spring::{ApiError, ErrorCode, Result, Spring};

use crate::catalog::{Action, GAMES, Game, Variant};
use crate::entry;

const INT: ValueType = ValueType::Int;
const BOOL: ValueType = ValueType::Bool;
const STRING: ValueType = ValueType::String;

const GAME_FIELDS: [(&str, ValueType); 8] = [
    ("index", INT),
    ("name", STRING),
    ("built", STRING),
    ("image", STRING),
    ("wasm_action", INT),
    ("lua_action", INT),
    ("editor_action", INT),
    ("has_editor", BOOL),
];
const PARAGRAPH_FIELDS: [(&str, ValueType); 1] = [("text", STRING)];
const RATING_FIELDS: [(&str, ValueType); 4] = [
    ("label", STRING),
    ("value", STRING),
    ("image", STRING),
    ("has_image", BOOL),
];

#[derive(Clone)]
pub struct Bindings {
    model: DataModel,
    selected_action: Variable<i32>,
    selected_game: Variable<i32>,
    name: Variable<String>,
    authors: Variable<String>,
    built: Variable<String>,
    image: Variable<String>,
    introduction: Rows,
    ratings: Rows,
    has_ratings: Variable<bool>,
    error: Variable<String>,
    has_error: Variable<bool>,
}

impl Bindings {
    pub fn create(
        spring: &mut Spring<'_, MenuEnvironment>,
        context: u64,
        actions: &[Action],
    ) -> Result<Self> {
        let model = DataModel::create(spring, context, "menu")?;
        let games = model.rows(spring, "games", &GAME_FIELDS)?;
        let quit = actions
            .iter()
            .position(|action| *action == Action::Quit)
            .ok_or(ApiError::new(ErrorCode::InvalidArgument as i32))?;
        model.bind(spring, "quit_action", quit as i32)?;
        let bindings = Self {
            selected_action: model.bind(spring, "selected_action", 0i32)?,
            selected_game: model.bind(spring, "selected_game", 0i32)?,
            name: model.bind(spring, "name", String::new())?,
            authors: model.bind(spring, "authors", String::new())?,
            built: model.bind(spring, "built", String::new())?,
            image: model.bind(spring, "image", String::new())?,
            introduction: model.rows(spring, "introduction", &PARAGRAPH_FIELDS)?,
            ratings: model.rows(spring, "ratings", &RATING_FIELDS)?,
            has_ratings: model.bind(spring, "has_ratings", false)?,
            error: model.bind(spring, "error", String::new())?,
            has_error: model.bind(spring, "has_error", false)?,
            model,
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
        games.set(spring, values)?;
        Ok(bindings)
    }

    pub fn bind_event(
        &self,
        spring: &mut Spring<'_, MenuEnvironment>,
        name: &str,
        id: u32,
    ) -> Result<()> {
        self.model
            .event(spring, name, &[INT], move |spring, event| {
                crate::ui::dispatch(spring, id, event)
            })?;
        Ok(())
    }

    pub fn select(
        &self,
        spring: &mut Spring<'_, MenuEnvironment>,
        action: usize,
        game: Option<usize>,
    ) -> Result<()> {
        self.selected_action.set(spring, action as i32)?;
        self.selected_game
            .set(spring, game.map_or(-1, |i| i as i32))
    }

    pub fn preview(&self, spring: &mut Spring<'_, MenuEnvironment>, game: &Game) -> Result<()> {
        for (handle, value) in [
            (&self.name, game.name),
            (&self.authors, game.authors),
            (&self.built, game.built),
            (&self.image, game.image),
        ] {
            handle.set(spring, value.into())?;
        }
        let paragraphs = entry::introduction(game.article)
            .into_iter()
            .map(text)
            .collect::<Vec<_>>();
        self.introduction.set(spring, paragraphs)?;
        let ratings = entry::ratings(game.article);
        self.has_ratings.set(spring, !ratings.is_empty())?;
        let mut values = Vec::with_capacity(ratings.len() * RATING_FIELDS.len());
        for rating in ratings {
            values.extend([
                text(&rating.label),
                text(&rating.value),
                text(rating.image.as_deref().unwrap_or("")),
                boolean(rating.image.is_some()),
            ]);
        }
        self.ratings.set(spring, values)
    }

    pub fn show_error(
        &self,
        spring: &mut Spring<'_, MenuEnvironment>,
        message: &str,
    ) -> Result<()> {
        self.error.set(spring, message.into())?;
        self.has_error.set(spring, true)
    }
    pub fn close(&self, spring: &mut Spring<'_, MenuEnvironment>) -> Result<()> {
        self.model.close(spring)
    }
}

pub fn require(success: bool) -> Result<()> {
    if success {
        Ok(())
    } else {
        Err(ApiError::new(ErrorCode::InvalidArgument as i32))
    }
}

fn text(value: &str) -> Value {
    Value::String(value.into())
}
fn int(value: i32) -> Value {
    Value::Int(value)
}
fn boolean(value: bool) -> Value {
    Value::Bool(value)
}
