#!/usr/bin/env bash
# Toggle between light and heavy blur. Runtime-only: a config reload restores
# the values from UserConfigs/UserDecorations.lua.

STATE=$(hyprctl -j getoption decoration.blur.passes | jq ".int")

if [ "$STATE" -eq 2 ]; then
	hyprctl eval 'hl.config({ decoration = { blur = { size = 2, passes = 1 } } })'
else
	hyprctl eval 'hl.config({ decoration = { blur = { size = 5, passes = 2 } } })'
fi
