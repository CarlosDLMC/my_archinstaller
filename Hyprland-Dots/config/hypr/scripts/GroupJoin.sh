#!/usr/bin/env bash
# Join the focused window into the workspace's group (one group per workspace).
# No group on the workspace yet -> the focused window and its nearest neighbour
# become one (GroupToggle.sh; mango has no single-window groups).
# The group need not be adjacent: the window walks towards it until it joins.

active=$(mmsg get focusing-client)
id=$(jq -r '.id // empty' <<<"$active")
[ -n "$id" ] || exit 0
[ "$(jq -r '.is_group' <<<"$active")" = true ] && exit 0

# The visible tab of a group on this monitor's shown workspace.
group=$(mmsg get all-clients | jq -c --argjson me "$active" '
    [ .clients[] | select(.id != $me.id and .monitor == $me.monitor and .is_visible and .is_group) ]
    | first // empty')

if [ -z "$group" ]; then
    exec "$HOME/.config/hypr/scripts/GroupToggle.sh"
fi

for _ in 1 2 3 4 5 6; do
    dir=$(jq -rn --argjson w "$(mmsg get focusing-client)" --argjson g "$group" '
        (($g.x + $g.width / 2) - ($w.x + $w.width / 2)) as $dx |
        (($g.y + $g.height / 2) - ($w.y + $w.height / 2)) as $dy |
        if ($dx | fabs) >= ($dy | fabs)
        then (if $dx < 0 then "left" else "right" end)
        else (if $dy < 0 then "up" else "down" end) end')
    mmsg dispatch "groupjoin,$dir" >/dev/null
    [ "$(mmsg get focusing-client | jq -r '.is_group')" = true ] && exit 0
    mmsg dispatch "move_client,$dir" >/dev/null
done
