use alloc::{format, string::String, vec::Vec};

fn section<'a>(article: &'a str, heading: &str) -> &'a str {
    article
        .split_once(&format!("## {heading}\n"))
        .map(|(_, rest)| rest.split("\n## ").next().unwrap_or_default().trim())
        .unwrap_or_default()
}

pub fn introduction(article: &str) -> Vec<&str> {
    let description = section(article, "Description");
    let text = if description.is_empty() {
        section(article, "About game")
    } else {
        description
    };
    text.split("\n\n")
        .map(str::trim)
        .filter(|paragraph| !paragraph.is_empty())
        .collect()
}

#[derive(Debug, PartialEq, Eq)]
pub struct Rating {
    pub label: String,
    pub value: String,
    pub image: Option<String>,
}

pub fn ratings(article: &str) -> Vec<Rating> {
    let mut ratings = Vec::new();
    for line in section(article, "Ratings").lines() {
        let mut cells = line.split('|').skip(1).map(str::trim);
        let (Some(label), Some(score)) = (cells.next(), cells.next()) else {
            continue;
        };
        if score.ends_with('%') {
            ratings.push(Rating {
                label: String::from(label),
                value: String::from(score),
                image: None,
            });
        } else if score.parse::<f32>().is_ok() {
            ratings.push(Rating {
                label: String::from(label),
                value: format!("{score} / 5"),
                image: Some(format!("images/score-{score}.png")),
            });
        }
    }
    ratings
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::catalog::GAMES;

    #[test]
    fn original_paragraphs_are_preserved() {
        for (index, game) in GAMES.iter().enumerate() {
            let heading = if index == 0 {
                "About game"
            } else {
                "Description"
            };
            let expected: Vec<&str> = section(game.article, heading).split("\n\n").collect();
            assert_eq!(introduction(game.article), expected);
            if index != 1 {
                assert!(
                    ratings(game.article)
                        .iter()
                        .any(|rating| rating.label == "Overall")
                );
            }
        }
        let hunted = introduction(GAMES[1].article);
        assert!(hunted.contains(&"Zeus vs Bunnies (Hunted theme)"));
        assert!(
            hunted.contains(
                &"Extract the archive and run \"Hunted\" or \"Hunted.exe\". Shoot stuff."
            )
        );
        assert!(ratings(GAMES[1].article).is_empty());
    }

    #[test]
    fn scores_use_exact_fractional_stars_and_keep_percentages() {
        let cube = ratings(GAMES[5].article);
        let overall = cube
            .iter()
            .find(|rating| rating.label == "Overall")
            .unwrap();
        assert_eq!(overall.image.as_deref(), Some("images/score-3.42.png"));
        assert_eq!(overall.value, "3.42 / 5");
        let parts = ratings(GAMES[4].article);
        let coolness = parts
            .iter()
            .find(|rating| rating.label == "Coolness")
            .unwrap();
        assert_eq!(coolness.value, "54%");
        assert_eq!(coolness.image, None);
    }
}
