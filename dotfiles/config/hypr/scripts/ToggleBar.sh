#!/usr/bin/env bash
# Toggle the bar on/off (SUPER+CTRL+ALT+B). The whole command line is matched,
# as in RestartBar.sh.
if pgrep -x -f '(/usr/bin/)?rust-bar' >/dev/null; then
    pkill -x -f '(/usr/bin/)?rust-bar'
else
    mkdir -p "$HOME/.cache/rust-bar"
    setsid -f rust-bar >/dev/null 2>&1
fi
