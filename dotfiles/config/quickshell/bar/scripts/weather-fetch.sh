#!/bin/bash
# Weather entry point. Decides *which* location the bar asks about.
#
# Precedence, and the reason for each step:
#
#   1. weather_city   - set by vpn-sync.sh. Its presence is what "the weather is
#                       following the tunnel" means, everywhere in the bar.
#   2. weather_home   - only consulted while a tunnel is up. This is the case IP
#                       geolocation cannot answer: you are connected but you want
#                       your own weather, and your IP is the exit node. Home
#                       travels as coordinates because it can be anywhere, while
#                       a bare city name only resolves for the seven in
#                       VPN_LOCATIONS.
#   3. IP             - no tunnel, no preference: ask where we actually are. This
#                       is also what keeps things honest if you move house, since
#                       it is consulted fresh every time.

CITY_FILE="$HOME/.cache/quickshell/weather_city"
HOME_FILE="$HOME/.cache/quickshell/weather_home"
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

# No city preference. If a tunnel is up, IP geolocation would answer with the
# exit node, so prefer the home coordinates saved before the first departure.
if [ -n "$(wg show interfaces 2>/dev/null)" ] && [ -s "$HOME_FILE" ]; then
    IFS=$'\t' read -r HOME_LAT HOME_LON HOME_NAME < "$HOME_FILE"
    if [ -n "$HOME_LAT" ] && [ -n "$HOME_LON" ]; then
        echo "Fetching weather for home: $HOME_NAME ($HOME_LAT,$HOME_LON)" >&2
        python3 "$WEATHER_SCRIPT" "$HOME_LAT,$HOME_LON" "$HOME_NAME"
        exit $?
    fi
fi

# No city preference, use IP-based
echo "Fetching weather using IP location" >&2
python3 "$WEATHER_SCRIPT"
