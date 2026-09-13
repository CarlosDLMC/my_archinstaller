#!/usr/bin/env bash
# Searchable keybinds in rofi (SUPER SHIFT K).
#
# The list comes from `hyprctl binds`, i.e. the binds Hyprland actually has
# loaded right now - the Lua config builds binds in loops and helper functions,
# so parsing the config files by hand would miss half of them. A bind shows its
# description; give every hl.bind() one, or it lists as "(no description)".
# KeyHints.py does the formatting so this and the cheat sheet (SUPER H) agree.

# kill yad / the cheat sheet to not interfere with these binds
pkill yad 2>/dev/null || true
pkill -f "^python3 .*KeyHints\.py" 2>/dev/null || true

if pidof rofi > /dev/null; then
  pkill rofi
fi

rofi_theme="$HOME/.config/rofi/config-keybinds.rasi"
msg='☣️ NOTE ☣️: Clicking with Mouse or Pressing ENTER will have NO function'

# "KEYS — DESCRIPTION", one per bind, SUPER first
display_keybinds=$("$(dirname "$(readlink -f "$0")")/KeyHints.py" --dump | awk -F'\t' '{ print $1 " — " $2 }')

if [[ -z "$display_keybinds" ]]; then
  echo "no keybinds found."
  exit 1
fi

printf '%s\n' "$display_keybinds" | rofi -dmenu -i -config "$rofi_theme" -mesg "$msg"
