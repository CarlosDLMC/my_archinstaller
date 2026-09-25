#!/bin/bash
# Install ly display manager

ly_package=(
  ly
)

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
# Determine the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Change the working directory to the parent directory of the script
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || exit 1

source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"

# Set the name of the log file to include the current date and time
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_ly.log"

# Installation of main components
printf "${NOTE} Installing ly display manager...\n"

for PKG1 in "${ly_package[@]}"; do
  install_package "$PKG1" "$LOG"
done

# install_package records a failure in the manifest but returns 0, so the old
# PIPESTATUS test here could never fire. Check the package itself: without ly
# there is nothing to enable, and disabling the other display managers would
# leave the machine with no login screen at all.
for PKG1 in "${ly_package[@]}"; do
  if ! pacman -Qi "$PKG1" &>/dev/null; then
    echo "${ERROR} $PKG1 did not install - leaving the display managers alone. Check $LOG" | tee -a "$LOG"
    exit 1
  fi
done

printf "${NOTE} Disabling other display managers if they exist...\n"

# Check for other login managers and disable them. Keep in step with the
# services list in install.sh. "ly" is the legacy non-template ly.service: left
# enabled, it and ly@tty2 fight over the console.
for login_manager in lightdm gdm3 gdm lxdm sddm greetd lemurs plasmalogin cosmic-greeter ly; do
  if systemctl is-enabled "$login_manager" 2>/dev/null | grep -q enabled; then
    echo "Disabling $login_manager..."
    sudo systemctl disable "$login_manager" 2>&1 | tee -a "$LOG"
  fi
done

printf "${NOTE} Enabling ly display manager on tty2...\n"
sudo systemctl enable ly@tty2.service 2>&1 | tee -a "$LOG"

