#!/usr/bin/env bash
# Quick Cheat Sheet (SUPER H): a searchable window listing the keybinds
# Hyprland has loaded right now. The window itself is KeyHints.py (GTK3,
# python-gobject); this wrapper only makes SUPER H a toggle and closes any
# rofi/yad dialog that would sit on top of it.

# Pressing SUPER H while the sheet is open closes it.
if pkill -f "^python3 .*KeyHints\.py" 2>/dev/null; then
  exit 0
fi

pidof rofi >/dev/null && pkill rofi
pidof yad  >/dev/null && pkill yad

exec python3 "$(dirname "$(readlink -f "$0")")/KeyHints.py"
