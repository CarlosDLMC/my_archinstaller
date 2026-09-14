#!/bin/bash
# Bluetooth Stuff #

blue=(
  bluez
  bluez-utils
  bluez-obex
  blueman
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
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_bluetooth.log"

# Bluetooth
printf "${NOTE} Installing ${SKY_BLUE}Bluetooth${RESET} Packages...\n"
 for BLUE in "${blue[@]}"; do
   install_package "$BLUE" "$LOG"
  done

# Enable the service, as on the machine this repo reproduces. It used to be left
# disabled "to save battery", but the radio itself is what the bar toggles: its
# off switch does `systemctl stop bluetooth && rfkill block bluetooth`, and
# systemd-rfkill restores that block at boot, so an enabled service on a blocked
# radio costs nothing. A disabled service instead meant Bluetooth was off after
# every boot until the bar glyph was clicked, whatever the radio state was.
printf " Enabling ${YELLOW}bluetooth.service${RESET}...\n"
sudo systemctl enable bluetooth.service 2>&1 | tee -a "$LOG"
if [ "${PIPESTATUS[0]}" -eq 0 ]; then
  echo "${OK} bluetooth.service enabled" | tee -a "$LOG"
else
  echo "${ERROR} Could not enable bluetooth.service - Bluetooth will be off at every boot" | tee -a "$LOG"
fi
printf " The bar widget turns the radio on and off.\n"

# Add sudoers rule for passwordless bluetooth control
printf " Setting up ${YELLOW}passwordless bluetooth control${RESET}...\n"
# Built in a temp file and validated with visudo first: a malformed file in
# sudoers.d (e.g. an empty $USER) makes EVERY sudo refuse to run.
BT_USER="${USER:-$(id -un)}"
if [ -z "$BT_USER" ]; then
  echo "${ERROR} Cannot determine the user name - not writing a sudoers rule." | tee -a "$LOG"
else
  BT_RULE="$(mktemp)"
  echo "$BT_USER ALL=(ALL) NOPASSWD: /usr/bin/rfkill, /usr/bin/systemctl start bluetooth, /usr/bin/systemctl stop bluetooth" > "$BT_RULE"
  if sudo visudo -c -f "$BT_RULE" >/dev/null 2>&1; then
    # PIPESTATUS, not the pipeline status: `sudo install ... | tee` reports
    # tee's exit code, so the OK line below was printed whether or not the rule
    # landed. Unlike the wheel rule, nothing in 02-Final-Check.sh looks for this
    # one, so a failure here was invisible - the bar's bluetooth toggle just did
    # nothing, with no message anywhere saying why.
    sudo install -m 0440 -o root -g root "$BT_RULE" /etc/sudoers.d/bluetooth-toggle 2>&1 | tee -a "$LOG"
    if [ "${PIPESTATUS[0]}" -eq 0 ] && sudo test -f /etc/sudoers.d/bluetooth-toggle; then
      echo "${OK} sudoers rule for the bar's bluetooth toggle installed" | tee -a "$LOG"
    else
      echo "${ERROR} Could not install /etc/sudoers.d/bluetooth-toggle - the bar's bluetooth toggle will not work" | tee -a "$LOG"
    fi
  else
    echo "${ERROR} Generated sudoers rule failed validation - NOT installing it" | tee -a "$LOG"
    sudo visudo -c -f "$BT_RULE" 2>&1 | tee -a "$LOG"
  fi
  rm -f "$BT_RULE"
fi

# Disable blueman auto-start to save RAM (bar widget handles bluetooth)
printf " Disabling ${YELLOW}blueman auto-start${RESET} (saves ~130MB RAM)...\n"
sudo rm -f /etc/xdg/autostart/blueman.desktop 2>&1 | tee -a "$LOG"
systemctl --user mask blueman-applet.service 2>&1 | tee -a "$LOG"

printf "\n%.0s" {1..2}