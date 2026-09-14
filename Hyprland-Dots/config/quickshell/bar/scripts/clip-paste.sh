#!/usr/bin/env bash
# Paste the clipboard into whatever window had focus before the picker opened.
#
# Lifted from the rofi ClipManager.sh this replaced, because it is the part of
# that script worth keeping: picking an entry should put it where you were
# typing, not merely load the clipboard and leave you to press Ctrl+V yourself.
#
# Terminals take Ctrl+Shift+V, everything else Ctrl+V. wtype types through
# Hyprland's virtual-keyboard protocol; the short sleep lets focus return to the
# window after the overlay closes, otherwise the keystroke lands nowhere.
#
# 60ms, not the 150ms the rofi script used: rofi was a real window that had to
# be unmapped, whereas this overlay drops its keyboard focus the instant it
# closes, so there is far less to wait for.

set -uo pipefail

command -v wtype >/dev/null 2>&1 || exit 0
sleep 0.06

class=$(hyprctl -j activewindow 2>/dev/null | jq -r '.class // ""')

case "$class" in
  foot|footclient|kitty|Alacritty|com.mitchellh.ghostty|org.wezfurlong.wezterm|xterm|st|st-256color|konsole|org.kde.konsole|Gnome-terminal|org.gnome.Terminal)
    wtype -M ctrl -M shift -k v -m shift -m ctrl ;;
  "")
    # Nothing focused - leave it on the clipboard rather than typing into the void.
    ;;
  *)
    wtype -M ctrl -k v -m ctrl ;;
esac
