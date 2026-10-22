#!/usr/bin/env bash
# SUPER+CTRL+F9..F12: move the current workspace to the monitor on the left,
# right, above or below, and show it there.
#
# mango's workspaces (tags) belong to their monitor, so it cannot move one
# whole: every window of it moves instead, keeping its workspace number, and
# the other monitor then shows that workspace.
dir=${1:?left, right, up or down}

read -r mon tag < <(mmsg get all-monitors |
    jq -r '.monitors[] | select(.active) | "\(.name) \(.active_tags[0] // 0)"')
[ -n "$mon" ] && [ "${tag:-0}" -gt 0 ] || exit 0

# A group's hidden tabs go with its shown one, so they are left out (mango
# keeps their old workspace on them in the list).
mmsg get all-clients | jq -r --arg mon "$mon" --argjson tag "$tag" '
    .clients[]
    | select(.monitor == $mon and (.tags | index($tag)) and (.is_global | not)
             and ((.is_group and (.is_group_focus | not)) | not))
    | .id' |
    while read -r id; do
        mmsg dispatch "tagmon,$dir,1" "client,$id" >/dev/null
    done
