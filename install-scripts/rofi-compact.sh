#!/bin/bash
# The rofi wrapper for screens with big pixels: /usr/local/bin/rofi
#
# rofi cannot scale a theme written in pixels, and on a screen below 100 PPI
# (a 27" 1920x1080) the menus were as oversized as everything else. So
# DisplayDensity.sh's compact profile keeps a copy of ~/.config/rofi with
# every pixel and font size at 80% (RofiCompact.sh, in ~/.cache/rofi-compact),
# and this wrapper - ahead of /usr/bin/rofi in PATH - sends rofi to the copy
# while that profile is on. With the profile off, or on a machine that never
# had it on, the wrapper execs /usr/bin/rofi with its arguments untouched.
#
# The wrapper itself is assets/rofi-compact/rofi.

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "Failed to change directory to $PARENT_DIR"; exit 1; }

if ! source "$SCRIPT_DIR/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_rofi-compact.log"

printf "\n${NOTE} Installing the ${SKY_BLUE}rofi wrapper${RESET} for screens with big pixels...\n" | tee -a "$LOG"

src="assets/rofi-compact/rofi"
if [ ! -f "$src" ]; then
  printf "${ERROR} Missing $src\n" | tee -a "$LOG"
  exit 1
fi

# root:root 0755: every menu of the desktop runs through it.
sudo install -o root -g root -m 0755 "$src" /usr/local/bin/rofi 2>&1 | tee -a "$LOG"
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
  printf "${ERROR} Failed to install /usr/local/bin/rofi - the menus keep their full size on a screen with big pixels.\n" | tee -a "$LOG"
  exit 1
fi
printf "${OK} Installed ${SKY_BLUE}/usr/local/bin/rofi${RESET}\n" | tee -a "$LOG"

printf "\n%.0s" {1..2}
exit 0
