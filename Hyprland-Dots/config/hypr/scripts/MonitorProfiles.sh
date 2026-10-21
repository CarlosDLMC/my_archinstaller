#!/usr/bin/env bash
# For applying Pre-configured Monitor Profiles

# Check if rofi is already running
if pidof rofi > /dev/null; then
  pkill rofi
fi

# Variables
iDIR="$HOME/.config/hypr/notify/images"
SCRIPTSDIR="$HOME/.config/hypr/scripts"
monitor_dir="$HOME/.config/mango/Monitor_Profiles"
target="$HOME/.config/mango/monitors.conf"
rofi_theme="$HOME/.config/rofi/config-Monitors.rasi"
msg='Внимание: будет перезаписан $HOME/.config/mango/monitors.conf'

# Define the list of files to ignore
ignore_files=(
  "README"
)

# list of Monitor Profiles, sorted alphabetically with numbers first
mon_profiles_list=$(find -L "$monitor_dir" -maxdepth 1 -type f -name '*.conf' | sed 's/.*\///' | sed 's/\.conf$//' | sort -V)

# Remove ignored files from the list
for ignored_file in "${ignore_files[@]}"; do
    mon_profiles_list=$(echo "$mon_profiles_list" | grep -v -E "^$ignored_file$")
done

# Rofi Menu
chosen_file=$(echo "$mon_profiles_list" | rofi -i -dmenu -config $rofi_theme -mesg "$msg")

if [[ -n "$chosen_file" ]]; then
    # mango reloads its config when the file changes.
    cp "$monitor_dir/$chosen_file.conf" "$target"
    
    notify-send -t 1000 -u low -i "$iDIR/ja.png" "Профиль мониторов загружен:" "$chosen_file"
fi

sleep 1
${SCRIPTSDIR}/RefreshColors.sh &