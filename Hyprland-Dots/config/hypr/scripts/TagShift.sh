#!/usr/bin/env bash
# SUPER+CTRL+[ / SUPER+CTRL+]: move the focused window to the previous / next
# workspace without following it. (mango's tagtoleft/tagtoright follow the
# window; there is no silent variant.)
dir=${1:-next}
read -r tag num < <(mmsg get all-monitors |
    jq -r '.monitors[] | select(.active) | "\(.active_tags[0] // 0) \(.tag_num)"')
[ -n "$tag" ] && [ "$tag" -gt 0 ] || exit 0

if [ "$dir" = next ]; then target=$((tag + 1)); else target=$((tag - 1)); fi
[ "$target" -ge 1 ] && [ "$target" -le "${num:-10}" ] || exit 0
exec mmsg dispatch "tagsilent,$target" >/dev/null
