#!/usr/bin/env bash
# Change Hyprland layout (Master or Dwindle) on the fly.
# Runtime-only: a config reload goes back to general.layout from SystemSettings.lua.

notif="$HOME/.config/swaync/images/ja.png"

LAYOUT=$(hyprctl -j getoption general.layout | jq -r '.str')

case $LAYOUT in
"master")
	hyprctl eval 'hl.config({ general = { layout = "dwindle" } })'
	# SUPER+J/K are global (configs/Keybinds.lua); only SUPER+O is layout-specific
	hyprctl eval 'hl.bind("SUPER + O", hl.dsp.layout("togglesplit"), { description = "toggle split (dwindle)" })'
	notify-send -t 1000 -e -u low -i "$notif" " Dwindle Layout"
	;;
"dwindle")
	hyprctl eval 'hl.config({ general = { layout = "master" } })'
	# Drop the togglesplit bind on SUPER+O when switching back to master
	hyprctl eval 'hl.unbind("SUPER + O")'
	notify-send -t 1000 -e -u low -i "$notif" " Master Layout"
	;;
*) ;;
esac
