#!/bin/bash
# Nvidia Stuffs #

nvidia_pkg=(
  nvidia-dkms
  nvidia-settings
  nvidia-utils
  libva
  libva-nvidia-driver
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
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_nvidia.log"


# nvidia stuff
printf "${YELLOW} Checking for other hyprland packages and remove if any..${RESET}\n"
if pacman -Qs hyprland > /dev/null; then
  printf "${YELLOW} Hyprland detected. removing to install Hyprland from official repo...${RESET}\n"
    for hyprnvi in hyprland-git hyprland-nvidia hyprland-nvidia-git hyprland-nvidia-hidpi-git; do
    sudo pacman -R --noconfirm "$hyprnvi" 2>/dev/null | tee -a "$LOG" || true
    done
fi

# Install additional Nvidia packages
printf "${YELLOW} Installing ${SKY_BLUE}Nvidia Packages and Linux headers${RESET}...\n"
for krnl in $(cat /usr/lib/modules/*/pkgbase); do
  for NVIDIA in "${krnl}-headers" "${nvidia_pkg[@]}"; do
    install_package "$NVIDIA" "$LOG"
  done
done

# Check if the Nvidia modules are already added in mkinitcpio.conf and add if not
if grep -qE '^MODULES=.*nvidia. *nvidia_modeset.*nvidia_uvm.*nvidia_drm' /etc/mkinitcpio.conf; then
  echo "Nvidia modules already included in /etc/mkinitcpio.conf" 2>&1 | tee -a "$LOG"
else
  sudo sed -Ei 's/^(MODULES=\([^\)]*)\)/\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf 2>&1 | tee -a "$LOG"
  echo "${OK} Nvidia modules added in /etc/mkinitcpio.conf"
fi

printf "\n%.0s" {1..1}
printf "${INFO} Rebuilding ${YELLOW}Initramfs${RESET}...\n" 2>&1 | tee -a "$LOG"
sudo mkinitcpio -P 2>&1 | tee -a "$LOG"

printf "\n%.0s" {1..1}

# Additional Nvidia steps
NVEA="/etc/modprobe.d/nvidia.conf"
if [ -f "$NVEA" ]; then
  printf "${INFO} Seems like ${YELLOW}nvidia_drm modeset=1 fbdev=1${RESET} is already added in your system..moving on."
  printf "\n"
else
  printf "\n"
  printf "${YELLOW} Adding options to $NVEA..."
  sudo echo -e "options nvidia_drm modeset=1 fbdev=1" | sudo tee -a /etc/modprobe.d/nvidia.conf 2>&1 | tee -a "$LOG"
  printf "\n"
fi

# Deliberately no bootloader changes here.
#
# This used to edit /etc/default/grub and run grub-mkconfig, and separately
# rewrite the `options` line of every systemd-boot loader entry, to add
# nvidia-drm.modeset=1 and nvidia_drm.fbdev=1 to the kernel command line.
#
# Both were redundant: /etc/modprobe.d/nvidia.conf above sets exactly those two
# options, the module reads them when it loads, and that works the same under
# every bootloader - grub, systemd-boot, limine, rEFInd or a UKI. The kernel
# command line added nothing the module was not already being told.
#
# They were also the riskiest thing in this repo. Rewriting a loader entry's
# options line means a bad quote or an unescaped character leaves a machine
# that does not boot and cannot be fixed from the desktop that failed to come
# up - for a setting that was already applied by other means. An installer has
# no business touching the bootloader, so it no longer does.

printf "\n%.0s" {1..2} 