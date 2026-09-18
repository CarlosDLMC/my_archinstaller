#!/bin/bash
# Send the clock and/or the weather back home.
#
# Usage: vpn-reset.sh [time|weather|all] [--forget]
#
# `all` is the default, which is what the disconnect button, the dropped-tunnel
# handler and the stale-cache check at startup all want. The bar's two toggle
# buttons call the halves individually, so either can come home while the tunnel
# stays up.
#
# --forget additionally drops the saved home location and timezone, so the next
# departure captures them fresh. It is passed by the paths that end with **no tunnel**
# - disconnect, a dropped tunnel, the stale-cache check - where the saved copy
# has nothing left to do: with no tunnel, an IP lookup is a better answer than a
# remembered one, and it is the only one that notices you have moved.
#
# It is deliberately NOT inferred from whether a tunnel is up right now. The
# disconnect button starts `wg-quick down` and this script in the same moment,
# so the tunnel is usually still up when we get here, and a rule that read the
# live state would forget almost nothing. It is also exactly the wrong thing to
# do on the toggle path, where coming home *while connected* is the entire
# point and the saved home is the only thing that can answer it.
#
# "Home" is whatever was saved the first time that half left it - see vpn-sync.sh.
# Nothing is saved until then, so a machine that has never followed a tunnel has
# no home files at all, and this degrades to what it always did: leave the clock
# alone and let the weather fall back to IP.

MODE="all"
FORGET=0
for arg in "$@"; do
    case "$arg" in
        --forget)         FORGET=1 ;;
        time|weather|all) MODE="$arg" ;;
        *)
            echo "Usage: vpn-reset.sh [time|weather|all] [--forget]"
            exit 1
            ;;
    esac
done

RESET_TIME=0
RESET_WEATHER=0
case "$MODE" in
    time)    RESET_TIME=1 ;;
    weather) RESET_WEATHER=1 ;;
    all)     RESET_TIME=1; RESET_WEATHER=1 ;;
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

        # After the restore, never before. Same rule as weather_home: with no
        # tunnel the saved copy has nothing left to do, and re-capturing it on
        # the next departure is what stops a stale one surviving a move. It also
        # means a wrong one - captured while the clock was already following a
        # tunnel - heals itself rather than persisting forever.
        if [ "$FORGET" -eq 1 ]; then
            rm -f ~/.cache/quickshell/timezone_default
            echo "Forgot the saved home timezone - the next sync will capture it again"
        fi
    fi
fi

# ---- weather -------------------------------------------------------------
if [ "$RESET_WEATHER" -eq 1 ]; then
    # Dropping the city preference is the whole reset: weather-fetch.sh then picks
    # home coordinates while a tunnel is up, or asks by IP when there is none.
    #
    # weather_home survives this unless --forget says otherwise: without it the
    # toggle could not answer "my own weather" while still connected, which is
    # the state that button exists for.
    rm -f ~/.cache/quickshell/weather_city

    SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
    FETCH="$SCRIPT_DIR/weather-fetch.sh"

    if [ -x "$FETCH" ]; then
        # Same rule as vpn-sync.sh: weather-location.py owns the cache file and
        # writes it only on a fresh reading, so this just runs the fetch and
        # reports. Exit 2 means every provider refused and the bar is still
        # showing the last good reading - which is the right thing for it to
        # show, but not something to call a successful reset.
        "$FETCH" >/dev/null 2>/dev/null
        FETCH_EXIT=$?
        case "$FETCH_EXIT" in
            0) echo "Weather reset to home" ;;
            2)
                echo "Warning: no weather provider answered - still showing the previous reading"
                FAILED=1
                ;;
            *)
                echo "Warning: could not fetch home weather"
                FAILED=1
                ;;
        esac
    else
        echo "Error: weather-fetch.sh not found at $FETCH"
        FAILED=1
    fi

    # After the fetch, never before: the tunnel may still be on its way down, in
    # which case that fetch was the last thing that needed these coordinates.
    if [ "$FORGET" -eq 1 ]; then
        rm -f ~/.cache/quickshell/weather_home
        echo "Forgot the saved home location - the next sync will capture it again"
    fi
fi

# Notify QuickShell to refresh
touch ~/.cache/quickshell/tz_changed

echo "Reset complete!"
exit $FAILED
