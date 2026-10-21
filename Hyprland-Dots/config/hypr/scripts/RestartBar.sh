#!/usr/bin/env bash
# Restart the quickshell bar (SUPER+CTRL+B).
# The bar runs as `qs -c bar`, so its process name is "qs", not "quickshell".
# The pattern is anchored with ^ so it cannot match a shell whose command line
# merely contains "qs -c bar". `;` and not `&&`, so a pkill that matches
# nothing still starts the bar.
pkill -f '^qs -c bar'
sleep 0.5
mkdir -p "$HOME/.cache/quickshell"
exec qs -c bar
