#!/bin/bash
# mango (mangowm) - the compositor - and the Hypr tools this setup keeps on it:
# hyprlock (the lock screen) and hypridle (idle and sleep), which are not tied
# to Hyprland.

mango_pkg=(
  mangowm
)

hypr_eco=(
  hypridle
  hyprlock
)

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Change the working directory to the parent directory of the script
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "[ERROR] Failed to change directory to $PARENT_DIR"; exit 1; }

# Source the global functions script
if ! source "$SCRIPT_DIR/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

# Set the name of the log file to include the current date and time
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_mango.log"

if pacman -Q mangowm >/dev/null 2>&1 || pacman -Q mangowm-git >/dev/null 2>&1; then
  printf "$NOTE - ${YELLOW} mango is already installed.${RESET} No action required.\n"
else
  printf "$INFO - mango not found. ${SKY_BLUE} Installing mango...${RESET}\n"
  for MANGO in "${mango_pkg[@]}"; do
    install_package "$MANGO" "$LOG"
  done
fi

# CachyOS's Mango editions install mangowm as a dependency of their own
# settings package, which 01-hypr-pkgs.sh removes: without this, the next
# orphan clean-up (pacman -Qtdq) would take the compositor with it.
if pacman -Qq mangowm >/dev/null 2>&1; then
  sudo pacman -D --asexplicit mangowm >>"$LOG" 2>&1
fi

printf "${NOTE} - Installing ${SKY_BLUE}hypridle and hyprlock${RESET} .......\n"
for HYPR in "${hypr_eco[@]}"; do
  if ! command -v "$HYPR" >/dev/null 2>&1; then
    printf "$INFO - ${YELLOW}$HYPR${RESET} not found. Installing ${YELLOW}$HYPR...${RESET}\n"
    install_package "$HYPR" "$LOG"
  else
    printf "$NOTE - ${YELLOW} $HYPR is already installed.${RESET} No action required.\n"
  fi
done

printf "\n%.0s" {1..2}
