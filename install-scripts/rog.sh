#!/bin/bash
# Asus ROG Laptops #

rog=(
    # power-profiles-daemon: see power_profiles.sh, which owns it and skips
    # it when something (tuned-cachy-ppd on CachyOS) already provides the API.
    asusctl
    rog-control-center
)

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Change the working directory to the parent directory of the script
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "[ERROR] Failed to change directory to $PARENT_DIR"; exit 1; }

# Source the global functions script
if ! source "$SCRIPT_DIR/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi



# Set the name of the log file to include the current date and time
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_rog.log"

### Install software for Asus ROG laptops ###

# No supergfxctl. asusctl 6.x switches the GPU itself (ROG Control Center ->
# GPU Configuration, or `asusctl armoury set dgpu_disable 0|1`; the change is
# written at shutdown by asus-shutdown.service), its changelog says "Remove
# supergfxctl completely", and its docs say to remove supergfxd. Worse, the two
# fight: supergfxd's default config (hotplug_type None) finds dgpu_disable=1 at
# boot, writes it back to 0 and blacklists nouveau - so Eco/Integrated never
# survived a reboot, and a dGPU switched off before the install came back on
# with no driver at all.
#
# A hybrid laptop left in Eco mode keeps its dGPU powered off across a
# reinstall, so it is not on the PCI bus and install.sh's NVIDIA detection
# could not see it: say how to get the driver afterwards.
if [ "$(cat /sys/devices/platform/asus-nb-wmi/dgpu_disable 2>/dev/null)" = "1" ]; then
  echo "${WARN} The dGPU is switched off (Eco mode). If it is NVIDIA, its driver was NOT installed: it cannot be detected while switched off." | tee -a "$LOG"
  echo "${NOTE} After this install: ROG Control Center -> GPU Configuration -> Hybrid (or ${MAGENTA}asusctl armoury set dgpu_disable 0${RESET}), reboot, then run ${MAGENTA}install-scripts/nvidia.sh${RESET}." | tee -a "$LOG"
fi

printf " Installing ${SKY_BLUE}ASUS ROG packages${RESET}...\n"
for ASUS in "${rog[@]}"; do
install_package  "$ASUS" "$LOG"
done

# asusd is the daemon asusctl, rog-control-center and the keyboard/fan controls
# talk to. asusctl 6.x ships it as a static unit that udev starts when
# asus-nb-wmi binds (SYSTEMD_WANTS in its rules file), so there is nothing to
# enable - `systemctl enable` on it does nothing and used to print "[OK]
# enabled" all the same. Older packaging had an [Install] section; enable it
# only there.
if ! systemctl list-unit-files asusd.service 2>/dev/null | grep -q '^asusd\.service'; then
  echo "${WARN} asusd.service does not exist - asusctl did not install." | tee -a "$LOG"
elif [ "$(systemctl is-enabled asusd.service 2>/dev/null)" = "static" ]; then
  echo "${OK} asusd is started by udev at boot on the ASUS families its rules list (check with ${MAGENTA}systemctl status asusd${RESET} after the reboot)." | tee -a "$LOG"
elif sudo systemctl enable asusd.service >> "$LOG" 2>&1; then
  echo "${OK} asusd.service enabled" | tee -a "$LOG"
else
  echo "${ERROR} Could not enable asusd.service - see $LOG" | tee -a "$LOG"
fi

# Left over from an earlier run of this installer, which used to install it:
# said, not removed - it is a system-wide GPU setting and may be wanted.
if systemctl is-enabled supergfxd.service &>/dev/null; then
  echo "${WARN} supergfxd is enabled. With asusctl 6.x it undoes Eco/Integrated mode at every boot." | tee -a "$LOG"
  echo "${NOTE} To remove it: ${MAGENTA}sudo systemctl disable --now supergfxd && sudo pacman -Rns supergfxctl && sudo rm -f /etc/modprobe.d/supergfxd.conf${RESET}" | tee -a "$LOG"
fi

printf "\n%.0s" {1..2}
