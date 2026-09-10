#!/bin/bash
# https://github.com/JaKooLit

# Set some colors for output messages
OK="$(tput setaf 2)[OK]$(tput sgr0)"
ERROR="$(tput setaf 1)[ERROR]$(tput sgr0)"
NOTE="$(tput setaf 3)[NOTE]$(tput sgr0)"
INFO="$(tput setaf 4)[INFO]$(tput sgr0)"
WARN="$(tput setaf 1)[WARN]$(tput sgr0)"
CAT="$(tput setaf 6)[ACTION]$(tput sgr0)"
MAGENTA="$(tput setaf 5)"
ORANGE="$(tput setaf 214)"
WARNING="$(tput setaf 1)"
YELLOW="$(tput setaf 3)"
GREEN="$(tput setaf 2)"
BLUE="$(tput setaf 4)"
SKY_BLUE="$(tput setaf 6)"
RESET="$(tput sgr0)"

# Variables
# This is a fork of JaKooLit/Arch-Hyprland carrying local customisations, so it
# must clone THIS repo - cloning upstream would install a stock system and
# silently discard every change in Hyprland-Dots/ and install-scripts/.
# HTTPS on purpose: a freshly installed machine has no SSH key yet.
Distro="my_archinstaller"
Github_URL="https://github.com/CarlosDLMC/$Distro.git"
# ~/Documents/my_archinstaller, matching the path the README tells you to clone
# to and the one diagnose.sh and the troubleshooting steps print. Cloning to
# $HOME instead left two copies of the repo on the machine, and any fix applied
# to the documented path had no effect on the one that actually ran.
Distro_DIR="$HOME/Documents/$Distro"

printf "\n%.0s" {1..1}

if ! command -v git &> /dev/null
then
    echo "${INFO} Git not found! ${SKY_BLUE}Installing Git...${RESET}"
    if ! sudo pacman -S git --noconfirm; then
        echo "${ERROR} Failed to install Git. Exiting."
        exit 1
    fi
fi

printf "\n%.0s" {1..1}

if [ -d "$Distro_DIR" ]; then
    echo "${YELLOW}$Distro_DIR exists. Updating the repository... ${RESET}"
    cd "$Distro_DIR" || { echo "${ERROR} Cannot enter $Distro_DIR. Exiting."; exit 1; }

    # Never stash silently: a stash here is invisible afterwards and looks
    # exactly like the local edits having been lost. Stop and let the user decide.
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "${ERROR} $Distro_DIR has uncommitted changes."
        echo "${NOTE} Commit or stash them yourself, then re-run. Showing what changed:"
        git status --short
        exit 1
    fi

    if ! git pull --ff-only; then
        echo "${ERROR} git pull failed (diverged history, or no network)."
        echo "${NOTE} Resolve it in $Distro_DIR, then re-run."
        exit 1
    fi
else
    echo "${MAGENTA}$Distro_DIR does not exist. Cloning the repository...${RESET}"
    # No --depth=1: this is a working config repo, and its history is the record
    # of why things are the way they are.
    mkdir -p "$(dirname "$Distro_DIR")"
    if ! git clone "$Github_URL" "$Distro_DIR"; then
        echo "${ERROR} Failed to clone $Github_URL. Exiting."
        exit 1
    fi
    cd "$Distro_DIR" || { echo "${ERROR} Cannot enter $Distro_DIR. Exiting."; exit 1; }
fi

chmod +x install.sh

# Drive the install from the preset, exactly as the README documents. Without
# --preset, install.sh opens the interactive checklist with every option
# unticked, so an "auto" install would sit waiting for input and then install
# a bare Hyprland with none of the customisations in this repo.
./install.sh --preset custom-preset.conf
