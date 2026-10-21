#!/usr/bin/env bash
# SUPER+TAB / SUPER+CTRL+TAB: next / previous tab of the focused group, going
# round from the last tab to the first and back as Hyprland did. mango's
# groupfocus stops at the ends; when it does not move, this walks back the
# other way to the far end.
dir=${1:-next}
[ "$dir" = next ] && back=prev || back=next

focused_id() { mmsg get focusing-client | jq -r '.id // empty'; }

start=$(focused_id)
[ -n "$start" ] || exit 0
mmsg dispatch "groupfocus,$dir" >/dev/null
[ "$(focused_id)" != "$start" ] && exit 0

# At the end: go to the other end. A group has a handful of tabs; the cap only
# guards against a loop if mango ever stops changing focus.
prev=$start
for _ in $(seq 1 32); do
    mmsg dispatch "groupfocus,$back" >/dev/null
    cur=$(focused_id)
    [ "$cur" = "$prev" ] && break
    prev=$cur
done
