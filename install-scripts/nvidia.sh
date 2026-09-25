#!/bin/bash
# Nvidia Stuffs #
#
# Exits non-zero when it cannot leave a working NVIDIA kernel module behind for
# every installed kernel. install.sh keys the nouveau blacklist off that, so a
# failed driver never ends with nouveau switched off as well - which was the
# one outcome worse than doing nothing: a reboot into no GPU driver at all.

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
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_nvidia.log"

# ------------------------------------------------------------ which driver
# nvidia-open-dkms only binds to Turing (GTX 16xx / RTX 20xx) and newer. It used
# to be installed for every NVIDIA card, so a Maxwell or Pascal machine got a
# module that never loaded. nvidia_detect.sh reads the generation from the PCI
# device ID; see that file for the ranges.
tier=$("$SCRIPT_DIR/nvidia_detect.sh")
case "$tier" in
  open)
    dkms_pkg="nvidia-open-dkms"
    # lib32-nvidia-utils: graphics.sh installs the 32-bit Mesa/Vulkan stack for
    # Steam and wine and leaves NVIDIA to this script, which never installed
    # the 32-bit half - 32-bit GL and Vulkan had no driver on an NVIDIA-only box.
    nvidia_pkg=(nvidia-utils lib32-nvidia-utils nvidia-settings libva libva-nvidia-driver)
    ;;
  580xx)
    # Maxwell, Pascal and Volta: NVIDIA's 580 branch is the last to support
    # them, and it lives in the AUR. (470xx is Kepler, 390xx is Fermi.)
    echo "${NOTE} Pre-Turing NVIDIA GPU: using the legacy ${SKY_BLUE}580xx${RESET} driver branch (AUR)." | tee -a "$LOG"
    dkms_pkg="nvidia-580xx-dkms"
    nvidia_pkg=(nvidia-580xx-utils lib32-nvidia-580xx-utils nvidia-580xx-settings libva libva-nvidia-driver)
    ;;
  unsupported)
    echo "${WARN} This NVIDIA GPU is Kepler or older: no maintained proprietary driver supports it." | tee -a "$LOG"
    echo "${NOTE} Keeping nouveau. nvidia-470xx-dkms / nvidia-390xx-dkms (AUR) are the manual route." | tee -a "$LOG"
    exit 1
    ;;
  *)
    echo "${NOTE} No NVIDIA display controller found - nothing to do." | tee -a "$LOG"
    exit 1
    ;;
esac

# Obsolete NVIDIA-specific Hyprland forks. hyprland-git is deliberately NOT in
# this list any more: it is not an NVIDIA fork, and when it was the Hyprland
# that satisfied hyprland.sh (which then installed nothing) removing it here
# left the machine with no Hyprland at all.
_removed_fork=false
for hyprnvi in hyprland-nvidia hyprland-nvidia-git hyprland-nvidia-hidpi-git; do
  if pacman -Q "$hyprnvi" &>/dev/null; then
    printf "${YELLOW} Removing obsolete ${hyprnvi}...${RESET}\n"
    sudo pacman -R --noconfirm "$hyprnvi" 2>&1 | tee -a "$LOG" || true
    _removed_fork=true
  fi
done
if [ "$_removed_fork" = true ] && ! pacman -Q hyprland &>/dev/null && ! pacman -Q hyprland-git &>/dev/null; then
  install_package hyprland "$LOG"
fi

