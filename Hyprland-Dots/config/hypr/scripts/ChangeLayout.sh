#!/usr/bin/env bash
# Change Hyprland layout (Master or Dwindle) on the fly.
# Runtime-only: a config reload goes back to general.layout from SystemSettings.lua.
# Only the layout changes: togglesplit has its own key (SUPER + SHIFT + I), and
# SUPER + O is "move window out of its group" in both layouts.

notif="$HOME/.config/swaync/images/ja.png"

LAYOUT=$(hyprctl -j getoption general.layout | jq -r '.str')

case $LAYOUT in
"master")
	hyprctl eval 'hl.config({ general = { layout = "dwindle" } })'
	notify-send -t 1000 -e -u low -i "$notif" " Dwindle Layout"
	;;
"dwindle")
	hyprctl eval 'hl.config({ general = { layout = "master" } })'
	notify-send -t 1000 -e -u low -i "$notif" " Master Layout"
	;;
*) ;;
esac
