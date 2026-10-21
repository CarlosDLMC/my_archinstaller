#!/usr/bin/env bash
# SUPER+SHIFT+TAB / SUPER+ALT+TAB: move the focused tab one place right (next)
# or left (prev) in its group. As on Hyprland, the tab swaps places with its
# neighbour, and at either end it swaps with the tab at the other end.
#
# mango has no dispatcher for it. groupjoin puts a window in front of the tab
# it joins and groupleave takes the shown tab out, so a tab is moved by taking
# a window out of the group and joining it back in front of another one.
dir=${1:-next}

focused_id() { mmsg get focusing-client | jq -r '.id // empty'; }

# Put tab $1 in front of tab $2 (same group). $1 ends up shown and focused.
move_before() {
    local x=$1 y=$2 d
    mmsg dispatch focusid "client,$x" >/dev/null
    mmsg dispatch groupleave >/dev/null
    mmsg dispatch focusid "client,$y" >/dev/null
    # The window that left sits beside the group's tile: join towards it.
    d=$(mmsg get all-clients | jq -r --argjson x "$x" --argjson y "$y" '
        (.clients[] | select(.id == $x)) as $w |
        (.clients[] | select(.id == $y)) as $g |
        (($g.x + $g.width / 2) - ($w.x + $w.width / 2)) as $dx |
        (($g.y + $g.height / 2) - ($w.y + $w.height / 2)) as $dy |
        if ($dx | fabs) >= ($dy | fabs)
        then (if $dx < 0 then "left" else "right" end)
        else (if $dy < 0 then "up" else "down" end) end')
    [ -n "$d" ] && mmsg dispatch "groupjoin,$d" "client,$x" >/dev/null
}

me=$(focused_id)
[ -n "$me" ] || exit 0
[ "$(mmsg get focusing-client | jq -r '.is_group')" = true ] || exit 0

# The neighbour, by showing it.
mmsg dispatch "groupfocus,$dir" >/dev/null
other=$(focused_id)
if [ -n "$other" ] && [ "$other" != "$me" ]; then
    if [ "$dir" = next ]; then
        move_before "$other" "$me"
        mmsg dispatch focusid "client,$me" >/dev/null
    else
        move_before "$me" "$other"
    fi
    exit 0
fi

# At the end: swap with the tab at the other end. The hidden tabs, in group
# order, follow the shown one in mango's window list - here every tab but this
# one, which is the last (next) or the first (prev).
mapfile -t rest < <(mmsg get all-clients | jq -r --argjson me "$me" '
    .clients as $c
    | ($c | map(.id) | index($me)) as $i
    | $c[$i + 1:]
    | (map(.is_group and (.is_group_focus | not)) | index(false) // length) as $n
    | .[:$n][].id')
[ ${#rest[@]} -gt 0 ] || exit 0

if [ "$dir" = next ]; then
    # first .. last(me) -> me .. first
    first=${rest[0]}
    move_before "$me" "$first"
    for m in "${rest[@]:1}"; do move_before "$m" "$first"; done
else
    # first(me) .. last -> last .. me
    last=${rest[-1]}
    move_before "$last" "$me"
    for m in "${rest[@]:0:${#rest[@]}-1}"; do move_before "$m" "$me"; done
fi
mmsg dispatch focusid "client,$me" >/dev/null
