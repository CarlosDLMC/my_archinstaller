#!/bin/bash
# Thunar #

thunar=(
  thunar 
  thunar-volman 
  tumbler
  ffmpegthumbnailer 
  thunar-archive-plugin
  xarchiver
)

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
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_thunar.log"

# Thunar
printf "${INFO} Installing ${SKY_BLUE}Thunar${RESET} Packages...\n"  
  for THUNAR in "${thunar[@]}"; do
    install_package "$THUNAR" "$LOG"
  done

printf "\n%.0s" {1..1}

 # Check for existing configs and copy if does not exist
 #
 # Sourced from Hyprland-Dots/config/, not from assets/. assets/ used to carry a
 # second copy of Thunar/ and xfce4/ and both had drifted from the dotfiles they
 # duplicate - assets/Thunar/accels.scm and assets/xfce4/helpers.rc were each a
 # different file from the one copy.sh deploys, so which keyboard shortcuts and
 # which helper apps you ended up with depended on whether 'dots' was enabled.
 # assets/ had already lost a duplicate .zshrc to exactly this (see zsh.sh);
 # these were the last two. One copy, one source of truth.
 #
 # gtk-3.0 is in this list and never was in assets/ at all, so this arm printed
 # a copy error on every single fresh install.
for DIR1 in gtk-3.0 Thunar xfce4; do
  DIRPATH=~/.config/$DIR1
  if [ -d "$DIRPATH" ]; then
    echo -e "${NOTE} Config for ${MAGENTA}$DIR1${RESET} found, no need to copy." 2>&1 | tee -a "$LOG"
  else
    echo -e "${NOTE} Config for ${YELLOW}$DIR1${RESET} not found, copying from the dotfiles." 2>&1 | tee -a "$LOG"
    cp -r "Hyprland-Dots/config/$DIR1" ~/.config/ && echo "${OK} Copy $DIR1 completed!" || echo "${ERROR} Failed to copy $DIR1 config files." 2>&1 | tee -a "$LOG"
  fi
done

# Enable avahi-daemon for NAS/SMB network discovery
printf "\n${INFO} Enabling ${SKY_BLUE}avahi-daemon${RESET} for NAS/SMB discovery...\n" | tee -a "$LOG"
sudo systemctl enable --now avahi-daemon.service 2>&1 | tee -a "$LOG"
if systemctl is-active --quiet avahi-daemon.service; then
  echo "${OK} avahi-daemon is running." | tee -a "$LOG"
else
  echo "${WARN} avahi-daemon failed to start. Network discovery may not work." | tee -a "$LOG"
fi

printf "\n%.0s" {1..2}