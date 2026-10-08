#!/usr/bin/env bash
# Next keyboard layout: SUPER+SPACE, both ALT+SHIFT orders and the lock screen's
# layout label.
#
# The bar owns layout switching - quickshell keeps the most-recently-used order
# and shows the popup - so while it runs, the switch goes through its global
# shortcut. Without the bar (hidden with SUPER+CTRL+ALT+B, or crashed) that went
# nowhere: on the lock screen with the Russian layout active, the Latin password
# could not be typed, and only a TTY got the session back. Hyprland switches it
# then.
if pgrep -f '^qs -c bar' >/dev/null; then
    exec hyprctl dispatch 'hl.dsp.global("quickshell:layoutNext")' >/dev/null
fi
exec hyprctl switchxkblayout all next >/dev/null
