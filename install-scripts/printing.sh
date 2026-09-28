#!/bin/bash
# CUPS - printing. Nothing else in this install pulls it in, so without this
# script a fresh machine has no print stack at all: every application's print
# dialog comes up with an empty printer list and no way to add one.
#
# Like docker.sh, this uses SOCKET ACTIVATION rather than enabling cups.service
# at boot: cups.socket + cups.path start cupsd on demand - the first print
# dialog, `lp` or `lpadmin` call. NOT a visit to http://localhost:631: the
# socket unit listens only on /run/cups/cups.sock, so on a machine where cupsd
# has never run the web UI is "connection refused" until something starts it
# (`sudo systemctl start cups`). Once it has run it stays: with the web
# interface on (the stock cupsd.conf) cupsd never idle-exits, and it leaves
# behind the /var/cache/cups/org.cups.cupsd that cups.path waits for, so it
# starts at every boot from then on. Adding the PDF printer below is that first
# run, so after the install reboot localhost:631 is simply there.
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
  # Print-to-PDF as a virtual printer (the "PDF" queue added below), so "save
  # as PDF" works from any print dialog and from `lp -d PDF`, including in
  # applications that have no PDF export of their own.
  cups-pdf
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
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_printing.log"

# Install packages
printf "\n%s - Installing ${SKY_BLUE}CUPS printing${RESET} packages .... \n" "${NOTE}"
for PKG in "${printing_pkg[@]}"; do
  install_package "$PKG" "$LOG"
done

# Socket activation: cupsd starts on demand, not at boot (until it has run once -
# see the top of this file).
printf "\n${NOTE} Configuring ${SKY_BLUE}CUPS socket activation${RESET} (on-demand, no boot autostart)...\n" | tee -a "$LOG"
sudo systemctl enable cups.socket 2>&1 | tee -a "$LOG"
sudo systemctl enable cups.path 2>&1 | tee -a "$LOG"

if [ "$(systemctl is-enabled cups.socket 2>/dev/null)" = "enabled" ]; then
  echo "${OK} CUPS set to socket-activation. cupsd starts on the first print job." | tee -a "$LOG"
else
  echo "${WARN} cups.socket is not enabled - check: systemctl is-enabled cups.socket" | tee -a "$LOG"
fi

# The "PDF" virtual printer. cups-pdf ships only the backend and its PPDs - its
# install scriptlet just prints "You can now add a Virtual Printer" - so the
# package alone put no PDF printer in any CUPS print dialog or `lp -d`.
#
# lpadmin and lpstat reach cupsd through /run/cups/cups.sock, and `enable` above
# does not start the socket before the next boot, so it is started here; the
# first connection then activates cupsd. Checked by name first so a re-run does
# not touch a queue that is already there.
#
# Not fatal: GTK and Qt print dialogs have their own "Print to File" as PDF, so
# losing this costs only the CUPS queue.
printf "\n${NOTE} Adding the ${SKY_BLUE}PDF${RESET} virtual printer (cups-pdf)...\n" | tee -a "$LOG"
sudo systemctl start cups.socket >> "$LOG" 2>&1 || true
if lpstat -p PDF >/dev/null 2>&1; then
  echo "${OK} PDF virtual printer already configured." | tee -a "$LOG"
elif sudo lpadmin -p PDF -E -v cups-pdf:/ -m CUPS-PDF_opt.ppd >> "$LOG" 2>&1 &&
     lpstat -p PDF >/dev/null 2>&1; then
  # cups-pdf.conf's Out, unchanged from the package default.
  echo "${OK} Added the PDF printer. Its files land in /var/spool/cups-pdf/$USER/." | tee -a "$LOG"
else
  echo "${WARN} Could not add the PDF printer - see $LOG. Add it later with:" | tee -a "$LOG"
  echo "${NOTE}   sudo lpadmin -p PDF -E -v cups-pdf:/ -m CUPS-PDF_opt.ppd" | tee -a "$LOG"
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

printf "\n${NOTE} ${SKY_BLUE}CUPS${RESET} installed. Add your printer with ${MAGENTA}lpadmin${RESET} (see ${MAGENTA}driverless${RESET}) or at ${MAGENTA}http://localhost:631${RESET}\n"
printf "${NOTE} (Administration -> Add Printer). If that page is refused, cupsd is not running yet -\n"
printf "${NOTE} port 631 does not start it; ${MAGENTA}sudo systemctl start cups${RESET} does.\n"
printf "${NOTE} A network IPP printer is normally discovered automatically -\n"
printf "${NOTE} avahi and nss-mdns are already wired up by services.sh.\n"
printf "\n%.0s" {1..2}
