#!/usr/bin/env bash
# Join the focused window into the workspace's group (one group per workspace).
# No group on the workspace yet -> the focused window becomes the group.
# The group need not be adjacent: the window walks towards it until it joins.

active=$(hyprctl activewindow -j)
addr=$(jq -r '.address // empty' <<<"$active")
[ -n "$addr" ] || exit 0
[ "$(jq '.grouped | length' <<<"$active")" -eq 0 ] || exit 0
ws=$(jq '.workspace.id' <<<"$active")

group=$(hyprctl clients -j | jq -c --arg a "$addr" --argjson ws "$ws" \
  'map(select(.workspace.id == $ws and .address != $a and (.grouped | length) > 0)) | first // empty')

if [ -z "$group" ]; then
  hyprctl dispatch 'hl.dsp.group.toggle()' >/dev/null
  exit 0
fi

for _ in 1 2 3 4 5 6; do
  read -r dir long <<<"$(jq -rn --argjson w "$(hyprctl activewindow -j)" --argjson g "$group" '
    (($g.at[0] + $g.size[0]/2) - ($w.at[0] + $w.size[0]/2)) as $dx |
    (($g.at[1] + $g.size[1]/2) - ($w.at[1] + $w.size[1]/2)) as $dy |
    if ($dx|fabs) >= ($dy|fabs)
    then (if $dx < 0 then "l left" else "r right" end)
    else (if $dy < 0 then "u up" else "d down" end) end')"
  hyprctl dispatch "hl.dsp.window.move({ into_group = '$dir' })" >/dev/null
  [ "$(hyprctl activewindow -j | jq '.grouped | length')" -gt 0 ] && exit 0
  hyprctl dispatch "hl.dsp.window.move({ direction = '$long' })" >/dev/null
done
