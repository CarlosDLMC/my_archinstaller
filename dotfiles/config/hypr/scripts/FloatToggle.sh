#!/usr/bin/env bash
# SUPER+SHIFT+SPACE: float or tile the focused window (or window id $1).
#
# A tiled window floats over the tile it leaves, as on Hyprland: centred on
# the tile at its last floating size (10 px bigger when that is the tile's own
# size, so the change shows) and kept inside the work area. mango centres it on
# the monitor instead, so it is moved back over its tile. The work area's top
# is the bar's bottom edge: 34 px, scaled down on narrow screens as
# rust-bar/src/bar.rs does.

id=${1:-$(mmsg get focusing-client | jq -r '.id // empty')}
[ -n "$id" ] || exit 0
window() { mmsg get all-clients | jq -c --argjson id "$id" '.clients[] | select(.id == $id)'; }

before=$(window)
[ -n "$before" ] || exit 0
mmsg dispatch togglefloating "client,$id" >/dev/null
[ "$(jq -r '.is_floating' <<<"$before")" = false ] || exit 0

after=$(window)
mon=$(mmsg get all-monitors | jq -c --arg name "$(jq -r '.monitor' <<<"$after")" \
    '.monitors[] | select(.name == $name)')
[ -n "$after" ] && [ -n "$mon" ] || exit 0

read -r dx dy grow < <(jq -rn --argjson b "$before" --argjson a "$after" --argjson m "$mon" '
    ($m.y + (34 * ([([$m.width / 2560, 1] | min), 0.9] | max)) | round) as $top
    | (if (($a.width - $b.width) | fabs) < 5 and (($a.height - $b.height) | fabs) < 5
       then 10 else 0 end) as $grow
    | ($a.width + $grow) as $w | ($a.height + $grow) as $h
    | ([($b.x + $b.width / 2 - $w / 2 | round), $m.x] | max) as $x
    | ([($b.y + $b.height / 2 - $h / 2 | round), $top] | max) as $y
    | (if $x + $w > $m.x + $m.width then $m.x + $m.width - $w else $x end) as $x
    | (if $y + $h > $m.y + $m.height then $m.y + $m.height - $h else $y end) as $y
    | "\($x - $a.x) \($y - $a.y) \($grow)"')
[ -n "$dx" ] || exit 0

mmsg dispatch "$(printf 'movewin,%+d,%+d' "$dx" "$dy")" "client,$id" >/dev/null
[ "$grow" -gt 0 ] && mmsg dispatch "resizewin,+$grow,+$grow" "client,$id" >/dev/null
exit 0
