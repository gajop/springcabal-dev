use crate::catalog::{Action, Variant};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Direction {
    Left,
    Right,
    Up,
    Down,
}

pub fn next(actions: &[Action], current: usize, direction: Direction) -> usize {
    let Some(&action) = actions.get(current) else {
        return 0;
    };
    let Action::Launch { game, variant } = action else {
        let variant = if direction == Direction::Right {
            Variant::Lua
        } else {
            Variant::Wasm
        };
        let matches =
            |action: &Action| matches!(action, Action::Launch { variant: v, .. } if *v == variant);
        return if direction == Direction::Down {
            actions.iter().position(matches)
        } else {
            actions.iter().rposition(matches)
        }
        .unwrap_or(current);
    };

    let same_row =
        |action: &Action| matches!(action, Action::Launch { game: row, .. } if *row == game);
    match direction {
        Direction::Left => current
            .checked_sub(1)
            .filter(|&index| same_row(&actions[index]))
            .unwrap_or(current),
        Direction::Right => actions
            .get(current + 1)
            .filter(|action| same_row(action))
            .map_or(current, |_| current + 1),
        Direction::Up | Direction::Down => {
            let target = if direction == Direction::Up {
                actions[..current]
                    .iter()
                    .rev()
                    .find(|action| !same_row(action))
                    .or_else(|| actions.last())
            } else {
                actions[current + 1..]
                    .iter()
                    .find(|action| !same_row(action))
                    .or_else(|| actions.first())
            };
            let Some(&Action::Launch { game, .. }) = target else {
                return actions
                    .iter()
                    .position(|action| *action == Action::Quit)
                    .unwrap_or(current);
            };
            let desired = Action::Launch { game, variant };
            actions
                .iter()
                .position(|action| *action == desired)
                .or_else(|| {
                    actions.iter().position(|action| {
                        *action
                            == Action::Launch {
                                game,
                                variant: Variant::Lua,
                            }
                    })
                })
                .unwrap_or(current)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use Action::{Launch, Quit};
    use Direction::{Down, Left, Right, Up};
    use Variant::{Editor, Lua, Wasm};

    const ACTIONS: &[Action] = &[
        Launch {
            game: 0,
            variant: Wasm,
        },
        Launch {
            game: 0,
            variant: Lua,
        },
        Launch {
            game: 0,
            variant: Editor,
        },
        Launch {
            game: 1,
            variant: Wasm,
        },
        Launch {
            game: 1,
            variant: Lua,
        },
        Launch {
            game: 2,
            variant: Wasm,
        },
        Launch {
            game: 2,
            variant: Lua,
        },
        Quit,
    ];

    #[test]
    fn horizontal_movement_stays_in_its_row() {
        assert_eq!(next(ACTIONS, 0, Left), 0);
        assert_eq!(next(ACTIONS, 0, Right), 1);
        assert_eq!(next(ACTIONS, 1, Right), 2);
        assert_eq!(next(ACTIONS, 2, Left), 1);
        assert_eq!(next(ACTIONS, 2, Right), 2);
        assert_eq!(next(ACTIONS, 4, Right), 4);
    }

    #[test]
    fn vertical_movement_preserves_versions_and_clamps_editor_to_lua() {
        assert_eq!(next(ACTIONS, 2, Down), 4);
        assert_eq!(next(ACTIONS, 4, Up), 1);
        assert_eq!(next(ACTIONS, 4, Down), 6);
        assert_eq!(next(ACTIONS, 5, Up), 3);
    }

    #[test]
    fn editor_column_is_preserved_when_available() {
        let actions = [
            Launch {
                game: 0,
                variant: Wasm,
            },
            Launch {
                game: 0,
                variant: Lua,
            },
            Launch {
                game: 0,
                variant: Editor,
            },
            Launch {
                game: 1,
                variant: Wasm,
            },
            Launch {
                game: 1,
                variant: Lua,
            },
            Launch {
                game: 1,
                variant: Editor,
            },
            Quit,
        ];
        assert_eq!(next(&actions, 2, Down), 5);
        assert_eq!(next(&actions, 5, Up), 2);
    }

    #[test]
    fn quit_wraps_between_game_rows() {
        assert_eq!(next(ACTIONS, 0, Up), 7);
        assert_eq!(next(ACTIONS, 1, Up), 7);
        assert_eq!(next(ACTIONS, 2, Up), 7);
        assert_eq!(next(ACTIONS, 5, Down), 7);
        assert_eq!(next(ACTIONS, 6, Down), 7);
        assert_eq!(next(ACTIONS, 7, Up), 5);
        assert_eq!(next(ACTIONS, 7, Down), 0);
        assert_eq!(next(ACTIONS, 7, Left), 5);
        assert_eq!(next(ACTIONS, 7, Right), 6);
    }
}
