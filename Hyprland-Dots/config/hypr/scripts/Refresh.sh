#!/usr/bin/env bash
# Scripts for refreshing quickshell, rofi, mako, wallust

SCRIPTSDIR=$HOME/.config/hypr/scripts
UserScripts=$HOME/.config/hypr/UserScripts

# Define file_exists function
file_exists() {
  if [ -e "$1" ]; then
    return 0 # File exists
  else
    return 1 # File does not exist
  fi
}

# Kill already running processes
_ps=(rofi ags)
for _prs in "${_ps[@]}"; do
  if pidof "${_prs}" >/dev/null; then
    pkill "${_prs}"
  fi
done

sleep 0.1

# quit ags & relaunch ags
#ags -q && ags &

# Quickshell is deliberately NOT restarted here.
#
# It refreshes itself: Quickshell hot-reloads its QML when the files change, and
# bar/Theme.qml watches wallust-colors.json through a FileView with
# watchChanges, so colours derived from a new wallpaper are picked up live.
# Killing it was the reason the bar vanished and reappeared every time the
# wallpaper changed.
#
# The line that used to be here was also broken in a second way:
#
#     pkill qs && sleep 0.3 && qs -c bar & qs -c overview &
#
# `&` binds looser than `&&`, so that parsed as two background jobs -
# { pkill qs && sleep 0.3 && qs -c bar; } & { qs -c overview; } & - so the
# overview was relaunched without its previous instance being killed, and when
# qs was not running at all, pkill failed and the bar was never brought back.
#
# To restart the bar by hand: pkill -f 'qs -c bar'; qs -c bar &

# some process to kill
for pid in $(pidof rofi ags swaybg); do
  kill -SIGUSR1 "$pid"
  sleep 0.1
done

sleep 0.1

# reload mako
sleep 0.3
killall -SIGUSR1 dunst >/dev/null 2>&1

# Relaunching rainbow borders if the script exists
sleep 1
if file_exists "${UserScripts}/RainbowBorders.sh"; then
  ${UserScripts}/RainbowBorders.sh &
fi

exit 0
