// Embed the archive so the menu and saved original text have one source of truth.
extern crate alloc;
use alloc::{format, string::String};

const ENTRIES: [&str; 7] = [
    include_str!("../../../../game-info/gravitas/README.md"),
    include_str!("../../../../game-info/zeus-vs-bunnies/README.md"),
    include_str!("../../../../game-info/area-17/README.md"),
    include_str!("../../../../game-info/flove/README.md"),
    include_str!("../../../../game-info/parts-needed/README.md"),
    include_str!("../../../../game-info/my-cube/README.md"),
    include_str!("../../../../game-info/to-the-last-drop/README.md"),
];

fn section<'a>(entry: &'a str, heading: &str) -> &'a str {
    entry
        .split_once(&format!("## {heading}\n"))
        .map(|(_, rest)| rest.split("\n## ").next().unwrap_or_default().trim())
        .unwrap_or_default()
}

fn escape(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

pub fn introduction(index: usize) -> String {
    let entry = ENTRIES[index];
    let text = section(
        entry,
        if index == 0 {
            "About game"
        } else {
            "Description"
        },
    );
    let mut markup = String::new();
    for paragraph in text.split("\n\n").filter(|p| !p.is_empty()) {
        markup.push_str(&format!("<p>{}</p>", escape(paragraph)));
    }
    markup
}

pub fn ratings(index: usize) -> String {
    let mut markup = String::new();
    for line in section(ENTRIES[index], "Ratings").lines() {
        let mut cells = line.split('|').skip(1).map(str::trim);
        let (Some(label), Some(score)) = (cells.next(), cells.next()) else {
            continue;
        };
        if score.ends_with('%') {
            markup.push_str(&format!("<div class='rating'><span class='rating-label'>{}</span><span class='rating-value'>{}</span></div>", escape(label), escape(score)));
            continue;
        }
        let Ok(_) = score.parse::<f32>() else {
            continue;
        };
        markup.push_str(&format!(
            "<div class='rating'><span class='rating-label'>{}</span><span class='stars'>",
            escape(label)
        ));
        markup.push_str(&format!("<img src='images/score-{}.png'/>", escape(score)));
        markup.push_str(&format!(
            "</span><span class='rating-value'>{} / 5</span></div>",
            escape(score)
        ));
    }
    if !markup.is_empty() {
        markup.insert_str(0, "<div class='rating-heading'>Ludum Dare scores</div>");
    }
    markup
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn original_paragraphs_are_preserved() {
        for index in [0, 2, 3, 4, 5, 6] {
            let heading = if index == 0 {
                "About game"
            } else {
                "Description"
            };
            for paragraph in section(ENTRIES[index], heading).split("\n\n") {
                assert!(introduction(index).contains(&format!("<p>{}</p>", escape(paragraph))));
            }
            assert!(ratings(index).contains("Overall"));
        }
        assert!(introduction(1).contains("Zeus vs Bunnies (Hunted theme)"));
        assert!(introduction(1).contains("&quot;Hunted.exe&quot;. Shoot stuff."));
        assert!(ratings(1).is_empty());
    }

    #[test]
    fn scores_use_exact_fractional_stars_and_keep_percentages() {
        let cube = ratings(5);
        assert!(cube.contains("images/score-3.42.png"));
        assert!(cube.contains("3.42 / 5"));
        assert!(ratings(4).contains("54%"));
        assert!(!ratings(4).contains("54% / 5"));
    }
}
