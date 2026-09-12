#!/bin/bash
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
  # (configs/Startup_Apps.lua). Checking for mako made the final screen of every
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

# Outcome checks: did each selected component actually produce what it exists
# to produce? Package presence alone missed the failures that matter most. A
# copy.sh that died left vanilla Hyprland with every package "installed"; a
# locales.sh killed by set -e left LC_TIME pointing at a locale that was never
# generated; a chsh that failed left bash as the login shell. None of those is
# a package, so none of them stopped the reboot, and install.sh used to clear
# the screen right before this point so the evidence was gone as well.
#
# install.sh exports the selection as INSTALL_SELECTED_OPTIONS. Checks that
# do not depend on a selection always run.
outcome_failures=()
sel=" ${INSTALL_SELECTED_OPTIONS:-} "

selected() { [[ "$sel" == *" $1 "* ]]; }

# check_outcome <what failed> <command...>
check_outcome() {
    local what="$1"; shift
    if ! "$@" &>/dev/null; then
        outcome_failures+=("$what")
    fi
}

# Always: these run on every install regardless of the preset.
check_outcome "ru_RU.UTF-8 locale not generated - clock, calendar and lock screen fall back to English (install-scripts/locales.sh)" \
    bash -c 'locale -a | grep -qi "^ru_RU\.utf8$"'
check_outcome "no AUR helper on PATH (install-scripts/yay.sh)" \
    bash -c 'command -v yay || command -v paru'
check_outcome "NetworkManager.service is not enabled (install-scripts/services.sh)" \
    systemctl is-enabled NetworkManager.service
if pacman -Qi systemd-resolvconf &>/dev/null; then
    check_outcome "systemd-resolvconf is installed but systemd-resolved is not enabled - DNS will fail (install-scripts/services.sh)" \
        systemctl is-enabled systemd-resolved.service
fi

if selected dots; then
    check_outcome "dotfiles not deployed: ~/.config/hypr/hyprland.lua is missing (install-scripts/dotfiles-main.sh)" \
        test -f "$HOME/.config/hypr/hyprland.lua"
    check_outcome "dotfiles not deployed: ~/.config/quickshell/bar/shell.qml is missing (install-scripts/dotfiles-main.sh)" \
        test -f "$HOME/.config/quickshell/bar/shell.qml"
    check_outcome "dotfiles not deployed: ~/.zshrc is missing (install-scripts/dotfiles-main.sh)" \
        test -f "$HOME/.zshrc"
    check_outcome "wallpaper not seeded: ~/.config/hypr/wallpaper_effects/.wallpaper_current is missing (Hyprland-Dots/copy.sh)" \
        test -f "$HOME/.config/hypr/wallpaper_effects/.wallpaper_current"
fi

if selected ly; then
    check_outcome "ly@tty2.service is not enabled (install-scripts/ly.sh)" \
        systemctl is-enabled ly@tty2.service
    check_outcome "/etc/ly/config.ini does not match assets/ly/config.ini (install-scripts/ly_config.sh)" \
        cmp -s /etc/ly/config.ini "assets/ly/config.ini"
fi

if selected zsh; then
    check_outcome "login shell is not zsh (install-scripts/zsh.sh)" \
        bash -c '[[ "$(getent passwd "$USER" | cut -d: -f7)" == */zsh ]]'
    check_outcome "~/.oh-my-zsh is missing (install-scripts/zsh.sh)" \
        test -d "$HOME/.oh-my-zsh"
fi

if selected pokemon; then
    check_outcome "pokemon-colorscripts is not on PATH - every terminal prints an error (install-scripts/zsh_pokemon.sh)" \
        command -v pokemon-colorscripts
fi

if selected gtk_themes; then
    check_outcome "icon theme Flat-Remix-Blue-Dark not extracted to ~/.icons (GTK-themes-icons/auto-extract.sh)" \
        test -d "$HOME/.icons/Flat-Remix-Blue-Dark"
    check_outcome "cursor theme Bibata-Modern-Ice not extracted to ~/.icons (GTK-themes-icons/auto-extract.sh)" \
        test -d "$HOME/.icons/Bibata-Modern-Ice"
fi

if selected nopasswd_sudo; then
    check_outcome "sudo still asks for a password - the bar's VPN widget will not work (install-scripts/sudoers_nopasswd.sh)" \
        sudo -n true
fi

if selected printing; then
    check_outcome "cups.socket is not enabled (install-scripts/printing.sh)" \
        systemctl is-enabled cups.socket
fi

if selected handy; then
    check_outcome "handy is not on PATH (install-scripts/handy.sh)" \
        command -v handy
fi

# Log missing packages
if [ ${#missing[@]} -eq 0 ] && [ ${#local_missing[@]} -eq 0 ] && [ ${#outcome_failures[@]} -eq 0 ]; then
    echo "${OK} GREAT! All ${YELLOW}essential packages${RESET} are installed and every selected component checked out." | tee -a "$LOG"
    exit 0
fi

if [ ${#outcome_failures[@]} -ne 0 ]; then
    echo "${WARN} The following components did NOT land as expected:"
    for f in "${outcome_failures[@]}"; do
        echo "  ${WARNING}$f${RESET}"
        echo "OUTCOME: $f" >> "$LOG"
    done
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
