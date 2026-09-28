#!/bin/bash
# Nvidia Stuffs #
#
# Exits non-zero when it cannot leave a working NVIDIA kernel module behind for
# every installed kernel. install.sh keys the nouveau blacklist off that, so a
# failed driver never ends with nouveau switched off as well - which was the
# one outcome worse than doing nothing: a reboot into no GPU driver at all. When
# NO kernel got a module, the failure path also masks nvidia-utils' own nouveau
# blacklist, which would otherwise do exactly that (see nouveau_pkg_blacklists).
# When only some did, that blacklist stays, so those kernels keep nvidia.

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

# nvidia-utils ships /usr/lib/modprobe.d/nvidia-utils.conf, and the 580xx branch
# nvidia-580xx-utils.conf, and both start with "blacklist nouveau". Every path
# below installs one of them (the dkms and prebuilt module packages depend on
# it, and the nvidia_pkg loop installs it by name), and mkinitcpio's modconf hook
# copies it into the initramfs. So "nouveau is not blacklisted" was never true
# once this script had run: the package had already done it. A same-named file
# in /etc/modprobe.d overrides the /usr/lib one, and a symlink to /dev/null is
# kmod's way of masking it - the only form of that file this script creates or
# removes.
nouveau_pkg_blacklists=(nvidia-utils.conf nvidia-580xx-utils.conf)
is_our_mask() { [ -L "/etc/modprobe.d/$1" ] && [ "$(readlink "/etc/modprobe.d/$1")" = /dev/null ]; }

# Take the masks back out, so the package's "blacklist nouveau" applies again.
# Only a symlink to /dev/null is removed. Returns 0 when it removed one, so the
# caller knows the initramfs needs rebuilding.
unmask_nouveau_pkg_blacklists() {
  local _bl _removed=1
  for _bl in "${nouveau_pkg_blacklists[@]}"; do
    is_our_mask "$_bl" || continue
    if sudo rm -f "/etc/modprobe.d/$_bl"; then
      echo "${OK} Removed the /etc/modprobe.d/$_bl mask from an earlier failed run - ${_bl%.conf} blacklists nouveau again." | tee -a "$LOG"
      _removed=0
    else
      echo "${WARN} Could not remove the /etc/modprobe.d/$_bl mask - nouveau is not blacklisted. Remove it by hand and rebuild the initramfs." | tee -a "$LOG"
    fi
  done
  return $_removed
}

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
module_missing=(); module_present=()
for i in "${!kvers[@]}"; do
  if has_module "${kvers[$i]}"; then
    module_present+=("${kbases[$i]} (${kvers[$i]})")
  else
    module_missing+=("${kbases[$i]} (${kvers[$i]})")
  fi
