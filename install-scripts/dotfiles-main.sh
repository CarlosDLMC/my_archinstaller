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

# Debug: Show current directory
printf "${INFO} Current directory: $(pwd)\n"
printf "${INFO} Looking for Hyprland-Dots in: $(pwd)/Hyprland-Dots\n"

if [ -d Hyprland-Dots ]; then
  printf "${OK} Found Hyprland-Dots directory\n"
  cd Hyprland-Dots || { echo "${ERROR} Failed to cd into Hyprland-Dots"; exit 1; }

  printf "${INFO} Now in directory: $(pwd)\n"

  # Check if copy.sh exists
  if [ -f copy.sh ]; then
    printf "${OK} Found copy.sh script\n"
    chmod +x copy.sh

    printf "${NOTE} Running copy.sh script...\n"
    printf "======================================\n"
    ./copy.sh 2>&1 | tee -a "$PARENT_DIR/Install-Logs/dotfiles-copy-$(date +%d-%H%M%S).log"

    if [ ${PIPESTATUS[0]} -eq 0 ]; then
      printf "======================================\n"
      echo -e "${OK} Customized dotfiles installed successfully!"
    else
      echo -e "${ERROR} copy.sh script failed with exit code ${PIPESTATUS[0]}"
      exit 1
    fi
  else
    echo -e "${ERROR} copy.sh not found in Hyprland-Dots directory"
    printf "${INFO} Contents of Hyprland-Dots:\n"
    ls -la
    exit 1
  fi
else
  echo -e "${ERROR} Hyprland-Dots directory not found. Cannot install dotfiles."
  echo -e "${NOTE} Please ensure the Hyprland-Dots folder exists in the installation directory."
  printf "${INFO} Current directory contents:\n"
  ls -la
  printf "${INFO} Expected location: $(pwd)/Hyprland-Dots\n"
  exit 1
fi

printf "\n%.0s" {1..2}