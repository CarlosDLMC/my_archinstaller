#!/usr/bin/env bash
# SUPER+G: tab group on or off for the focused window.
#
# A window in a group leaves it. A window outside one joins the nearest
# visible tiled window into a group with it: mango has no single-window groups
# (Hyprland made the focused window a group of one, and then new windows
# joined it by themselves), so a group starts with two windows.

focused=$(mmsg get focusing-client)
id=$(jq -r '.id // empty' <<<"$focused")
[ -n "$id" ] || exit 0

if [ "$(jq -r '.is_group' <<<"$focused")" = true ]; then
    exec mmsg dispatch groupleave >/dev/null
fi

# The direction of the closest other visible tiled window on this monitor,
# measured between the centres of the two windows.
dir=$(mmsg get all-clients | jq -r --argjson me "$focused" '
    def cx: .x + .width / 2;
    def cy: .y + .height / 2;
    [ .clients[]
      | select(.id != $me.id and .monitor == $me.monitor and .is_visible and (.is_floating | not))
      | { dx: (cx - ($me | cx)), dy: (cy - ($me | cy)) }
      | . + { d: (.dx * .dx + .dy * .dy) } ]
    | sort_by(.d) | first // empty
    | if (.dx | fabs) >= (.dy | fabs)
      then (if .dx < 0 then "left" else "right" end)
      else (if .dy < 0 then "up" else "down" end) end')
[ -n "$dir" ] || exit 0
exec mmsg dispatch "groupjoin,$dir" >/dev/null
