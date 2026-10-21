#!/usr/bin/env bash
# Searchable keybinds in rofi (SUPER SHIFT K).
#
# The list comes from the mango config (KeyHints.py --dump): every bind in
# ~/.config/mango/config.conf and the files it sources. A bind shows its
# description - the "  # text" comment at the end of its line; without one it
# lists as its dispatcher and arguments. KeyHints.py does the formatting so
# this and the cheat sheet (SUPER H) agree.

# kill yad / the cheat sheet to not interfere with these binds
pkill yad 2>/dev/null || true
pkill -f "^python3 .*KeyHints\.py" 2>/dev/null || true

if pidof rofi > /dev/null; then
  pkill rofi
fi

rofi_theme="$HOME/.config/rofi/config-keybinds.rasi"
msg='Только для просмотра: щелчок и Enter ничего не делают'

# "KEYS — DESCRIPTION", one per bind, SUPER first
display_keybinds=$("$(dirname "$(readlink -f "$0")")/KeyHints.py" --dump | awk -F'\t' '{ print $1 " — " $2 }')

if [[ -z "$display_keybinds" ]]; then
  echo "no keybinds found."
  exit 1
fi

printf '%s\n' "$display_keybinds" | rofi -dmenu -i -config "$rofi_theme" -mesg "$msg"
