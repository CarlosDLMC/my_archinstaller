#!/bin/bash
# Configure ly display manager

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
# Determine the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Change the working directory to the parent directory of the script
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || exit 1

source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"

# Set the name of the log file to include the current date and time
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_ly_config.log"

printf "${NOTE} Configuring ly display manager...\n"

# Copy ly configuration files
printf "${NOTE} Installing ly configuration...\n"
# `install`, checked: config.ini points ly at every one of these files, so a
# missing one used to give a login screen with no flag, no language and an OK.
ly_install() { # mode src dst
  if ! sudo install -D -m "$1" "$2" "$3" 2>&1 | tee -a "$LOG"; then :; fi
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then echo "${ERROR} Failed to install $3" | tee -a "$LOG"; exit 1; fi
}
ly_install 644 "$PARENT_DIR/assets/ly/config.ini" /etc/ly/config.ini

printf "${NOTE} Installing ly start script...\n"
ly_install 755 "$PARENT_DIR/assets/ly/start.sh" /etc/ly/start.sh

printf "${NOTE} Installing 8-bit soviet flag animation...\n"
# config.ini sets animation = dur_file and points dur_file_path here, so the
# flag has to land in /etc/ly or ly draws nothing at all. Both the waving and
# the still version are installed, so switching is a one-line config edit
# rather than a re-run of this script.
ly_install 644 "$PARENT_DIR/assets/ly/soviet-flag-animated.dur" /etc/ly/soviet-flag-animated.dur
ly_install 644 "$PARENT_DIR/assets/ly/soviet-flag-static.dur" /etc/ly/soviet-flag-static.dur

printf "${NOTE} Installing custom soviet language...\n"
ly_install 644 "$PARENT_DIR/assets/ly/lang/soviet.ini" /etc/ly/lang/soviet.ini

printf "${OK} ly display manager configured successfully!\n"

