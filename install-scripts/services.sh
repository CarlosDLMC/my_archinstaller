#!/bin/bash
# 💫 https://github.com/JaKooLit 💫 #
# Enable essential systemd services #

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Change the working directory to the parent directory of the script
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "${ERROR} Failed to change directory to $PARENT_DIR"; exit 1; }

# Source the global functions script
if ! source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

# Set the name of the log file to include the current date and time
LOG="Install-Logs/install-$(date +%d-%H%M%S)_services.log"

printf "\n${INFO} Enabling essential ${SKY_BLUE}system services${RESET}...\n" | tee -a "$LOG"

# Enable NetworkManager
printf "\n${NOTE} Enabling ${SKY_BLUE}NetworkManager${RESET}...\n" | tee -a "$LOG"
sudo systemctl enable --now NetworkManager.service 2>&1 | tee -a "$LOG"
if systemctl is-active --quiet NetworkManager.service; then
  echo "${OK} NetworkManager is running." | tee -a "$LOG"
else
  echo "${WARN} NetworkManager failed to start. Network connectivity may not work." | tee -a "$LOG"
fi

# Enable power-profiles-daemon
printf "\n${NOTE} Enabling ${SKY_BLUE}power-profiles-daemon${RESET}...\n" | tee -a "$LOG"
sudo systemctl enable --now power-profiles-daemon.service 2>&1 | tee -a "$LOG"
if systemctl is-active --quiet power-profiles-daemon.service; then
  echo "${OK} power-profiles-daemon is running." | tee -a "$LOG"
else
  echo "${WARN} power-profiles-daemon failed to start. Power profile management may not work." | tee -a "$LOG"
fi

printf "\n%.0s" {1..2}
