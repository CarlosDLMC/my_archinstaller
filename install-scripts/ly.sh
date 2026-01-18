#!/bin/bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  #
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
LOG="Install-Logs/install-$(date +%d-%H%M%S)_ly.log"

# Installation of main components
printf "${NOTE} Installing ly display manager...\n"

for PKG1 in "${ly_package[@]}"; do
  install_package "$PKG1" 2>&1 | tee -a "$LOG"
  if [ $? -ne 0 ]; then
    echo -e "\e[1A\e[K${ERROR} - $PKG1 Package installation failed, Please check the installation logs"
    exit 1
  fi
done

printf "${NOTE} Disabling other display managers if they exist...\n"

# Check for other login managers and disable them
for login_manager in lightdm gdm3 gdm lxdm sddm; do
  if systemctl is-enabled "$login_manager" 2>/dev/null | grep -q enabled; then
    echo "Disabling $login_manager..."
    sudo systemctl disable "$login_manager" 2>&1 | tee -a "$LOG"
  fi
done

printf "${NOTE} Enabling ly display manager on tty2...\n"
sudo systemctl enable ly@tty2.service 2>&1 | tee -a "$LOG"

clear
