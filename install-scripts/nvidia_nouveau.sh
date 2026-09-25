#!/bin/bash
# Nvidia Blacklist #

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Change the working directory to the parent directory of the script
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "[ERROR] Failed to change directory to $PARENT_DIR"; exit 1; }

# Source the global functions script
if ! source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi



# Set the name of the log file to include the current date and time
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_nvidia.log"

printf "${INFO} ${SKY_BLUE}blacklist nouveau${RESET}...\n"
# Blacklist nouveau
NOUVEAU="/etc/modprobe.d/nouveau.conf"
if [ -f "$NOUVEAU" ]; then
  printf "${OK} Seems like ${YELLOW}nouveau${RESET} is already blacklisted..moving on.\n"
else
  echo "blacklist nouveau" | sudo tee -a "$NOUVEAU" 2>&1 | tee -a "$LOG"

  # To completely blacklist nouveau (See wiki.archlinux.org/title/Kernel_module#Blacklisting 6.1)
  if [ -f "/etc/modprobe.d/blacklist.conf" ]; then
    echo "install nouveau /bin/true" | sudo tee -a "/etc/modprobe.d/blacklist.conf" 2>&1 | tee -a "$LOG"
  else
    echo "install nouveau /bin/true" | sudo tee "/etc/modprobe.d/blacklist.conf" 2>&1 | tee -a "$LOG"
  fi
fi

# Rebuild AFTER the blacklist is on disk. The default `kms` hook puts nouveau in
# the initramfs and `modconf` copies /etc/modprobe.d into it, so a blacklist
# written after the last rebuild is not in the image that actually boots.
# nvidia.sh leaves the rebuild to this script when nouveau is selected, so this
# one image carries the NVIDIA modules, their options and the blacklist.
rebuild_initramfs "$LOG" || true

printf "\n%.0s" {1..2}
