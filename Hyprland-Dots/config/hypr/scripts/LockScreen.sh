#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##

# Regenerate the per-monitor hyprlock widgets. hyprlock positions are absolute
# logical pixels, so this has to run whenever the display set may have changed
# - plugging in a projector, a new machine, a different resolution.
python3 "$HOME/.config/hypr/scripts/SovietLockGen.py" >/dev/null 2>&1

# Ensure weather cache is up-to-date before locking (Quickshell/lockscreen readers)
bash "$HOME/.config/hypr/UserScripts/WeatherWrap.sh" >/dev/null 2>&1

loginctl lock-session
