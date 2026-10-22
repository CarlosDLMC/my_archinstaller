#!/usr/bin/env bash
# Next keyboard layout: SUPER+SPACE, both ALT+SHIFT orders and the lock screen's
# layout label.
#
# The bar owns layout switching - quickshell keeps the most-recently-used order
# and shows the popup - so while it runs, the switch goes through its IPC.
# Without the bar (hidden with SUPER+CTRL+ALT+B, or crashed) that went nowhere:
# on the lock screen with the Russian layout active, the Latin password could
# not be typed, and only a TTY got the session back. mango switches it then.
if pgrep -f '^qs -c bar' >/dev/null; then
    exec qs -c bar ipc call layout next >/dev/null
fi
exec mmsg dispatch switch_keyboard_layout >/dev/null
