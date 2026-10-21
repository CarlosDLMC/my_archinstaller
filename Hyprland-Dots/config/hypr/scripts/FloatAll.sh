#!/usr/bin/env bash
# Float or tile every window on the current workspace (SUPER+ALT+SPACE).
# If any window there is tiled, all of them float; if all of them already
# float, all of them tile again. (mango's own toggle_all_floating decides by
# the focused window alone.)

clients=$(mmsg get all-clients) || exit 1
mon=$(mmsg get all-monitors | jq -r '.monitors[] | select(.active) | .name')
tag=$(mmsg get all-monitors | jq -r '.monitors[] | select(.active) | .active_tags[0] // empty')
[ -n "$mon" ] && [ -n "$tag" ] || exit 0

# Windows of this monitor that are on the shown workspace (sticky ones too).
mapfile -t rows < <(jq -r --arg mon "$mon" --argjson tag "$tag" '
    .clients[]
    | select(.monitor == $mon and .is_visible and (.is_global or (.tags | index($tag))))
    | "\(.id) \(.is_floating)"' <<<"$clients")
[ ${#rows[@]} -gt 0 ] || exit 0

any_tiled=false
for r in "${rows[@]}"; do
    [ "${r#* }" = false ] && any_tiled=true
done

for r in "${rows[@]}"; do
    id=${r%% *} floating=${r#* }
    if $any_tiled; then
        [ "$floating" = false ] && mmsg dispatch togglefloating "client,$id" >/dev/null
    else
        mmsg dispatch togglefloating "client,$id" >/dev/null
    fi
done
