#!/bin/bash
# 💫 https://github.com/JaKooLit 💫 #
# Enable essential systemd services #

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
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_services.log"

printf "\n${INFO} Enabling essential ${SKY_BLUE}system services${RESET}...\n" | tee -a "$LOG"

# Enable NetworkManager
printf "\n${NOTE} Enabling ${SKY_BLUE}NetworkManager${RESET}...\n" | tee -a "$LOG"
sudo systemctl enable --now NetworkManager.service 2>&1 | tee -a "$LOG"
if systemctl is-active --quiet NetworkManager.service; then
  echo "${OK} NetworkManager is running." | tee -a "$LOG"
else
  echo "${WARN} NetworkManager failed to start. Network connectivity may not work." | tee -a "$LOG"
fi

# Enable whichever daemon provides the power-profiles-daemon D-Bus API.
#
# The unit name is not fixed. power-profiles-daemon.service on Arch;
# tuned-ppd.service (plus tuned.service under it) on CachyOS, where
# tuned-cachy-ppd provides the same interface. Hardcoding the first meant that
# on CachyOS this enabled a unit that does not exist, printed a warning, and
# left the bar's power widget pointing at a daemon nobody had started.
ppd_unit=""
for unit in power-profiles-daemon.service tuned-ppd.service; do
  if systemctl cat "$unit" &>/dev/null; then
    ppd_unit="$unit"
    break
  fi
done

if [ -z "$ppd_unit" ]; then
  echo "${WARN} No power profile daemon unit found. The bar's power widget will be inert." | tee -a "$LOG"
else
  printf "\n${NOTE} Enabling ${SKY_BLUE}${ppd_unit}${RESET}...\n" | tee -a "$LOG"
  # tuned-ppd is only the translation layer; tuned itself does the work.
  if [ "$ppd_unit" == "tuned-ppd.service" ] && systemctl cat tuned.service &>/dev/null; then
    sudo systemctl enable --now tuned.service 2>&1 | tee -a "$LOG"
  fi
  sudo systemctl enable --now "$ppd_unit" 2>&1 | tee -a "$LOG"
  if systemctl is-active --quiet "$ppd_unit"; then
    echo "${OK} $ppd_unit is running." | tee -a "$LOG"
  else
    echo "${WARN} $ppd_unit failed to start. Power profile management may not work." | tee -a "$LOG"
  fi
fi

# Wire nss-mdns into /etc/nsswitch.conf.
#
# thunar.sh enables avahi-daemon, but enabling the daemon is only half of it:
# glibc never asks Avahi unless "mdns_minimal [NOTFOUND=return]" sits in the
# hosts: line, ahead of dns. Without it .local hostnames simply do not resolve
# and nothing reports an error - the name just fails to look up.
printf "\n${NOTE} Wiring ${SKY_BLUE}nss-mdns${RESET} into /etc/nsswitch.conf...\n" | tee -a "$LOG"
if ! pacman -Qi nss-mdns &>/dev/null; then
  echo "${WARN} nss-mdns is not installed. Skipping .local name resolution." | tee -a "$LOG"
elif grep -q 'mdns_minimal' /etc/nsswitch.conf; then
  echo "${OK} nsswitch.conf already resolves .local names." | tee -a "$LOG"
else
  sudo cp /etc/nsswitch.conf /etc/nsswitch.conf.bak-"$(date +%Y%m%d-%H%M%S)"
  # Insert before "dns" so mDNS is consulted first, and keep the rest intact.
  sudo sed -i -E '/^hosts:/ s/\bdns\b/mdns_minimal [NOTFOUND=return] dns/' /etc/nsswitch.conf
  if grep -q 'mdns_minimal' /etc/nsswitch.conf; then
    echo "${OK} .local name resolution enabled." | tee -a "$LOG"
  else
    echo "${WARN} Could not edit nsswitch.conf. .local names will not resolve." | tee -a "$LOG"
  fi
fi

printf "\n%.0s" {1..2}
