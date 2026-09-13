# Rebuild assets/limine/limine-wallpaper.jpg from source-kgb_server_hall_4k.png.
#
# Why the title is painted into the picture: Limine's terminal maps text onto a
# 256-glyph CP437 font, so `interface_branding` cannot show Cyrillic. Painting it
# here also gives a real typeface instead of an 8x16 bitmap font.
#
#   make-wallpaper.sh [WIDTHxHEIGHT] [title]     default 2560x1440, "ЗАГРУЗОЧНОЕ МЕНЮ"
#
# The source is a native 16:9 3840x2160 render, so for any 16:9 target it only scales
# down and nothing is cropped. Limine stretches the wallpaper to the screen, so only
# the aspect ratio matters; for a 16:10 or 4:3 monitor pass its resolution and the
# excess is cropped from the bottom (the signs are at the top).
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIZE="${1:-2560x1440}"; TITLE="${2:-ЗАГРУЗОЧНОЕ МЕНЮ}"
W="${SIZE%x*}"; H="${SIZE#*x}"
SRC="$HERE/source-kgb_server_hall_4k.png"
FONT="$(fc-match -f '%{file}' 'Adwaita Sans:style=ExtraBold')"
# Scale to the target width, crop the target height from the top (keeps the signs), then
# darken the left ~47 % where Limine draws the entries, fading out towards the centre.
DARK_W=$(( W * 47 / 100 ))
magick "$SRC" -resize "${W}x" -gravity north -crop "${W}x${H}+0+0" +repage \
  \( -size "${H}x${DARK_W}" gradient:'#000000d0'-'#00000000' -rotate -90 -background none -gravity west -extent "${W}x${H}" \) -compose over -composite \
  \( -size "${W}x$(( H * 15 / 100 ))" xc:none -font "$FONT" -pointsize $(( H * 61 / 1000 )) -gravity north -fill '#000000' -annotate +4+$(( H * 44 / 1000 )) "$TITLE" -blur 0x10 \) -gravity north -geometry +0+0 -composite \
  -font "$FONT" -pointsize $(( H * 61 / 1000 )) -gravity north -fill '#d42a2a' -stroke '#d42a2a' -strokewidth 2.5 -annotate +0+$(( H * 42 / 1000 )) "$TITLE" \
  -quality 92 "$HERE/limine-wallpaper.jpg"
echo "wrote $HERE/limine-wallpaper.jpg ($SIZE)"
