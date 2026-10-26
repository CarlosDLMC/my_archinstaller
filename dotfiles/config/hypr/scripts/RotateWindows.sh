#!/usr/bin/env bash
# SUPER+R: rotate the tiled windows of the focused workspace one
# slot along the layout, every window at once (RotateWindows.sh [next|prev]).
#
# mango has no rotate, only exchange_stack_client, which swaps the focused
# window with its neighbour in the stack (wrapping at the ends) and keeps focus
# on it. Done once per window minus one, the focused window walks all the way
# round and every other window steps one slot the other way: a rotation, from
# whichever window has focus, and focus stays on the app it was on.
#
#   next   left half -> top right -> bottom right -> left half (on dwindle)
#   prev   the other way
#
# A group counts as one slot (only its shown tab is visible). Nothing happens
# when the focused window floats, or when fewer than two windows are tiled.

dir=${1:-next}
[ "$dir" = prev ] || dir=next

focused=$(mmsg get focusing-client)
[ "$(jq -r '.is_floating' <<<"$focused")" = false ] || exit 0

n=$(mmsg get all-clients | jq --argjson f "$focused" '[.clients[]
    | select(.monitor == $f.monitor and .is_visible and (.is_floating | not)
             and (.is_minimized | not) and (.is_scratchpad | not))] | length')
[ "${n:-0}" -ge 2 ] || exit 0

for ((i = 1; i < n; i++)); do
    mmsg dispatch "exchange_stack_client,$dir" >/dev/null
done
exit 0
