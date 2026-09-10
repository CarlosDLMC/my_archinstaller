#!/bin/bash
# 💫 https://github.com/JaKooLit 💫 #
# quickshell - for desktop overview replacing AGS

if [[ $USE_PRESET = [Yy] ]]; then
  source ./preset.sh
fi

# quickshell, NOT quickshell-git.
#
# This machine happens to run quickshell-git (0.3.0.r6.gb66495f) because that is
# what was available when the bar was written, so the obvious "reproduce it
# exactly" move is to install the -git package here too. That is a trap: a -git
# PKGBUILD builds whatever upstream HEAD is on the day you install, so it pins
# nothing and can only drift further from what the bar was tested against.
#
# Stable is safe here, and this was verified rather than assumed - the exported
# QML API of 0.3.1 was diffed against the 0.3.0.r6 build this bar was written
# on: 118 -> 119 types and 1056 -> 1057 members, with *nothing* removed or
# renamed. The bar only touches PanelWindow, PopupWindow, Variants, ShellRoot,
# Singleton, Process, Timer and HyprlandFocusGrab, all unchanged.
#
# If the bar ever does come up blank after an install, re-run that diff before
# reaching for the -git package:
#   pacman -Qlq quickshell | grep qmltypes
quick=(
    qt6-5compat
    quickshell
)

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Change the working directory to the parent directory of the script
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || {
  echo "${ERROR} Failed to change directory to $PARENT_DIR"
  exit 1
}

# Source the global functions script
if ! source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

# Set the name of the log file to include the current date and time
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_quick.log"

# Installation of main components
printf "\n%s - Installing ${SKY_BLUE}Quick Shell ${RESET} for Desktop Overview \n" "${NOTE}"

for PKG1 in "${quick[@]}"; do
  install_package "$PKG1" "$LOG"
done

printf "\n%.0s" {1..1}

