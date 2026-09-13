#!/bin/bash
# Rebuild assets/limine/limine-wallpaper.jpg from source-soviet_db.jpg.
#
# Why the title is painted into the picture: Limine's terminal maps text onto a
# 256-glyph CP437 font, so `interface_branding` cannot show Cyrillic. Painting it
# here also gives a real typeface instead of an 8x16 bitmap font.
#
#   make-wallpaper.sh [WIDTHxHEIGHT] [title]     default 2560x1440, "ЗАГРУЗОЧНОЕ МЕНЮ"
#
# Limine stretches the wallpaper to the screen, so only the aspect ratio matters;
# regenerate for a 16:10 or 4:3 monitor by passing its resolution.
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIZE="${1:-2560x1440}"; TITLE="${2:-ЗАГРУЗОЧНОЕ МЕНЮ}"
W="${SIZE%x*}"; H="${SIZE#*x}"
FONT="$(fc-match -f '%{file}' 'Adwaita Sans:style=ExtraBold')"
# Crop the source to the target aspect from the top (keeps the red signs), then darken
# the left ~47 % where Limine draws the entries, fading to nothing towards the centre.
DARK_W=$(( W * 47 / 100 ))
magick "$HERE/source-soviet_db.jpg" -resize "${W}x" -gravity north -crop "${W}x${H}+0+30" +repage \
  \( -size "${H}x${DARK_W}" gradient:'#000000d0'-'#00000000' -rotate -90 -background none -gravity west -extent "${W}x${H}" \) -compose over -composite \
  \( -size "${W}x$(( H * 15 / 100 ))" xc:none -font "$FONT" -pointsize $(( H * 61 / 1000 )) -gravity north -fill '#000000' -annotate +4+$(( H * 44 / 1000 )) "$TITLE" -blur 0x10 \) -gravity north -geometry +0+0 -composite \
  -font "$FONT" -pointsize $(( H * 61 / 1000 )) -gravity north -fill '#d42a2a' -stroke '#d42a2a' -strokewidth 2.5 -annotate +0+$(( H * 42 / 1000 )) "$TITLE" \
  -quality 92 "$HERE/limine-wallpaper.jpg"
echo "wrote $HERE/limine-wallpaper.jpg ($SIZE)"
