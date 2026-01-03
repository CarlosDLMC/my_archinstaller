#!/bin/bash
# 💫 https://github.com/JaKooLit 💫 #
# Hyprland-Dots to download from main #


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

# Install customized Hyprland-Dots from local directory
printf "${NOTE} Installing ${SKY_BLUE}Customized Hyprland Dots${RESET}....\n"

if [ -d Hyprland-Dots ]; then
  cd Hyprland-Dots || exit 1

  # Check if copy.sh exists
  if [ -f copy.sh ]; then
    chmod +x copy.sh
    ./copy.sh
    echo -e "${OK} Customized dotfiles installed successfully!"
  else
    echo -e "${ERROR} copy.sh not found in Hyprland-Dots directory"
    exit 1
  fi
else
  echo -e "${ERROR} Hyprland-Dots directory not found. Cannot install dotfiles."
  echo -e "${NOTE} Please ensure the Hyprland-Dots folder exists in the installation directory."
  exit 1
fi

printf "\n%.0s" {1..2}