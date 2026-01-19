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
# Set larger font for ly login screen with Cyrillic support
/usr/bin/setfont latarcyrheb-sun32
EOF

sudo chmod +x /etc/ly/start.sh 2>&1 | tee -a "$LOG"

# Install custom soviet language
printf "${NOTE} Installing custom soviet language...\n"
sudo cp "$PARENT_DIR/assets/ly/lang/soviet.ini" /etc/ly/lang/soviet.ini 2>&1 | tee -a "$LOG"

# Configure ly settings
printf "${NOTE} Updating ly configuration...\n"
sudo sed -i 's|^input_len = 34$|input_len = 20|' /etc/ly/config.ini 2>&1 | tee -a "$LOG"
sudo sed -i 's|^start_cmd = null$|start_cmd = /etc/ly/start.sh|' /etc/ly/config.ini 2>&1 | tee -a "$LOG"
sudo sed -i 's|^lang = en$|lang = soviet|' /etc/ly/config.ini 2>&1 | tee -a "$LOG"
sudo sed -i 's|^bigclock = none$|bigclock = en|' /etc/ly/config.ini 2>&1 | tee -a "$LOG"

printf "${OK} ly display manager configured successfully!\n"
printf "${NOTE} Features enabled:\n"
printf "  - Large font (latarcyrheb-sun32) with Cyrillic support\n"
printf "  - Custom 'soviet' language theme\n"
printf "  - Compact input box (20 characters)\n"
printf "  - Big clock display\n"

clear
