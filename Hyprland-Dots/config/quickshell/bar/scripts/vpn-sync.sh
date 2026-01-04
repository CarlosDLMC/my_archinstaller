#!/bin/bash
# VPN location sync script
# Syncs timezone and weather to match VPN location

# Log file for debugging
LOG_FILE="$HOME/.cache/quickshell/vpn-sync.log"
mkdir -p "$(dirname "$LOG_FILE")"

VPN_NAME="$1"

echo "=== VPN Sync started at $(date) ===" >> "$LOG_FILE"
echo "VPN_NAME: $VPN_NAME" >> "$LOG_FILE"

if [ -z "$VPN_NAME" ]; then
    echo "Error: No VPN name provided" >> "$LOG_FILE"
    echo "Usage: vpn-sync.sh <vpn-name>"
    exit 1
fi

# VPN mappings: vpn-name -> city:timezone:offset
declare -A VPN_MAP=(
    ["de-ber"]="berlin:Europe/Berlin:+01:00"
    ["pl-waw"]="warsaw:Europe/Warsaw:+01:00"
    ["ge-tbs"]="tbilisi:Asia/Tbilisi:+04:00"
    ["es-mad"]="madrid:Europe/Madrid:+01:00"
    ["ua-iev"]="kyiv:Europe/Kiev:+02:00"
    ["lt-vno"]="vilnius:Europe/Vilnius:+02:00"
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

# Set timezone using timedatectl
if command -v timedatectl &> /dev/null; then
    sudo timedatectl set-timezone "$TIMEZONE"
    echo "Timezone set to $TIMEZONE"
else
    echo "Warning: timedatectl not found, skipping timezone change"
fi

# Save timezone and city preference for QuickShell
mkdir -p ~/.cache/quickshell
echo "$TIMEZONE" > ~/.cache/quickshell/timezone
echo "$OFFSET" > ~/.cache/quickshell/timezone_offset
echo "$CITY" > ~/.cache/quickshell/weather_city

# Fetch weather for location
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
    fi
else
    echo "Error: Weather script not found at $WEATHER_SCRIPT" >> "$LOG_FILE"
    echo "Warning: Weather script not found at $WEATHER_SCRIPT"
fi

# Notify QuickShell to refresh by touching a trigger file
touch ~/.cache/quickshell/tz_changed

echo "Sync complete at $(date)" >> "$LOG_FILE"
echo "Sync complete!"
