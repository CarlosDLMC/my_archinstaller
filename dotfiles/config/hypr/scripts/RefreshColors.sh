#!/usr/bin/env bash

# Refresh after the colours change without a menu in front: re-runs wallust
# (synchronously, so the palette is ready) and refreshes rofi and dunst.
# Used by the automatic wallpaper change, the animations menu and monitor
# profiles; Refresh.sh is the full one behind SUPER+ALT+R.

SCRIPTSDIR=$HOME/.config/hypr/scripts
UserScripts=$HOME/.config/hypr/UserScripts

# Define file_exists function
file_exists() {
    if [ -e "$1" ]; then
        return 0  # File exists
    else
        return 1  # File does not exist
    fi
}

# Kill already running processes
_ps=(rofi)
for _prs in "${_ps[@]}"; do
    if pidof "${_prs}" >/dev/null; then
        pkill "${_prs}"
    fi
done

# quit ags & relaunch ags
#ags -q && ags &

# The bar is deliberately NOT restarted here.
#
# It refreshes itself: rust-bar watches ~/.config/rust-bar and reloads
# wallust-colors.json when wallust rewrites it (rust-bar/src/services.rs), so
# colours derived from a new wallpaper are picked up live. Killing it was the
# reason the bar vanished and reappeared every time the wallpaper changed.
#
# To restart the bar: SUPER+CTRL+B (RestartBar.sh).

# Wallust refresh (synchronous to ensure colors are ready)
${SCRIPTSDIR}/WallustSwww.sh
sleep 0.2

# Reload dunst's settings. NOT `killall -SIGUSR1 dunst`: that line replaced
# `makoctl reload` in the switch from mako, but for dunst SIGUSR1 means PAUSE
# (dunst(1): "send SIGUSR1 and SIGUSR2 to pause and unpause"). Every wallpaper
# change, refresh and game-mode toggle held all notifications - the volume and
# brightness popups included - until a restart or a click on the bar's bell.
dunstctl reload >/dev/null 2>&1

# Relaunching rainbow borders if the script exists
sleep 1
if file_exists "${UserScripts}/RainbowBorders.sh"; then
    ${UserScripts}/RainbowBorders.sh &
fi


exit 0