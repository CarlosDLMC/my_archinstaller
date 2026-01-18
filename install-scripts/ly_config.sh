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

# Create ly start script to set larger font
printf "${NOTE} Creating ly font configuration script...\n"
sudo tee /etc/ly/start.sh > /dev/null <<'EOF'
#!/bin/sh
# Set larger font for ly login screen
/usr/bin/setfont solar24x32
EOF

sudo chmod +x /etc/ly/start.sh 2>&1 | tee -a "$LOG"

# Configure ly settings
printf "${NOTE} Updating ly configuration...\n"
sudo sed -i 's|^input_len = 34$|input_len = 50|' /etc/ly/config.ini 2>&1 | tee -a "$LOG"
sudo sed -i 's|^start_cmd = null$|start_cmd = /etc/ly/start.sh|' /etc/ly/config.ini 2>&1 | tee -a "$LOG"

printf "${OK} ly display manager configured successfully!\n"
printf "${NOTE} Features enabled:\n"
printf "  - Large font (solar24x32) for better visibility\n"
printf "  - Extended input box length (50 characters)\n"

clear
