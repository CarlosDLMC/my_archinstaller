#!/bin/bash
# XDG desktop portals for mango: wlr (screen sharing and screenshots) and gtk
# (file pickers and the rest). The option kept its name, xdph, from when it
# installed xdg-desktop-portal-hyprland, so older presets still select it.
# mangowm ships mango-portals.conf, which picks these two.

xdg=(
    xdg-desktop-portal-wlr
    xdg-desktop-portal-gtk
)

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Change the working directory to the parent directory of the script
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "[ERROR] Failed to change directory to $PARENT_DIR"; exit 1; }

# Source the global functions script
if ! source "$SCRIPT_DIR/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi


# Set the name of the log file to include the current date and time
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_xdph.log"

printf "${NOTE} Installing ${SKY_BLUE}xdg-desktop-portal-wlr${RESET} and ${SKY_BLUE}-gtk${RESET}\n"
for xdgs in "${xdg[@]}"; do
  install_package "$xdgs" "$LOG"
done
    
printf "\n%.0s" {1..2}
