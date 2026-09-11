#!/bin/bash
# 💫 https://github.com/JaKooLit 💫 #
# Final checking if packages are installed
#
# Two sources are checked, and the script exits non-zero if either reports
# something missing - install.sh keys its auto-reboot off that exit code.
#
#   1. The hardcoded list below. This is a floor, not the whole check: it
#      catches a package that never got attempted at all, e.g. because its
#      install script was skipped by the preset or died before reaching it.
#   2. Install-Logs/.failed-packages, written by record_package_failure() in
#      Global_functions.sh every time an install_* function's post-install
#      verification fails. That covers every package any script actually tried
#      to install - roughly a hundred of them - rather than only these sixteen.

packages=(
  cliphist
  kvantum
  # rofi, not rofi-wayland: rofi-wayland was merged back into rofi and is what
  # 01-hypr-pkgs.sh installs.
  rofi
  imagemagick
  # dunst, not mako: dunst is the notification daemon this setup runs
  # (Startup_Apps.conf:31). Checking for mako made the final screen of every
  # single install report a missing essential package.
  dunst
  awww
  wallust
  quickshell
  wl-clipboard
  wlogout
  foot
  hypridle
  hyprlock
  hyprland
  hyprpolkitagent
  xdg-desktop-portal-hyprland
)

# Local packages that should be in /usr/local/bin/
local_pkgs_installed=(

)

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
# Determine the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Change the working directory to the parent directory of the script
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "${ERROR} Failed to change directory to $PARENT_DIR"; exit 1; }

# Source the global functions script
source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"

# Set the name of the log file to include the current date and time
LOG="Install-Logs/00_CHECK-$(date +%Y%m%d-%H%M%S)_installed.log"

printf "\n%s - Final Check if all ${SKY_BLUE}Essential packages${RESET} were installed \n" "${NOTE}"
# Initialize an empty array to hold missing packages
missing=()
local_missing=()

# Function to check if a packages are installed using pacman
is_installed_pacman() {
    pacman -Qi "$1" &>/dev/null
}

# Loop through each package
for pkg in "${packages[@]}"; do
    # Check if the packages are installed
    if ! is_installed_pacman "$pkg"; then
        missing+=("$pkg")
    fi
done

# Check for local packages
for pkg1 in "${local_pkgs_installed[@]}"; do
    if ! [ -f "/usr/local/bin/$pkg1" ]; then
        local_missing+=("$pkg1")
    fi
done

# Fold in everything any install script failed on.
#
# Re-verified rather than trusted: a package can fail its own install and then
# be pulled in later as a dependency of something else, and reporting it as
# missing when it is sitting there installed would train you to ignore this
# screen. Only what is genuinely still absent is reported.
if [ -f "$FAILED_PACKAGES_MANIFEST" ]; then
    while read -r pkg; do
        [ -n "$pkg" ] || continue
        is_installed_pacman "$pkg" && continue
        # Skip anything the hardcoded list above already reported.
        already="no"
        for seen in "${missing[@]}"; do
            [ "$seen" == "$pkg" ] && already="yes" && break
        done
        [ "$already" == "yes" ] && continue
        missing+=("$pkg")
    done < "$FAILED_PACKAGES_MANIFEST"
fi

# Log missing packages
if [ ${#missing[@]} -eq 0 ] && [ ${#local_missing[@]} -eq 0 ]; then
    echo "${OK} GREAT! All ${YELLOW}essential packages${RESET} have been successfully installed." | tee -a "$LOG"
    exit 0
fi

if [ ${#missing[@]} -ne 0 ]; then
    echo "${WARN} The following packages are NOT installed and will be logged:"
    for pkg in "${missing[@]}"; do
        echo "${WARNING}$pkg${RESET}"
        echo "$pkg" >> "$LOG"
    done
fi

if [ ${#local_missing[@]} -ne 0 ]; then
    echo "${WARN} The following local packages are missing from /usr/local/bin/ and will be logged:"
    for pkg1 in "${local_missing[@]}"; do
        echo "${WARNING}$pkg1${RESET} is not installed. Can't find it in /usr/local/bin/"
        echo "$pkg1" >> "$LOG"
    done
fi

echo "${NOTE} Missing packages logged at $(date)" >> "$LOG"

printf "\n%s Full list also in %s\n" "${NOTE}" "$LOG"

# Non-zero so install.sh knows not to reboot out from under an incomplete
# install. Before this, the warning above scrolled past and a preset run
# rebooted 15 seconds later regardless.
exit 1
