#!/bin/bash
# Asus ROG Laptops #

rog=(
    # power-profiles-daemon: see power_profiles.sh, which owns it and skips
    # it when something (tuned-cachy-ppd on CachyOS) already provides the API.
    asusctl
    rog-control-center
)

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Change the working directory to the parent directory of the script
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "[ERROR] Failed to change directory to $PARENT_DIR"; exit 1; }

# Source the global functions script
if ! source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi



# Set the name of the log file to include the current date and time
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_rog.log"

### Install software for Asus ROG laptops ###

# supergfxctl only switches between an integrated and a discrete GPU. install.sh
# treats any ASUS laptop as ROG hardware, and Zenbooks and Vivobooks are mostly
# Intel-only - they got an enabled supergfxd for a switch they do not have.
# Two or more display controllers (PCI class 03xx) is the hybrid case.
gpu_count=$(lspci -n 2>/dev/null | awk '$2 ~ /^03/' | wc -l)
if [ "$gpu_count" -ge 2 ]; then
  rog+=(supergfxctl)
else
  echo "${NOTE} Single GPU - skipping supergfxctl (it only switches iGPU/dGPU)." | tee -a "$LOG"
fi

printf " Installing ${SKY_BLUE}ASUS ROG packages${RESET}...\n"
for ASUS in "${rog[@]}"; do
install_package  "$ASUS" "$LOG"
done

printf " Activating ROG services...\n"
# asusd is the daemon asusctl, rog-control-center and the keyboard/fan controls
# talk to; the package does not enable it, so without this line the tools
# install and then fail with "asusd not running" after reboot.
#
# One unit per call. `systemctl enable asusd supergfxd` fails as a whole when
# either unit is missing - supergfxctl is an AUR build, and when it failed,
# asusd was left disabled too, with the error hidden behind `| tee`.
for _unit in asusd supergfxd; do
  if systemctl list-unit-files "$_unit.service" 2>/dev/null | grep -q "^$_unit\.service"; then
    if sudo systemctl enable "$_unit.service" >> "$LOG" 2>&1; then
      echo "${OK} $_unit.service enabled" | tee -a "$LOG"
    else
      echo "${ERROR} Could not enable $_unit.service - see $LOG" | tee -a "$LOG"
    fi
  elif [ "$_unit" = asusd ] || [ "$gpu_count" -ge 2 ]; then
    echo "${WARN} $_unit.service does not exist - its package did not install." | tee -a "$LOG"
  fi
done

printf "\n%.0s" {1..2}