done
if [ ${#module_missing[@]} -ne 0 ]; then
  echo "${ERROR} No NVIDIA kernel module for: ${module_missing[*]}" | tee -a "$LOG"
  echo "${NOTE} Check the DKMS build with: dkms status   (and $LOG)" | tee -a "$LOG"
  if [ ${#module_present[@]} -eq 0 ]; then
    # No kernel has the module: give nouveau back for real. This used to print
    # "nouveau is NOT being blacklisted, so this machine still has a working GPU
    # driver" and exit - but nvidia-utils had blacklisted it already (see
    # nouveau_pkg_blacklists), so a reboot on the strength of that message came
    # up on simpledrm with no GPU driver at all. Mask the package's blacklist,
    # then rebuild so the image that boots has the mask too. Safe only because
    # no kernel can load nvidia: the mask applies to every kernel (see below).
    _masked=()
    for _bl in "${nouveau_pkg_blacklists[@]}"; do
      [ -f "/usr/lib/modprobe.d/$_bl" ] || continue
      if is_our_mask "$_bl"; then
        _masked+=("/etc/modprobe.d/$_bl")
      elif [ -e "/etc/modprobe.d/$_bl" ]; then
        # Somebody's own file of that name already overrides the package's; not ours to touch.
        echo "${WARN} /etc/modprobe.d/$_bl exists and is not a mask - leaving it as it is." | tee -a "$LOG"
      elif sudo mkdir -p /etc/modprobe.d && sudo ln -s /dev/null "/etc/modprobe.d/$_bl"; then
        echo "${OK} Masked /usr/lib/modprobe.d/$_bl (its 'blacklist nouveau') with /etc/modprobe.d/$_bl -> /dev/null." | tee -a "$LOG"
        _masked+=("/etc/modprobe.d/$_bl")
      else
        echo "${ERROR} Could not mask /usr/lib/modprobe.d/$_bl - nouveau stays blacklisted by it." | tee -a "$LOG"
      fi
    done
    if [ ${#_masked[@]} -ne 0 ]; then
      # Only a successful run of this script removes the mask. Fixing DKMS by
      # hand (dkms autoinstall, a kernel update that builds) leaves it in
      # place, and from then on nouveau loads as well and competes with nvidia
      # for the card on every boot - with the final check's modinfo test passing.
      echo "${NOTE} Once the NVIDIA module builds, re-run ${SCRIPT_DIR}/nvidia.sh: it removes this mask and adds the early-KMS modules. Left in place, the mask makes nouveau compete with nvidia for the card on every boot. (By hand: sudo rm ${_masked[*]}, then rebuild the initramfs.)" | tee -a "$LOG"
      rebuild_initramfs "$LOG" || true
    fi
  else
    # Some kernels have the module, some do not. The mask above cannot be
    # limited to one kernel, so it would hand the card to nouveau on the kernels
    # that work: nouveau is in their image through autodetect, and on a first
    # run nvidia is not, because 99-nvidia.conf below is only written once every
    # kernel has the module. A working kernel downgraded to keep a broken one on
    # nouveau. So keep the package's blacklist, and take out a mask left by an
    # earlier run in which no kernel had the module.
    if unmask_nouveau_pkg_blacklists; then
      rebuild_initramfs "$LOG" || true
    fi
  fi
  # Anything still blacklisting nouveau: the package's own file (always, when
  # some kernel has the module), an earlier run's nvidia_nouveau.sh
  # (/etc/modprobe.d/nouveau.conf, and `install nouveau /bin/true` in
  # blacklist.conf), or a file of your own. Named rather than removed - the
  # final check blocks the reboot over the missing module either way.
  _still=()
  for _f in /etc/modprobe.d/*.conf /usr/lib/modprobe.d/*.conf; do
    [ -f "$_f" ] || continue
    # A package file overridden by a same-named /etc one (the mask) is not read.
    if [ "${_f%/*}" = /usr/lib/modprobe.d ] && [ -e "/etc/modprobe.d/${_f##*/}" ]; then continue; fi
    grep -qsE '^\s*(blacklist\s+nouveau\b|install\s+nouveau\s)' "$_f" && _still+=("$_f")
  done
  if [ ${#module_present[@]} -ne 0 ]; then
    if [ ${#_still[@]} -ne 0 ]; then
      echo "${WARN} No driver for the NVIDIA card on ${module_missing[*]}: nouveau is blacklisted by ${_still[*]}." | tee -a "$LOG"
      echo "${NOTE} Left that way on purpose: unblacklisting nouveau would make it take the card on ${module_present[*]} as well, where the NVIDIA module works. Boot ${module_present[*]} until the module builds, then re-run ${SCRIPT_DIR}/nvidia.sh." | tee -a "$LOG"
    else
      echo "${WARN} Nothing blacklists nouveau: ${module_missing[*]} falls back to it, but on ${module_present[*]} nouveau and nvidia both load and race for the card." | tee -a "$LOG"
    fi
  elif [ ${#_still[@]} -eq 0 ]; then
    echo "${NOTE} nouveau is not blacklisted, so this machine still has a GPU driver on every kernel." | tee -a "$LOG"
  else
    echo "${WARN} nouveau is still blacklisted by: ${_still[*]}" | tee -a "$LOG"
    echo "${NOTE} Until the NVIDIA module builds, a kernel without it boots with no GPU driver. Remove those lines and rebuild the initramfs to use nouveau meanwhile." | tee -a "$LOG"
  fi
  exit 1
fi
echo "${OK} NVIDIA kernel module present for every installed kernel." | tee -a "$LOG"

# The driver works, so a mask left by an earlier failed run (above) has to go:
# with it, nouveau and nvidia both load and race for the card. The initramfs
# rebuild below (or nvidia_nouveau.sh's, when nouveau is selected) then puts the
# package's blacklist back into the image.
unmask_nouveau_pkg_blacklists || true

# ------------------------------------------------------------ early KMS
# A drop-in rather than a sed on /etc/mkinitcpio.conf. The sed silently did
# nothing when MODULES was not a single-line `MODULES=(...)`, and a MODULES=
# in /etc/mkinitcpio.conf.d/ overrides the main file anyway - the script
# printed "added" in both cases. `+=` appends to whatever the main file and the
# earlier drop-ins set, and the effective list is verified afterwards.
nv_modules=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)

# mkinitcpio skips /etc/mkinitcpio.conf.d entirely when it is given `-c <file>`,
# which is what a preset with an uncommented ALL_config= / default_config= /
# fallback_config= does. A drop-in would then "pass" the check below while the
# image got nothing. So: if any preset names its own config file, edit those
# files instead (and verify each one on its own).
custom_confs=$(sed -nE 's/^\s*[A-Za-z_]*config=["\x27]?([^"\x27 ]+)["\x27]?.*/\1/p' /etc/mkinitcpio.d/*.preset 2>/dev/null | sort -u)

effective_modules() {
  # $1: a config file used on its own (-c), or empty for the default layout.
  if [ -n "$1" ]; then
    bash -c 'source "$1" 2>/dev/null; printf "%s\n" "${MODULES[@]}"' _ "$1" 2>/dev/null
  else
    bash -c 'source /etc/mkinitcpio.conf 2>/dev/null
             for f in /etc/mkinitcpio.conf.d/*.conf; do [ -f "$f" ] && source "$f"; done
             printf "%s\n" "${MODULES[@]}"' 2>/dev/null
  fi
}
modules_present() {
  local have; have=$(effective_modules "${1:-}")
  for m in "${nv_modules[@]}"; do grep -qx "$m" <<< "$have" || return 1; done
}

if [ -z "$custom_confs" ]; then
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
else
  for _conf in $custom_confs; do
    if modules_present "$_conf"; then
      echo "Nvidia modules already in MODULES of $_conf" 2>&1 | tee -a "$LOG"
      continue
    fi
    # Presets pass this file with -c, so drop-ins do not apply; append to its
    # own single-line MODULES=(...) and check that it took.
    sudo sed -Ei "s/^(MODULES=\([^)]*)\)/\1 ${nv_modules[*]})/" "$_conf" 2>&1 | tee -a "$LOG"
    if modules_present "$_conf"; then
      echo "${OK} Nvidia modules added to $_conf (a preset uses it with -c, so drop-ins are ignored)" | tee -a "$LOG"
    else
      echo "${WARN} Could not add the Nvidia modules to $_conf - add them to its MODULES by hand for early KMS." | tee -a "$LOG"
    fi
  done
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
