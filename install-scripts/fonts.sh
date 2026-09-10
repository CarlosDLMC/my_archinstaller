#!/bin/bash
# 💫 https://github.com/JaKooLit 💫 #
# Fonts #

# These fonts are minimun required for pre-configured dots to work. You can add here as required
# WARNING! If you remove packages here, dotfiles may not work properly.
# and also, ensure that packages are present in AUR and official Arch Repo

fonts=(
  adobe-source-code-pro-fonts
  noto-fonts-emoji
  otf-font-awesome
  ttf-droid
  ttf-fira-code
  ttf-fantasque-nerd
  ttf-jetbrains-mono
  ttf-jetbrains-mono-nerd
  ttf-victor-mono
  noto-fonts

  # REQUIRED by the quickshell bar. Theme.qml sets
  #   readonly property string fontFamily: "Terminess Nerd Font"
  # and every widget in the bar renders through Theme.fontFamily, so without
  # this package fontconfig substitutes something else and the whole bar is
  # laid out in the wrong face - silently, since a font fallback is not an
  # error. "Terminess" is the Nerd Fonts name for Terminus.
  ttf-terminus-nerd

  # ttf-fira-code above covers "Fira Code Semi-Bold", used by dunst and by
  # gtk-3.0/settings.ini, and ttf-jetbrains-mono-nerd covers
  # "JetBrainsMono Nerd Font Mono", used by foot, hyprlock and SovietLockGen.py.

  # The rest of the terminal/bitmap Nerd Fonts on this setup. Nothing in the
  # dots hardcodes them, but they are what is available to pick from when
  # editing Theme.qml, foot.ini or a rofi theme.
  ttf-3270-nerd
  ttf-bigblueterminal-nerd
  ttf-envycoder-nerd
  ttf-gohu-nerd
  ttf-profont-nerd
  ttf-proggyclean-nerd
  ttf-sharetech-mono-nerd

  ttf-ubuntu-font-family
)

# Font families the dots name and that must resolve to themselves after the
# install. fontconfig substitutes silently on a miss, so a missing font shows up
# as a subtly wrong-looking desktop rather than as a failure - check explicitly.
required_families=(
  "Terminess Nerd Font"           # quickshell bar (Theme.qml)
  "JetBrainsMono Nerd Font Mono"  # foot, hyprlock, SovietLockGen.py
  "Fira Code"                     # dunst, gtk-3.0/settings.ini
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
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_fonts.log"


# Installation of main components
printf "\n%s - Installing necessary ${SKY_BLUE}fonts${RESET}.... \n" "${NOTE}"

for PKG1 in "${fonts[@]}"; do
  install_package "$PKG1" "$LOG"
done

# Verify the families the dots actually name.
#
# A missing font is not an error anywhere: fontconfig silently substitutes its
# best guess, so the only symptom is a desktop that looks subtly wrong. Check
# for the families by name so a missing one is stated out loud.
#
# This lists installed families rather than using `fc-match`, because fc-match
# answers "what would you render this as", not "do you have it" - it can return
# a substitute for a family that is installed (it does exactly that for
# "Fira Code" on this setup), which would make the check cry wolf.
if command -v fc-list >/dev/null 2>&1; then
  printf "\n%s - Verifying required font families...\n" "${NOTE}"
  fc-cache -f >/dev/null 2>&1

  _installed_families=$(fc-list : family | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

  for _family in "${required_families[@]}"; do
    if printf '%s\n' "$_installed_families" | grep -Fxq "$_family"; then
      echo "${OK} $_family" 2>&1 | tee -a "$LOG"
    else
      echo "${WARN} Font family '$_family' is MISSING." 2>&1 | tee -a "$LOG"
      echo "${NOTE} Anything asking for it renders in a substituted face instead." 2>&1 | tee -a "$LOG"
    fi
  done
fi

printf "\n%.0s" {1..2}