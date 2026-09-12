#!/usr/bin/env bash
# Airplane Mode. Turning on or off all wifi using rfkill. 

notif="$HOME/.config/swaync/images/ja.png"

# Check if any wireless device is blocked
wifi_blocked=$(rfkill list wifi | grep -o "Soft blocked: yes")

if [ -n "$wifi_blocked" ]; then
    rfkill unblock wifi
    notify-send -t 1000 -u low -i "$notif" " Airplane" " mode: OFF"
else
    rfkill block wifi
    notify-send -t 1000 -u low -i "$notif" " Airplane" " mode: ON"
fi
