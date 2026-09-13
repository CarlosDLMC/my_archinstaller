#!/bin/bash
# OPTIONAL: paint a Cyrillic title into a copy of the wallpaper.
#
# The shipped limine-wallpaper.png is used as delivered. If you want a title on it,
# this writes limine-wallpaper-titled.jpg (left side darkened for the menu text, title
# painted at the top) - point `wallpaper:` in theme.conf at that file and raise
# term_margin to ~180 so the menu box starts below the title. The title has to be in
# the picture because Limine's terminal maps text onto a 256-glyph CP437 font, which
# has no Cyrillic.
#
#   make-wallpaper.sh [WIDTHxHEIGHT] [title]     default 2560x1440, "ЗАГРУЗОЧНОЕ МЕНЮ"
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIZE="${1:-2560x1440}"; TITLE="${2:-ЗАГРУЗОЧНОЕ МЕНЮ}"
W="${SIZE%x*}"; H="${SIZE#*x}"
SRC="$HERE/limine-wallpaper.png"
FONT="$(fc-match -f '%{file}' 'Adwaita Sans:style=ExtraBold')"
# Fill the target box (scale so both dimensions are covered, then trim from the top so
# the signs stay), then darken the left ~47 % where Limine draws the entries, fading out
# towards the centre. "^" makes the resize cover, so a 16:10 or 4:3 target really is WxH.
DARK_W=$(( W * 47 / 100 ))
magick "$SRC" -resize "${W}x${H}^" -gravity north -extent "${W}x${H}" +repage \
  \( -size "${H}x${DARK_W}" gradient:'#000000d0'-'#00000000' -rotate -90 -background none -gravity west -extent "${W}x${H}" \) -compose over -composite \
  \( -size "${W}x$(( H * 15 / 100 ))" xc:none -font "$FONT" -pointsize $(( H * 61 / 1000 )) -gravity north -fill '#000000' -annotate +4+$(( H * 44 / 1000 )) "$TITLE" -blur 0x10 \) -gravity north -geometry +0+0 -composite \
  -font "$FONT" -pointsize $(( H * 61 / 1000 )) -gravity north -fill '#d42a2a' -stroke '#d42a2a' -strokewidth 2.5 -annotate +0+$(( H * 42 / 1000 )) "$TITLE" \
  -quality 92 "$HERE/limine-wallpaper-titled.jpg"
echo "wrote $HERE/limine-wallpaper-titled.jpg ($SIZE)"
