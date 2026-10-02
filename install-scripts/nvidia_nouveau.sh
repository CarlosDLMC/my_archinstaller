#!/bin/bash
# Nvidia Blacklist #

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
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_nvidia.log"

printf "${INFO} ${SKY_BLUE}blacklist nouveau${RESET}...\n"
# Blacklist nouveau
#
# Both lines go into nouveau.conf. The `install nouveau /bin/true` line used to
# go into /etc/modprobe.d/blacklist.conf, and a file in /etc/modprobe.d REPLACES
# the one of the same name in /usr/lib/modprobe.d: on CachyOS cachyos-settings
# ships /usr/lib/modprobe.d/blacklist.conf, which blacklists the iTCO_wdt and
# sp5100_tco watchdogs, and our one-liner switched that off. Same bug as
# nvidia.sh's old /etc/modprobe.d/nvidia.conf.
NOUVEAU="/etc/modprobe.d/nouveau.conf"
NOUVEAU_LINES=("blacklist nouveau" "install nouveau /bin/true")
BL_OLD="/etc/modprobe.d/blacklist.conf"

# An earlier run left the install line in blacklist.conf: take out exactly that
# line, and the file too if nothing else is in it, so the packaged one applies
# again. Anything else in there was put there on purpose and stays.
if [ -f "$BL_OLD" ] && [ ! -L "$BL_OLD" ] && grep -qxF "install nouveau /bin/true" "$BL_OLD"; then
  if sudo sed -i '\|^install nouveau /bin/true$|d' "$BL_OLD"; then
    if ! grep -qvE '^[[:space:]]*(#|$)' "$BL_OLD"; then
      sudo rm -f "$BL_OLD"
      echo "${OK} Removed $BL_OLD from an earlier run - the nouveau line now lives in ${NOUVEAU##*/}." | tee -a "$LOG"
    else
      echo "${OK} Moved the nouveau line out of $BL_OLD (its other lines are left as they are)." | tee -a "$LOG"
      if [ -f /usr/lib/modprobe.d/blacklist.conf ]; then
        echo "${NOTE} $BL_OLD still replaces /usr/lib/modprobe.d/blacklist.conf - rename it if that is not intended." | tee -a "$LOG"
      fi
    fi
  else
    echo "${WARN} Could not edit $BL_OLD - it keeps hiding /usr/lib/modprobe.d/blacklist.conf." | tee -a "$LOG"
  fi
fi

# Per line, so a nouveau.conf from an earlier run (which only had the first
# line) gets the second one instead of being taken as "already done".
for _line in "${NOUVEAU_LINES[@]}"; do
  if [ -f "$NOUVEAU" ] && grep -qxF "$_line" "$NOUVEAU"; then
    continue
  fi
  echo "$_line" | sudo tee -a "$NOUVEAU" 2>&1 | tee -a "$LOG"
done
if [ -f "$NOUVEAU" ] && grep -qxF "blacklist nouveau" "$NOUVEAU" && grep -qxF "install nouveau /bin/true" "$NOUVEAU"; then
  printf "${OK} ${YELLOW}nouveau${RESET} is blacklisted in $NOUVEAU.\n"
else
  echo "${WARN} Could not write the nouveau blacklist to $NOUVEAU." | tee -a "$LOG"
fi

# Rebuild AFTER the blacklist is on disk. The default `kms` hook puts nouveau in
# the initramfs and `modconf` copies /etc/modprobe.d into it, so a blacklist
# written after the last rebuild is not in the image that actually boots.
# nvidia.sh leaves the rebuild to this script when nouveau is selected, so this
# one image carries the NVIDIA modules, their options and the blacklist.
rebuild_initramfs "$LOG" || true

printf "\n%.0s" {1..2}
