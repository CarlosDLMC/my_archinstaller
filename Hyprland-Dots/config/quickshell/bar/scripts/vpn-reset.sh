#!/bin/bash
# Reset timezone and weather to local/default

echo "Resetting to local timezone and weather..."

# Get system's default timezone (usually the one you set initially)
# You may want to change this to your actual local timezone
DEFAULT_TZ="Europe/Madrid"

# Set timezone back
if command -v timedatectl &> /dev/null; then
    sudo timedatectl set-timezone "$DEFAULT_TZ"
    echo "Timezone reset to $DEFAULT_TZ"
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
