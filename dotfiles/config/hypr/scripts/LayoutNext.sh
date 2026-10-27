#!/usr/bin/env bash
# Next keyboard layout: SUPER+SPACE, both ALT+SHIFT orders and the lock screen's
# layout label.
#
# The bar owns layout switching - it keeps the most-recently-used order and
# shows the popup - so while it runs, the switch goes through its IPC.
# Without the bar (hidden with SUPER+CTRL+ALT+B, or crashed) that went nowhere:
# on the lock screen with the Russian layout active, the Latin password could
# not be typed, and only a TTY got the session back. mango switches it then:
# rust-bar msg fails when no bar answers on its socket.
if rust-bar msg layout next >/dev/null 2>&1; then
    exit 0
fi
exec mmsg dispatch switch_keyboard_layout >/dev/null
