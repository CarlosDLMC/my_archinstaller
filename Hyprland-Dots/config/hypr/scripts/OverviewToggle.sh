#!/usr/bin/env bash
# Overview toggle wrapper - tries Quickshell first, falls back to AGS

set -euo pipefail

# 1) Try Quickshell via IPC (works if QS is running and listening)
if pgrep -f "qs -c overview" >/dev/null 2>&1; then
  if qs ipc -c overview call overview toggle >/dev/null 2>&1; then
    exit 0
  fi
fi

# Not answering yet: start it if it is not running, then retry for up to ~3 s.
# A freshly started overview takes a moment before its IPC answers, and one try
# after a fixed 0.6 s often came too early - the first SUPER+A of a session fell
# through to "Neither Quickshell nor AGS is available". It also used to start a
# second instance when the first was running but slow to answer.
if command -v qs >/dev/null 2>&1; then
  if ! pgrep -f "qs -c overview" >/dev/null 2>&1; then
    qs -c overview >/dev/null 2>&1 &
  fi
  for _ in $(seq 1 15); do
    sleep 0.2
    if qs ipc -c overview call overview toggle >/dev/null 2>&1; then
      exit 0
    fi
  done
fi

# 2) Fall back to AGS template
if command -v ags >/dev/null 2>&1; then
  pkill rofi || true
  if ags -t 'overview' >/dev/null 2>&1; then
    exit 0
  fi
  # If it failed, try starting AGS daemon then call the template
  ags >/dev/null 2>&1 &
  sleep 0.6
  if ags -t 'overview' >/dev/null 2>&1; then
    exit 0
  fi
fi

# If we get here, neither worked
notify-send "Overview" "Neither Quickshell nor AGS is available" -u low 2>/dev/null || true
exit 1
