#!/bin/bash
# Send the clock and/or the weather back home.
#
# Usage: vpn-reset.sh [time|weather|all]
#
# `all` is the default, which is what the disconnect button, the dropped-tunnel
# handler and the stale-cache check at startup all want. The bar's two toggle
# buttons call the halves individually, so either can come home while the tunnel
# stays up.
#
# "Home" is whatever was saved the first time that half left it - see vpn-sync.sh.
# Nothing is saved until then, so a machine that has never followed a tunnel has
# no home files at all, and this degrades to what it always did: leave the clock
# alone and let the weather fall back to IP.

MODE="${1:-all}"

RESET_TIME=0
RESET_WEATHER=0
case "$MODE" in
    time)    RESET_TIME=1 ;;
    weather) RESET_WEATHER=1 ;;
    all)     RESET_TIME=1; RESET_WEATHER=1 ;;
    *)
        echo "Usage: vpn-reset.sh [time|weather|all]"
        exit 1
        ;;
esac

echo "Returning to local ($MODE)..."

mkdir -p ~/.cache/quickshell
FAILED=0

# ---- clock ---------------------------------------------------------------
if [ "$RESET_TIME" -eq 1 ]; then
    # The machine's own timezone, saved by vpn-sync.sh before the first change. If
    # it was never saved (reset pressed before any sync) there is nothing to restore.
    DEFAULT_TZ="$(cat ~/.cache/quickshell/timezone_default 2>/dev/null || true)"

    if [ -z "$DEFAULT_TZ" ]; then
        echo "No saved local timezone - leaving the clock as it is"
    elif command -v timedatectl &> /dev/null; then
        if sudo -n timedatectl set-timezone "$DEFAULT_TZ" 2>/dev/null; then
            echo "Timezone reset to $DEFAULT_TZ"
        else
            echo "Error: sudo refused timedatectl (no NOPASSWD rule for this user?)"
            notify-send -u critical "VPN" "Could not reset the timezone: sudo needs a password." 2>/dev/null
            FAILED=1
        fi
    fi

    # Clear the override the bar's clock reads. An empty file rather than no file:
    # CenterInfo watches this path, and a delete followed by a create is two
    # events where a truncate is one.
    if [ "$FAILED" -eq 0 ]; then
        rm -f ~/.cache/quickshell/timezone_offset
        : > ~/.cache/quickshell/timezone
    fi
fi

# ---- weather -------------------------------------------------------------
if [ "$RESET_WEATHER" -eq 1 ]; then
    # Dropping the city preference is the whole reset: weather-fetch.sh then picks
    # home coordinates while a tunnel is up, or asks by IP when there is none.
    #
    # weather_home is deliberately NOT deleted. It is the only thing that can
    # answer "my own weather" while still connected, which is exactly the state
    # this button exists for.
    rm -f ~/.cache/quickshell/weather_city

    SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
    FETCH="$SCRIPT_DIR/weather-fetch.sh"

    if [ -x "$FETCH" ]; then
        WEATHER_OUTPUT=$("$FETCH" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$WEATHER_OUTPUT" ]; then
            echo "$WEATHER_OUTPUT" > ~/.cache/quickshell/weather.json
            echo "Weather reset to home"
        else
            echo "Warning: could not fetch home weather"
            FAILED=1
        fi
    else
        echo "Error: weather-fetch.sh not found at $FETCH"
        FAILED=1
    fi
fi

# Notify QuickShell to refresh
touch ~/.cache/quickshell/tz_changed

echo "Reset complete!"
exit $FAILED
