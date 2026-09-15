#!/bin/bash
# VPN location sync script
# Points the clock and/or the weather at the VPN's exit node.
#
# Usage: vpn-sync.sh <vpn-name> [time|weather|all]
#
# The two halves are separately callable because the bar's VPN card has a button
# for each, and they are not remotely the same size of change. Moving the weather
# rewrites one string in ~/.cache; moving the clock runs `timedatectl
# set-timezone`, which moves the system clock for every process on the machine -
# journal timestamps, file mtimes, every other app - and needs sudo to do it.
# Wanting the weather to follow the tunnel while the clock stays where you are is
# the normal case, so it is two buttons rather than one.
#
# `all` is the default and is what the single sync button used to do.

# Log file for debugging
LOG_FILE="$HOME/.cache/quickshell/vpn-sync.log"
mkdir -p "$(dirname "$LOG_FILE")"

VPN_NAME="$1"
MODE="${2:-all}"

echo "=== VPN Sync started at $(date) ===" >> "$LOG_FILE"
echo "VPN_NAME: $VPN_NAME" >> "$LOG_FILE"
echo "MODE: $MODE" >> "$LOG_FILE"

if [ -z "$VPN_NAME" ]; then
    echo "Error: No VPN name provided" >> "$LOG_FILE"
    echo "Usage: vpn-sync.sh <vpn-name> [time|weather|all]"
    exit 1
fi

SYNC_TIME=0
SYNC_WEATHER=0
case "$MODE" in
    time)    SYNC_TIME=1 ;;
    weather) SYNC_WEATHER=1 ;;
    all)     SYNC_TIME=1; SYNC_WEATHER=1 ;;
    *)
        echo "Error: Unknown mode: $MODE" >> "$LOG_FILE"
        echo "Usage: vpn-sync.sh <vpn-name> [time|weather|all]"
        exit 1
        ;;
esac

# VPN mappings: vpn-name -> city:timezone:offset
declare -A VPN_MAP=(
    ["de-ber"]="berlin:Europe/Berlin:+01:00"
    ["pl-waw"]="warsaw:Europe/Warsaw:+01:00"
    ["ge-tbs"]="tbilisi:Asia/Tbilisi:+04:00"
    ["es-mad"]="madrid:Europe/Madrid:+01:00"
    ["ua-iev"]="kyiv:Europe/Kiev:+02:00"
    ["lt-vno"]="vilnius:Europe/Vilnius:+02:00"
    ["id-jak"]="jakarta:Asia/Jakarta:+07:00"
)

# Get mapping for this VPN
MAPPING="${VPN_MAP[$VPN_NAME]}"
echo "Mapping: $MAPPING" >> "$LOG_FILE"

if [ -z "$MAPPING" ]; then
    echo "Error: Unknown VPN: $VPN_NAME" >> "$LOG_FILE"
    echo "Unknown VPN: $VPN_NAME"
    exit 1
fi

# Split into city, timezone, and offset
CITY=$(echo "$MAPPING" | cut -d: -f1)
TIMEZONE=$(echo "$MAPPING" | cut -d: -f2)
OFFSET=$(echo "$MAPPING" | cut -d: -f3-)

echo "CITY: $CITY" >> "$LOG_FILE"
echo "TIMEZONE: $TIMEZONE" >> "$LOG_FILE"
echo "OFFSET: $OFFSET" >> "$LOG_FILE"

echo "Syncing to $CITY ($TIMEZONE, UTC$OFFSET)..."

mkdir -p ~/.cache/quickshell
FAILED=0

# ---- clock ---------------------------------------------------------------
# System-wide, and the reason this half has its own button.
if [ "$SYNC_TIME" -eq 1 ]; then
    # Remember the machine's own timezone the first time we move away from it, so
    # vpn-reset.sh can restore THAT rather than a hardcoded city.
    if [ ! -s ~/.cache/quickshell/timezone_default ]; then
        timedatectl show -p Timezone --value 2>/dev/null > ~/.cache/quickshell/timezone_default || true
    fi

    # Set timezone using timedatectl. This runs from a QML Process with no tty, so
    # `sudo -n`: fail now rather than hang on a password prompt, and do not write
    # the caches below if the clock did not actually move (the bar would show a
    # city time the system does not have).
    if command -v timedatectl &> /dev/null; then
        if sudo -n timedatectl set-timezone "$TIMEZONE" 2>>"$LOG_FILE"; then
            echo "$TIMEZONE" > ~/.cache/quickshell/timezone
            echo "$OFFSET" > ~/.cache/quickshell/timezone_offset
            echo "Timezone set to $TIMEZONE"
        else
            echo "Error: sudo refused timedatectl (no NOPASSWD rule for this user?)" | tee -a "$LOG_FILE"
            notify-send -u critical "VPN" "Could not change the timezone: sudo needs a password. See README 'VPN configs'." 2>/dev/null
            FAILED=1
        fi
    else
        echo "Warning: timedatectl not found, skipping timezone change"
    fi
fi

# ---- weather -------------------------------------------------------------
# One string in a cache file, which weather-fetch.sh then passes to the lookup.
if [ "$SYNC_WEATHER" -eq 1 ]; then
    echo "$CITY" > ~/.cache/quickshell/weather_city

    SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
    WEATHER_SCRIPT="$SCRIPT_DIR/weather-location.py"

    echo "Weather script: $WEATHER_SCRIPT" >> "$LOG_FILE"
    echo "Running: python3 $WEATHER_SCRIPT $CITY" >> "$LOG_FILE"

    if [ -f "$WEATHER_SCRIPT" ]; then
        WEATHER_OUTPUT=$(python3 "$WEATHER_SCRIPT" "$CITY" 2>&1)
        WEATHER_EXIT=$?
        echo "Weather script exit code: $WEATHER_EXIT" >> "$LOG_FILE"
        echo "Weather output: $WEATHER_OUTPUT" >> "$LOG_FILE"

        if [ $WEATHER_EXIT -eq 0 ]; then
            echo "$WEATHER_OUTPUT" > ~/.cache/quickshell/weather.json
            echo "Weather cache written successfully" >> "$LOG_FILE"
            echo "Weather updated for $CITY"
        else
            echo "Error: Weather script failed" >> "$LOG_FILE"
            echo "Warning: Weather update failed for $CITY"
            FAILED=1
        fi
    else
        echo "Error: Weather script not found at $WEATHER_SCRIPT" >> "$LOG_FILE"
        echo "Warning: Weather script not found at $WEATHER_SCRIPT"
        FAILED=1
    fi
fi

# Notify QuickShell to refresh by touching a trigger file
touch ~/.cache/quickshell/tz_changed

echo "Sync complete at $(date)" >> "$LOG_FILE"
echo "Sync complete!"
exit $FAILED
