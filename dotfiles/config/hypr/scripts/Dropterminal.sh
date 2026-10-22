#!/usr/bin/env bash
#
# Made and brought to by Kiran George
# /* -- ✨ https://github.com/SherLock707 ✨ -- */  ##
# Dropdown Terminal
# Usage: ./Dropterminal.sh <terminal_command>
# Example: ./Dropterminal.sh foot
#
# SUPER+SHIFT+Return: the terminal slides down from above the screen, stays
# over every workspace until it is put away, and slides back up.
#
# The window is a mango named scratchpad (the dropterm rule in
# ~/.config/mango/rules.conf sizes and places it: 65% of the monitor, its top
# at 10% of the height), and mango slides a scratchpad down when it is shown
# and up when it is hidden. Shown, it is made global - on every workspace, as
# the pinned Hyprland dropdown was. Hiding it minimizes it, which hands it back
# to the scratchpad. On another monitor it comes to the focused one.

APP_ID=dropterm
WIDTH_PERCENT=65
HEIGHT_PERCENT=65
Y_PERCENT=10

cmd=${1:-foot}
case "$cmd" in
foot*) launch="$cmd --app-id=$APP_ID" ;;
kitty* | alacritty*) launch="$cmd --class $APP_ID" ;;
*) launch="$cmd" ;;
esac

dropdown() { # the dropdown window as mango lists it, or nothing
    mmsg get all-clients |
        jq -c --arg app "$APP_ID" '[.clients[] | select(.appid == $app)] | first // empty'
}

win=$(dropdown)
if [ -n "$win" ] && [ "$(jq -r '.is_minimized' <<<"$win")" = false ]; then
    id=$(jq -r '.id' <<<"$win")
    [ "$(jq -r '.is_global' <<<"$win")" = true ] &&
        mmsg dispatch toggleglobal "client,$id" >/dev/null
    exec mmsg dispatch minimized "client,$id" >/dev/null
fi

# Hidden, or not running yet: mango shows it (sliding down) or starts it.
mmsg dispatch "toggle_named_scratchpad,$APP_ID,none,$launch" >/dev/null

# A new terminal takes a moment to map.
for _ in $(seq 1 40); do
    win=$(dropdown)
    [ -n "$win" ] && [ "$(jq -r '.is_minimized' <<<"$win")" = false ] && break
    win=""
    sleep 0.05
done
[ -n "$win" ] || exit 0
id=$(jq -r '.id' <<<"$win")

[ "$(jq -r '.is_global' <<<"$win")" = true ] ||
    mmsg dispatch toggleglobal "client,$id" >/dev/null

# Brought over from another monitor, mango centres it: put it where it goes.
read -r dx dy w h < <(mmsg get all-monitors | jq -r --argjson win "$win" \
    --argjson wp "$WIDTH_PERCENT" --argjson hp "$HEIGHT_PERCENT" --argjson yp "$Y_PERCENT" '
    .monitors[] | select(.active)
    | (.width * $wp / 100 | floor) as $w | (.height * $hp / 100 | floor) as $h
    | "\(.x + ((.width - $w) / 2 | floor) - $win.x) \(.y + (.height * $yp / 100 | floor) - $win.y) \($w) \($h)"')
if [ -n "$dx" ] && jq -e --argjson dx "$dx" --argjson dy "$dy" --argjson w "$w" --argjson h "$h" '
    ($dx | fabs) > 8 or ($dy | fabs) > 8 or
    ((.width - $w) | fabs) > 8 or ((.height - $h) | fabs) > 8' <<<"$win" >/dev/null; then
    mmsg dispatch "resizewin,$w,$h" "client,$id" >/dev/null
    mmsg dispatch "$(printf 'movewin,%+d,%+d' "$dx" "$dy")" "client,$id" >/dev/null
fi
mmsg dispatch focusid "client,$id" >/dev/null
