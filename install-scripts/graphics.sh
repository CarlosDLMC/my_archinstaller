#!/bin/bash
# Vendor-specific GPU userspace: VA-API video decode and Vulkan drivers.
#
# mesa alone gives you a working desktop, which is why this was easy to miss:
# nothing looks broken without these. What you lose is hardware video decode
# (so mpv, LibreWolf and any browser fall back to the CPU - hot laptop, short
# battery) and Vulkan. The 32-bit variants are here because multilib is enabled
# by pacman.sh and Steam/wine/32-bit games need them.
#
# NVIDIA is deliberately not handled here - nvidia.sh owns that, and it is
# gated behind the preset's nvidia/nouveau options.

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "${ERROR} Failed to change directory to $PARENT_DIR"; exit 1; }

if ! source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_graphics.log"

gpu_info=$(lspci -nn 2>/dev/null | grep -iE 'vga|3d controller|display controller')

# Common to every vendor. lib32-mesa is the 32-bit OpenGL stack: multilib is
# enabled by pacman.sh, and without it 32-bit games and wine fall back to
# software rendering.
graphics=(
  mesa
  lib32-mesa
  libva-utils      # vainfo, so the check below can actually verify decode works
  vulkan-icd-loader
  lib32-vulkan-icd-loader
)
base_count=${#graphics[@]}

if grep -qi 'intel' <<< "$gpu_info"; then
  printf "\n${NOTE} Detected ${SKY_BLUE}Intel${RESET} graphics\n" | tee -a "$LOG"
  # intel-media-driver covers Broadwell/Gen9 and newer (this machine's UHD 620
  # included). libva-intel-driver is the legacy path for pre-Broadwell parts.
  graphics+=(intel-media-driver vulkan-intel lib32-vulkan-intel)
fi

if grep -qiE 'amd|radeon|advanced micro devices' <<< "$gpu_info"; then
  printf "\n${NOTE} Detected ${SKY_BLUE}AMD${RESET} graphics\n" | tee -a "$LOG"
  # No libva-mesa-driver here: it was merged into mesa, which is installed
  # above. Asking for the old name now fails the install.
  graphics+=(vulkan-radeon lib32-vulkan-radeon)
fi

if [ ${#graphics[@]} -eq "$base_count" ]; then
  printf "\n${WARN} No Intel or AMD GPU detected. Installing loaders only.\n" | tee -a "$LOG"
  printf "${NOTE} If this is an NVIDIA machine, enable 'nvidia' in the preset.\n" | tee -a "$LOG"
fi

printf "\n${NOTE} Installing ${SKY_BLUE}graphics drivers${RESET}...\n"
for PKG in "${graphics[@]}"; do
  install_package "$PKG" "$LOG"
done

# Verify hardware decode actually came up, rather than trusting the install.
# A missing driver here is silent at runtime - you only notice the fan.
if command -v vainfo &>/dev/null; then
  if vainfo &>/dev/null; then
    printf "${OK} VA-API hardware video decode is working.\n" | tee -a "$LOG"
  else
    printf "${WARN} VA-API is not working. Video will decode on the CPU.\n" | tee -a "$LOG"
    printf "${NOTE} Run 'vainfo' after reboot - a driver may need the new kernel.\n" | tee -a "$LOG"
  fi
fi

printf "\n%.0s" {1..2}
