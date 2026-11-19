#!/usr/bin/env bash
# Rescue for a monitor that shows "out of range" / "no signal": every output
# to 1920x1080 at 60 Hz (1280x720 if it has no such mode), scale 1. Bound to
# SUPER+CTRL+ALT+R so it works blind. For this session only - monitors.conf
# is untouched, so fix the cause there (or in the kernel's EDID override).

iDIR="$HOME/.config/hypr/notify/images"

for out in $(wlr-randr --json | jq -r '.[].name'); do
  wlr-randr --output "$out" --on --mode 1920x1080@60 --scale 1 2>/dev/null ||
    wlr-randr --output "$out" --on --mode 1280x720@60 --scale 1 2>/dev/null ||
    wlr-randr --output "$out" --on --preferred --scale 1
done

notify-send -u normal -i "$iDIR/note.png" "Безопасный режим экрана" \
  "Все мониторы: 1920x1080, 60 Гц - до конца сеанса."
