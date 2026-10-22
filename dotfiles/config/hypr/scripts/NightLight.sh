#!/usr/bin/env bash
set -euo pipefail

# Night light: toggle, status and the login restore (startup.conf `init`).
# The bar's ПУЛЬТ card switches it (quickshell/bar/NightLight.qml).
#
# wlsunset keeps the warm colour while it runs (wlr-gamma-control: the screen
# goes back to normal by itself when it exits). It has no fixed-temperature
# mode, only day and night temperatures: 3000 K at night and 3001 K by day is
# 3000 K around the clock.
#
# Customize via env vars:
#   NIGHTLIGHT_TEMP   default 3000 (K)

STATE_FILE="$HOME/.cache/.nightlight_state"
TARGET_TEMP="${NIGHTLIGHT_TEMP:-3000}"

ensure_state() {
  [[ -f "$STATE_FILE" ]] || echo "off" > "$STATE_FILE"
}

start_nightlight() {
  if command -v wlsunset >/dev/null 2>&1; then
    nohup wlsunset -t "$TARGET_TEMP" -T "$((TARGET_TEMP + 1))" -S 06:00 -s 18:00 \
      >/dev/null 2>&1 &
  fi
}

cmd_toggle() {
  ensure_state
  state="$(cat "$STATE_FILE" || echo off)"

  # Only one may hold the gamma ramps.
  pkill -x wlsunset || true

  if [[ "$state" == "on" ]]; then
    echo off > "$STATE_FILE"
    notify-send -t 1000 -u low "Ночной свет:" "выключен" || true
  else
    start_nightlight
    echo on > "$STATE_FILE"
    notify-send -t 1000 -u low "Ночной свет:" "включён, ${TARGET_TEMP} K" || true
  fi
}

cmd_status() {
  ensure_state
  # Prefer live process detection; fall back to state file
  if pgrep -x wlsunset >/dev/null 2>&1; then
    onoff="on"
  else
    onoff="$(cat "$STATE_FILE" || echo off)"
  fi

  if [[ "$onoff" == "on" ]]; then
    txt="<span size='18pt'>🌇</span>"
    cls="on"
    tip="Night light on @ ${TARGET_TEMP}K"
  else
    txt="<span size='16pt'>☀</span>"
    cls="off"
    tip="Night light off"
  fi
  printf '{"text":"%s","class":"%s","tooltip":"%s"}\n' "$txt" "$cls" "$tip"
}

cmd_init() {
  ensure_state
  state="$(cat "$STATE_FILE" || echo off)"
  if [[ "$state" == "on" ]]; then
    start_nightlight
  fi
}

case "${1:-}" in
  toggle) cmd_toggle ;;
  status) cmd_status ;;
  init) cmd_init ;;
  *) echo "usage: $0 [toggle|status|init]" >&2; exit 2 ;;
esac
