#!/bin/bash
# Weather fetch wrapper that reads city preference

CITY_FILE="$HOME/.cache/quickshell/weather_city"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
WEATHER_SCRIPT="$SCRIPT_DIR/weather-location.py"

# Read city preference if it exists
if [ -f "$CITY_FILE" ] && [ -s "$CITY_FILE" ]; then
    CITY=$(cat "$CITY_FILE" | tr -d '\n')
    if [ -n "$CITY" ]; then
        echo "Fetching weather for: $CITY" >&2
        python3 "$WEATHER_SCRIPT" "$CITY"
        exit $?
    fi
fi

# No city preference, use IP-based
echo "Fetching weather using IP location" >&2
python3 "$WEATHER_SCRIPT"
