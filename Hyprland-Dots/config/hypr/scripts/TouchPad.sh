#!/usr/bin/env bash
# Toggle the touchpad on/off (XF86TouchpadToggle).
#
# With the Lua config `hyprctl keyword` no longer exists, so this flips the
# per-device `enabled` flag through `hyprctl eval 'hl.device({...})'`.
#
# Which device is the touchpad comes from udev (ID_INPUT_TOUCHPAD=1), mapped to
# Hyprland's device name (lowercase, spaces to dashes - what `hyprctl devices`
# prints). Hyprland does not tag devices by type and touchpad names rarely
# contain "touchpad" (this ThinkPad's is "synaptics-tm3276-022"), so a name
# match alone is not enough; it is only the fallback.

notif="$HOME/.config/swaync/images/ja.png"

export STATUS_FILE="$XDG_RUNTIME_DIR/touchpad.status"

touchpad_names() {
    local e name found=0
    for e in /sys/class/input/event*; do
        if udevadm info -q property -n "/dev/input/$(basename "$e")" 2>/dev/null | grep -q '^ID_INPUT_TOUCHPAD=1'; then
            name=$(tr 'A-Z ' 'a-z-' < "$e/device/name")
            [ -n "$name" ] && { echo "$name"; found=1; }
        fi
    done
    # fallback: anything Hyprland lists that looks like a touchpad
    [ "$found" = 1 ] || hyprctl -j devices | jq -r '.mice[].name | select(test("touchpad|trackpad|synaptics|elan"; "i"))'
}

set_touchpads() {
    local enabled="$1" dev
    while IFS= read -r dev; do
        [ -n "$dev" ] || continue
        hyprctl eval "hl.device({ name = '$dev', enabled = $enabled })" >/dev/null
    done < <(touchpad_names)
}

enable_touchpad() {
    printf "true" >"$STATUS_FILE"
    notify-send -t 1000 -u low -i $notif  " Enabling" " touchpad"
    set_touchpads true
}

disable_touchpad() {
    printf "false" >"$STATUS_FILE"
    notify-send -t 1000 -u low -i $notif " Disabling" " touchpad"
    set_touchpads false
}

if ! [ -f "$STATUS_FILE" ]; then
  enable_touchpad
else
  if [ $(cat "$STATUS_FILE") = "true" ]; then
    disable_touchpad
  elif [ $(cat "$STATUS_FILE") = "false" ]; then
    enable_touchpad
  fi
fi
