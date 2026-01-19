#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
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

# quit quickshell & relaunch quickshell
pkill qs && sleep 0.3 && qs -c bar & qs -c overview &

# some process to kill
for pid in $(pidof rofi ags swaybg); do
  kill -SIGUSR1 "$pid"
  sleep 0.1
done

sleep 0.1

# reload mako
sleep 0.3
makoctl reload >/dev/null 2>&1

# Relaunching rainbow borders if the script exists
sleep 1
if file_exists "${UserScripts}/RainbowBorders.sh"; then
  ${UserScripts}/RainbowBorders.sh &
fi

exit 0
