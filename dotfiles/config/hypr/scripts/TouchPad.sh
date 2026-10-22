#!/usr/bin/env bash
# Toggle the touchpad on/off (XF86TouchpadToggle, laptop.conf).
#
# mango switches every touchpad off with disable_trackpad=1. The setting goes
# into a file on the runtime tmpfs that mango sources on laptops
# (state/machine.conf, written by MachineConf.sh); mango reloads when it
# changes. So a switched-off touchpad stays off across config reloads, and is
# on again at the next login.

notif="$HOME/.config/hypr/notify/images/ja.png"
state="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/mango-touchpad.conf"

if grep -q '^disable_trackpad=1$' "$state" 2>/dev/null; then
    printf 'disable_trackpad=0\n' >"$state"
    notify-send -t 1000 -u low -i "$notif" "Сенсорная панель:" "включена"
else
    printf 'disable_trackpad=1\n' >"$state"
    notify-send -t 1000 -u low -i "$notif" "Сенсорная панель:" "выключена"
fi
