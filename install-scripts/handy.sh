#!/bin/bash
# Handy - free, open-source, offline speech-to-text.
#
# This script only installs the packages. Everything Handy needs on the desktop
# side is owned by the dotfiles and arrives with dotfiles-main.sh:
#   - UserScripts/handy-start.sh     the launcher (visible until a model is picked,
#                                    hidden afterwards; exits quietly if handy is missing)
#   - UserConfigs/UserKeybinds.lua   CTRL+SUPER+F8 -> notify + handy --toggle-transcription
#   - UserConfigs/Startup_Apps.lua   the (commented-out) autostart line
#
# It used to write its own copy of the launcher over the shipped one and append a
# second keybind and a second autostart handler. The two launchers drifted (one
# checked settings.json, the real file is settings_store.json), the copy lacked the
# missing-binary guard and the first-login hint, and the appended autostart baked
# this machine's absolute $HOME into an otherwise portable config. Removed 2026-09-13:
# a file has one owner, and for these three it is the dotfiles.
#
# NOTE: runs AFTER dotfiles-main.sh in install.sh, so the check below sees the files.

handy_pkg=(
  handy-bin
  wtype
  gtk-layer-shell
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
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_handy.log"

# Install packages (handy-bin is AUR; wtype + gtk-layer-shell are repo)
printf "\n%s - Installing ${SKY_BLUE}Handy speech-to-text${RESET} packages .... \n" "${NOTE}"
for PKG in "${handy_pkg[@]}"; do
  install_package "$PKG" "$LOG"
done

# Report-only: the desktop integration comes from the dotfiles. Say so if it is not
# there, rather than writing a second copy of it.
HANDY_LAUNCHER="$HOME/.config/hypr/UserScripts/handy-start.sh"
USER_KEYBINDS="$HOME/.config/hypr/UserConfigs/UserKeybinds.lua"
if [ -x "$HANDY_LAUNCHER" ] && grep -q 'handy --toggle-transcription' "$USER_KEYBINDS" 2>/dev/null; then
  echo "${OK} Launcher and CTRL+SUPER+F8 keybind are in place (from the dotfiles)." | tee -a "$LOG"
else
  echo "${WARN} The dotfiles' Handy launcher/keybind were not found under ~/.config/hypr." | tee -a "$LOG"
  echo "${NOTE} Select the 'dots' option (or run install-scripts/dotfiles-main.sh); handy.sh no longer writes them itself." | tee -a "$LOG"
fi

printf "\n${NOTE} ${SKY_BLUE}Handy${RESET} installed. Autostart is ${YELLOW}disabled${RESET} to save RAM - run ${MAGENTA}handy${RESET} once to pick a model (${MAGENTA}Parakeet V3${RESET} recommended, auto-detects 25 languages) and let it download. Afterwards ${YELLOW}CTRL+SUPER+F8${RESET} toggles transcription. To autostart it, uncomment the handy-start.sh line in ${SKY_BLUE}~/.config/hypr/UserConfigs/Startup_Apps.lua${RESET}.\n"
printf "\n%.0s" {1..2}
