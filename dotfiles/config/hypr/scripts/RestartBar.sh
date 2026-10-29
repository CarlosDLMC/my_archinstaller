#!/usr/bin/env bash
# Restart the bar (SUPER+CTRL+B).
# mango starts it as plain `rust-bar` (startup.conf), so the whole command
# line is matched (-x -f): not `rust-bar crt` or `rust-bar msg ...`, and not a
# shell whose command line merely contains "rust-bar". A new bar exits at once
# while the old one still answers on its socket, so wait for it to be gone.
pkill -x -f '(/usr/bin/)?rust-bar'
for _ in $(seq 1 20); do
    pgrep -x -f '(/usr/bin/)?rust-bar' >/dev/null || break
    sleep 0.1
done
mkdir -p "$HOME/.cache/rust-bar"
exec rust-bar
