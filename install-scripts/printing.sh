#!/bin/bash
# CUPS - printing. Nothing else in this install pulls it in, so without this
# script a fresh machine has no print stack at all: every application's print
# dialog comes up with an empty printer list and no way to add one.
#
# Like docker.sh, this uses SOCKET ACTIVATION rather than enabling cups.service
# at boot. cupsd is idle almost all the time on a laptop, and cups.socket +
# cups.path start it on demand - the first print dialog, `lp` call, or visit to
# http://localhost:631 activates it. Enable cups.service instead if you want
# cupsd resident (needed only if you rely on it continuously browsing the
# network for newly appeared printers).
#
# No printer driver package is needed for an IPP Everywhere / AirPrint printer,
# which is what modern network printers are: cups-filters does the rendering and
# the printer advertises its own capabilities. Only an old USB or PostScript-only
# model needs a vendor driver (e.g. brother-* or gutenprint from the AUR).
#
# The printer itself is NOT configured here. /etc/cups/printers.conf holds a
# device URI with a LAN IP that will not be the same on another network, so it
# is machine-specific in the same way /etc/wireguard is - see the README.

printing_pkg=(
  cups
  # The rendering filters. cups can technically install without them, and then
  # every job silently fails to render rather than erroring at install time.
  cups-filters
  # Print-to-PDF as a virtual printer, so "save as PDF" works from any print
  # dialog, including in applications that have no PDF export of their own.
  cups-pdf
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
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_printing.log"

# Install packages
printf "\n%s - Installing ${SKY_BLUE}CUPS printing${RESET} packages .... \n" "${NOTE}"
for PKG in "${printing_pkg[@]}"; do
  install_package "$PKG" "$LOG"
done

# Socket activation: cupsd starts on demand, not at boot.
printf "\n${NOTE} Configuring ${SKY_BLUE}CUPS socket activation${RESET} (on-demand, no boot autostart)...\n" | tee -a "$LOG"
sudo systemctl enable cups.socket 2>&1 | tee -a "$LOG"
sudo systemctl enable cups.path 2>&1 | tee -a "$LOG"

if [ "$(systemctl is-enabled cups.socket 2>/dev/null)" = "enabled" ]; then
  echo "${OK} CUPS set to socket-activation. cupsd starts on the first print job." | tee -a "$LOG"
else
  echo "${WARN} cups.socket is not enabled - check: systemctl is-enabled cups.socket" | tee -a "$LOG"
fi

# Administering printers needs membership in cupsd's SystemGroup, which the
# package sets to "sys root wheel". Say so rather than leaving the user to
# discover that the web UI rejects their password.
if ! groups "$USER" | grep -qE '\b(wheel|sys)\b'; then
  echo "${WARN} $USER is in neither 'wheel' nor 'sys', so you cannot add printers" | tee -a "$LOG"
  echo "${NOTE} without root. Add yourself: sudo usermod -aG wheel $USER" | tee -a "$LOG"
else
  echo "${OK} $USER can administer printers (member of cupsd's SystemGroup)." | tee -a "$LOG"
fi

printf "\n${NOTE} ${SKY_BLUE}CUPS${RESET} installed. Add your printer with ${MAGENTA}http://localhost:631${RESET} (Administration -> Add Printer)\n"
printf "${NOTE} or ${MAGENTA}lpadmin${RESET}. A network IPP printer is normally discovered automatically -\n"
printf "${NOTE} avahi and nss-mdns are already wired up by thunar.sh and services.sh.\n"
printf "\n%.0s" {1..2}
