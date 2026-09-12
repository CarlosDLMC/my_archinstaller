#!/bin/bash
# Power profile daemon (whatever provides the power-profiles-daemon D-Bus API)

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "${ERROR} Failed to change directory to $PARENT_DIR"; exit 1; }

if ! source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_power_profiles.log"

# Why this is not just another entry in 01-hypr-pkgs.sh
#
# The bar's PowerProfileWidget.qml runs `powerprofilesctl` and watches
# net.hadess.PowerProfiles on the system bus. What it needs is that D-Bus API,
# not one specific package. On Arch the API comes from power-profiles-daemon.
# On CachyOS it normally comes from tuned-cachy-ppd, which *provides* the same
# API and *conflicts* with power-profiles-daemon.
#
# That conflict is the problem. Asking for power-profiles-daemon there is not a
# harmless no-op - it is a conflicting transaction, and `pacman -S --noconfirm`
# will not remove an installed package to satisfy it. The install stops partway
# through a run whose entire selling point is that it is unattended.
#
# So ask pacman whether anything already satisfies the dependency and only
# install when nothing does. `pacman -T` prints the unsatisfied dependency and
# exits non-zero; satisfied, it prints nothing and exits 0 - and it counts
# `provides`, which is exactly the question being asked here.

if pacman -T power-profiles-daemon &>/dev/null; then
  # Name it if we can, for the log. These are the packages that realistically
  # provide the API; an unrecognised one is still fine, just unnamed.
  provider=$(pacman -Qq power-profiles-daemon tuned-ppd tuned-cachy-ppd 2>/dev/null | paste -sd' ' -)
  printf "\n${OK} The power-profiles-daemon API is already provided by ${SKY_BLUE}${provider:-another package}${RESET}.\n" | tee -a "$LOG"
  printf "${NOTE} Leaving it alone - installing power-profiles-daemon over it would conflict.\n" | tee -a "$LOG"
else
  printf "\n${NOTE} Installing ${SKY_BLUE}power-profiles-daemon${RESET}...\n" | tee -a "$LOG"
  install_package power-profiles-daemon "$LOG"
fi

# The widget calls the CLI, not the bus, so a provider without powerprofilesctl
# leaves the dropdown inert even though the daemon is running fine.
if command -v powerprofilesctl &>/dev/null; then
  printf "${OK} powerprofilesctl is available - the bar's power widget will work.\n" | tee -a "$LOG"
else
  printf "${WARN} powerprofilesctl is not installed. The bar's power profile widget\n" | tee -a "$LOG"
  printf "${WARN} will show nothing and switching profiles from it will do nothing.\n" | tee -a "$LOG"
fi

printf "\n%.0s" {1..2}
