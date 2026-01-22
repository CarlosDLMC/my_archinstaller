#!/bin/bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  #
# Configure ly display manager

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
# Determine the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Change the working directory to the parent directory of the script
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || exit 1

source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"

# Set the name of the log file to include the current date and time
LOG="Install-Logs/install-$(date +%d-%H%M%S)_ly_config.log"

printf "${NOTE} Configuring ly display manager...\n"

# Copy ly configuration files
printf "${NOTE} Installing ly configuration...\n"
sudo cp "$PARENT_DIR/assets/ly/config.ini" /etc/ly/config.ini 2>&1 | tee -a "$LOG"

printf "${NOTE} Installing ly start script...\n"
sudo cp "$PARENT_DIR/assets/ly/start.sh" /etc/ly/start.sh 2>&1 | tee -a "$LOG"
sudo chmod +x /etc/ly/start.sh 2>&1 | tee -a "$LOG"

printf "${NOTE} Installing custom soviet language...\n"
sudo cp "$PARENT_DIR/assets/ly/lang/soviet.ini" /etc/ly/lang/soviet.ini 2>&1 | tee -a "$LOG"

printf "${OK} ly display manager configured successfully!\n"

clear
