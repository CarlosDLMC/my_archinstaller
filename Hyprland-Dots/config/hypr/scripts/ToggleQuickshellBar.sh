#!/usr/bin/env bash
# Toggle quickshell bar visibility

# Check if quickshell bar is running
if pgrep -f "qs -c bar" > /dev/null; then
    # Bar is running, kill it
    pkill -f "qs -c bar"
else
    # Bar is not running, start it
    qs -c bar &
fi
