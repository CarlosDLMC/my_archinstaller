#!/usr/bin/env bash
# Game Mode. Turns off animations, blur, shadows, gaps and rounding, and makes
# every window opaque. `hyprctl reload` undoes all of it (the runtime values and
# the extra window rule only live until the next reload).

notif="$HOME/.config/swaync/images/ja.png"
SCRIPTSDIR="$HOME/.config/hypr/scripts"

# "true"/"false" with the Lua config manager (it was int 1/0 with hyprlang)
HYPRGAMEMODE=$(hyprctl -j getoption animations.enabled | jq -r 'if has("bool") then .bool else (.int == 1) end')
if [ "$HYPRGAMEMODE" = "true" ] ; then
    hyprctl eval 'hl.config({
        animations = { enabled = false },
        decoration = { shadow = { enabled = false }, blur = { enabled = false }, rounding = 0 },
        general    = { gaps_in = 0, gaps_out = 0, border_size = 1 },
    })'
    hyprctl eval 'hl.window_rule({ name = "gamemode-opaque", match = { class = ".*" }, opacity = "1 override 1 override 1 override" })'
    awww kill
    notify-send -t 1000 -e -u low -i "$notif" " Gamemode:" " enabled"
    sleep 0.1
    exit
else
	awww-daemon --format argb && awww img "$HOME/.config/rofi/.current_wallpaper" &
	sleep 0.1
	${SCRIPTSDIR}/WallustSwww.sh
	sleep 0.5
  hyprctl reload
	${SCRIPTSDIR}/Refresh.sh
    notify-send -t 1000 -e -u normal -i "$notif" " Gamemode:" " disabled"
    exit
fi
