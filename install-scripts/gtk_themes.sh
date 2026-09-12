#!/bin/bash
# GTK Themes & ICONS and  Sourcing from a different Repo #

engine=(
    unzip
    gtk-engine-murrine
)

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


# Set the name of the log file to include the current date and time
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_themes.log"


# installing engine needed for gtk themes
for PKG1 in "${engine[@]}"; do
    install_package "$PKG1" "$LOG"
done

# Extract the themes and icons that ship with this repo.
#
# This used to `rm -rf GTK-themes-icons` and then clone upstream. GTK-themes-icons
# is committed *here* - the Flat-Remix theme tarballs and the Bibata cursor zip
# are tracked files - so that deleted tracked content on every run: the working
# tree was left dirty with deletions, and auto-install.sh's uncommitted-changes
# guard then refused to pull ever again. Using the local copy also pins the
# theme versions initial-boot.sh names, and works with no network.
if [ -d "GTK-themes-icons" ]; then
    echo "$NOTE Extracting ${SKY_BLUE}GTK themes and Icons${RESET} bundled with this repo..." 2>&1 | tee -a "$LOG"
    (
        cd GTK-themes-icons || exit 1
        chmod +x auto-extract.sh
        ./auto-extract.sh
    ) 2>&1 | tee -a "$LOG"

    # initial-boot.sh sets these three by name over gsettings, so a missing one
    # is a silently unthemed desktop rather than a visible error.
    for _want in "$HOME/.themes/Flat-Remix-GTK-Blue-Dark" \
                 "$HOME/.icons/Flat-Remix-Blue-Dark" \
                 "$HOME/.icons/Bibata-Modern-Ice"; do
        if [ -d "$_want" ]; then
            echo "$OK $(basename "$_want") installed" 2>&1 | tee -a "$LOG"
        else
            echo "$ERROR $(basename "$_want") missing after extraction" 2>&1 | tee -a "$LOG"
        fi
    done
else
    echo "$ERROR GTK-themes-icons not found in this repo - themes NOT installed." 2>&1 | tee -a "$LOG"
fi

printf "\n%.0s" {1..2}