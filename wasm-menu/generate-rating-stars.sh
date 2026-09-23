#!/usr/bin/env bash
# Rebuild the small RGBA star strips from the archived scores (ImageMagick).
set -euo pipefail
cd "$(dirname "$0")"
assets=WasmMenu/images
convert -background none "$assets/rating-star.svg" "PNG32:$assets/rating-star.png"
convert "$assets/rating-star.png" -channel RGB -fill '#455164' -colorize 100 "PNG32:$assets/rating-star-empty.png"
awk -F '|' '/^\|/ { gsub(/ /, "", $3); if ($3 ~ /^[0-9]+\.[0-9]+$/) print $3 }' ../game-info/*/README.md | sort -u |
while read -r score; do
    pixels=$(awk -v score="$score" 'BEGIN { printf "%.0f", score * 22 }')
    convert \( "$assets/rating-star-empty.png" -duplicate 4 +append \) \
        \( "$assets/rating-star.png" -duplicate 4 +append -crop "${pixels}x28+0+0" +repage \) \
        -gravity northwest -composite -background '#141b25' -alpha remove -alpha off "PNG24:$assets/score-$score.png"
done
