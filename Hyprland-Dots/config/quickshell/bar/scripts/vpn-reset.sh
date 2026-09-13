#!/bin/bash
# Reset timezone and weather to local/default

echo "Resetting to local timezone and weather..."

# The machine's own timezone, saved by vpn-sync.sh before the first change. If it
# was never saved (reset pressed before any sync) there is nothing to restore.
DEFAULT_TZ="$(cat ~/.cache/quickshell/timezone_default 2>/dev/null || true)"

# Set timezone back
if [ -z "$DEFAULT_TZ" ]; then
    echo "No saved local timezone - leaving the clock as it is"
elif command -v timedatectl &> /dev/null; then
    if sudo -n timedatectl set-timezone "$DEFAULT_TZ" 2>/dev/null; then
        echo "Timezone reset to $DEFAULT_TZ"
    else
        echo "Error: sudo refused timedatectl (no NOPASSWD rule for this user?)"
        notify-send -u critical "VPN" "Could not reset the timezone: sudo needs a password." 2>/dev/null
        exit 1
    fi
fi

# Clear city preference (will use IP-based location)
rm -f ~/.cache/quickshell/weather_city
rm -f ~/.cache/quickshell/timezone
rm -f ~/.cache/quickshell/timezone_offset

# Create empty marker to force QuickShell refresh
mkdir -p ~/.cache/quickshell
touch ~/.cache/quickshell/timezone

# Fetch local weather (IP-based)
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
WEATHER_SCRIPT="$SCRIPT_DIR/weather-location.py"

if [ -f "$WEATHER_SCRIPT" ]; then
    python3 "$WEATHER_SCRIPT" > ~/.cache/quickshell/weather.json 2>&1
    echo "Weather reset to local location"
fi

# Notify QuickShell to refresh
touch ~/.cache/quickshell/tz_changed

echo "Reset complete!"