# ------------------------------------------------------------ kernel modules
# Installed kernels: a /usr/lib/modules/<kver>/ whose vmlinuz a package owns.
# Not every directory with a pkgbase file - hooks that keep the running kernel's
# modules loadable across an upgrade (kernel-modules-hook and friends) leave old
# <kver>/ directories behind, pkgbase included, for kernels no longer installed.
kvers=(); kbases=()
for _moddir in /usr/lib/modules/*/; do
  [ -f "$_moddir/pkgbase" ] || continue
  pacman -Qqo "${_moddir}vmlinuz" &>/dev/null || continue
  kvers+=("$(basename "$_moddir")")
  kbases+=("$(cat "$_moddir/pkgbase")")
done

# A prebuilt module package may already be installed. CachyOS's installer
# (chwd) puts `linux-cachyos-nvidia-open` on NVIDIA machines; it provides
# NVIDIA-MODULE, and the dkms packages conflict with that, so under --noconfirm
# pacman refuses the swap. Find which package it is.
prebuilt=""
if pacman -T NVIDIA-MODULE >/dev/null 2>&1; then
  for _p in $(pacman -Qqs nvidia 2>/dev/null || true); do
    [ "$_p" = "$dkms_pkg" ] && continue
    if LC_ALL=C pacman -Qi "$_p" 2>/dev/null | grep -qE '^Provides *:.*NVIDIA-MODULE'; then
      prebuilt="$_p"; break
    fi
  done
fi

has_module() { modinfo -k "$1" -n nvidia &>/dev/null; }

printf "${YELLOW} Installing ${SKY_BLUE}Nvidia Packages${RESET}...\n"
if [ -n "$prebuilt" ]; then
  echo "${NOTE} NVIDIA kernel module already installed (${SKY_BLUE}${prebuilt}${RESET}); keeping it, not installing ${dkms_pkg}." | tee -a "$LOG"
  # That package covers ONE kernel. This used to be decided once for all of
  # them, so a second kernel (linux-cachyos-lts, the one you would boot to
  # recover) got no module and nouveau blacklisted. For every kernel without a
  # module, install the same flavour of prebuilt package for it: the prebuilt
  # name is "<pkgbase>-<suffix>", e.g. linux-cachyos-nvidia-open.
  # The LONGEST kernel name that prefixes it: with linux-cachyos and
  # linux-cachyos-lts both installed, linux-cachyos-lts-nvidia-open also starts
  # with "linux-cachyos-", and the first match would make the suffix
  # "lts-nvidia-open".
  suffix="" _best=""
  for _kb in "${kbases[@]}"; do
    if [[ "$prebuilt" == "$_kb-"* ]] && [ ${#_kb} -gt ${#_best} ]; then
      _best="$_kb"; suffix="${prebuilt#"$_kb"-}"
    fi
  done
  for i in "${!kvers[@]}"; do
    has_module "${kvers[$i]}" && continue
    _want="${kbases[$i]}-${suffix}"
    if [ -n "$suffix" ] && pacman -Si "$_want" &>/dev/null; then
      install_package "$_want" "$LOG"
    else
      echo "${ERROR} Kernel ${kbases[$i]} (${kvers[$i]}) has no NVIDIA module, and there is no prebuilt ${_want:-package} for it." | tee -a "$LOG"
      echo "${NOTE} ${dkms_pkg} would conflict with ${prebuilt}, so this needs a decision by hand." | tee -a "$LOG"
    fi
  done
else
  # Headers FIRST, so the dkms package's own install hook builds the module for
  # every kernel in one go.
  for _kb in "${kbases[@]}"; do
    install_package "${_kb}-headers" "$LOG"
  done
  install_package "$dkms_pkg" "$LOG"
fi

for NVIDIA in "${nvidia_pkg[@]}"; do
  install_package "$NVIDIA" "$LOG"
done

# "Package installed" is not "module built": when the DKMS build fails inside
# pacman's hook (a brand-new kernel, a headers mismatch) the dkms package still
# counts as installed, and the old script carried on to blacklist nouveau and
# let the preset reboot into no GPU driver. Check the module itself, per kernel.
module_missing=()
for i in "${!kvers[@]}"; do
  has_module "${kvers[$i]}" || module_missing+=("${kbases[$i]} (${kvers[$i]})")
done
if [ ${#module_missing[@]} -ne 0 ]; then
  echo "${ERROR} No NVIDIA kernel module for: ${module_missing[*]}" | tee -a "$LOG"
  echo "${NOTE} Check the DKMS build with: dkms status   (and $LOG)" | tee -a "$LOG"
  echo "${NOTE} nouveau is NOT being blacklisted, so this machine still has a working GPU driver." | tee -a "$LOG"
  exit 1
fi
echo "${OK} NVIDIA kernel module present for every installed kernel." | tee -a "$LOG"

# ------------------------------------------------------------ early KMS
# A drop-in rather than a sed on /etc/mkinitcpio.conf. The sed silently did
# nothing when MODULES was not a single-line `MODULES=(...)`, and a MODULES=
# in /etc/mkinitcpio.conf.d/ overrides the main file anyway - the script
# printed "added" in both cases. `+=` appends to whatever the main file and the
# earlier drop-ins set, and the effective list is verified afterwards.
nv_modules=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
effective_modules() {
  bash -c 'source /etc/mkinitcpio.conf 2>/dev/null
           for f in /etc/mkinitcpio.conf.d/*.conf; do [ -f "$f" ] && source "$f"; done
           printf "%s\n" "${MODULES[@]}"' 2>/dev/null
}
modules_present() {
  local have; have=$(effective_modules)
  for m in "${nv_modules[@]}"; do grep -qx "$m" <<< "$have" || return 1; done
}
if modules_present; then
  echo "Nvidia modules already in the initramfs MODULES" 2>&1 | tee -a "$LOG"
else
  sudo mkdir -p /etc/mkinitcpio.conf.d
  echo "MODULES+=(${nv_modules[*]})" | sudo tee /etc/mkinitcpio.conf.d/99-nvidia.conf >/dev/null
  if modules_present; then
    echo "${OK} Nvidia modules added via /etc/mkinitcpio.conf.d/99-nvidia.conf" | tee -a "$LOG"
  else
    echo "${WARN} Could not get the Nvidia modules into MODULES - they will load later instead of in the initramfs." | tee -a "$LOG"
  fi
fi

# Additional Nvidia steps
NVEA="/etc/modprobe.d/nvidia.conf"
# Look for the option itself, in any modprobe.d file, not for the file name.
# CachyOS's chwd NVIDIA profile drops its own files under /etc/modprobe.d, and
# one called nvidia.conf that does not carry modeset=1 used to be taken as
# "already done" - Hyprland then started without DRM modeset.
if grep -qsE '^\s*options\s+nvidia[_-]drm\s.*modeset=1' /etc/modprobe.d/*.conf; then
  printf "${INFO} ${YELLOW}nvidia_drm modeset=1${RESET} is already set in /etc/modprobe.d..moving on."
  printf "\n"
else
  printf "\n"
  printf "${YELLOW} Adding options to $NVEA..."
  echo "options nvidia_drm modeset=1 fbdev=1" | sudo tee -a "$NVEA" 2>&1 | tee -a "$LOG"
  printf "\n"
fi

# The initramfs is rebuilt by nvidia_nouveau.sh when nouveau is being
# blacklisted, so that one rebuild picks up the modules, the modprobe options
# AND the blacklist. Rebuilding here as well used to bake an image with the
# blacklist missing. Without nouveau in the selection, rebuild here.
if [[ " ${INSTALL_SELECTED_OPTIONS:-} " != *" nouveau "* ]]; then
  rebuild_initramfs "$LOG" || true
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
