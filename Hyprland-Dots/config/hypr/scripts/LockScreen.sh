#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##

# Regenerate the per-monitor hyprlock widgets. hyprlock positions are absolute
# logical pixels, so this has to run whenever the display set may have changed
# - plugging in a projector, a new machine, a different resolution.
python3 "$HOME/.config/hypr/scripts/SovietLockGen.py" >/dev/null 2>&1

# The panel reads the bar's weather cache, which quickshell refreshes hourly,
# so this only warms the legacy ~/.cache/.weather_cache fallback for a machine
# without the bar. Detached and capped: it is a network call, measured at up to
# 3s here and able to block far longer on a dead network, and locking the
# screen must never wait on it.
( timeout 20 bash "$HOME/.config/hypr/UserScripts/WeatherWrap.sh" >/dev/null 2>&1 & ) >/dev/null 2>&1

loginctl lock-session
