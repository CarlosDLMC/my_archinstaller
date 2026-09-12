#!/bin/bash
# CPU microcode

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "${ERROR} Failed to change directory to $PARENT_DIR"; exit 1; }

if ! source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_ucode.log"

# Why this exists
#
# Nothing in this repo installed microcode until now, and the omission is
# completely invisible from the desktop: the CPU simply keeps running whatever
# revision the board's firmware supplied, everything boots, and the only trace
# is a *missing* "microcode updated early" line in the boot log. What you lose
# is every erratum and side-channel mitigation the vendor shipped after the
# board's last BIOS release - which on a laptop that stopped getting firmware
# updates is years of them.
#
# The vendor is read from /proc/cpuinfo rather than asked. A prompt here could
# only be answered wrong; the CPU already knows what it is.

case "$(grep -m1 '^vendor_id' /proc/cpuinfo)" in
  *AuthenticAMD*) ucode_pkg="amd-ucode";   vendor="AMD" ;;
  *GenuineIntel*) ucode_pkg="intel-ucode"; vendor="Intel" ;;
  *)
    printf "\n${WARN} Unrecognised CPU vendor - no microcode package to install.\n" | tee -a "$LOG"
    printf "\n%.0s" {1..2}
    exit 0
    ;;
esac

printf "\n${NOTE} Detected ${SKY_BLUE}${vendor}${RESET} CPU - installing ${SKY_BLUE}${ucode_pkg}${RESET}...\n" | tee -a "$LOG"
install_package "$ucode_pkg" "$LOG"

if ! pacman -Qi "$ucode_pkg" &>/dev/null; then
  printf "${WARN} ${ucode_pkg} did not install. Skipping bootloader wiring.\n" | tee -a "$LOG"
  printf "\n%.0s" {1..2}
  exit 0
fi

# The package on its own updates nothing. The microcode image has to be loaded
# by the bootloader as an *extra initrd, ahead of the real one*, or the kernel
# never sees it - which is the same silent no-op as not installing it at all.
#
# Every test against /boot goes through sudo. The ESP is routinely mounted
# root-only (fmask=0077), so a plain [ -f ] or a *.conf glob is evaluated by
# the unprivileged shell, finds nothing, and reports success - a false OK is
# the one outcome worse than a warning here.
ucode_img=$(pacman -Qlq "$ucode_pkg" | grep -m1 'ucode\.img$')
if [ -z "$ucode_img" ] || ! sudo test -f "$ucode_img"; then
  printf "${WARN} Could not find the microcode image from ${ucode_pkg}.\n" | tee -a "$LOG"
  printf "\n%.0s" {1..2}
  exit 0
fi
printf "${OK} Microcode image: ${MAGENTA}${ucode_img}${RESET}\n" | tee -a "$LOG"

# mkinitcpio's `microcode` hook, which Arch has shipped in the default HOOKS
# since 2024, builds the image into the main initramfs as an early uncompressed
# CPIO section. The bootloader then needs no separate initrd line at all, and
# the pacman hook regenerates the initramfs when the ucode package lands, so it
# is already done by the time we get here.
#
# This is checked first and on purpose. Telling someone to hand-edit a boot
# entry that is already correct is a good way to end up with a boot entry that
# is not - which is the exact failure this script is written to avoid.
#
# find, not a glob: an empty conf.d would leave the pattern unexpanded and
# grep -s would swallow it, turning "I could not check" into "not enabled".
microcode_hook=false
while IFS= read -r conf; do
  [ -n "$conf" ] || continue
  if grep -qsE '^HOOKS=.*[ (]microcode[ )]' "$conf"; then microcode_hook=true; break; fi
done <<< "$(printf '/etc/mkinitcpio.conf\n'; find /etc/mkinitcpio.conf.d -maxdepth 1 -name '*.conf' 2>/dev/null)"

if [ "$microcode_hook" == "true" ]; then
  printf "${OK} mkinitcpio's ${MAGENTA}microcode${RESET} hook is enabled, so the image is built\n" | tee -a "$LOG"
  printf "${OK} into the initramfs - no bootloader change is needed.\n" | tee -a "$LOG"

elif command -v bootctl &>/dev/null && sudo test -d /boot/loader/entries; then
  # systemd-boot Type #1 entries are edited by hand, and this script will not
  # do it for you. A malformed loader entry is an unbootable machine that
  # cannot be repaired from the desktop that failed to come up, which is a far
  # worse outcome than a missing microcode update. So: report precisely, and
  # let the user make a two-word edit with the machine still running.
  img_name="${ucode_img##*/}"
  # find, not a glob, and run as root - see the note above. -maxdepth 1 with an
  # explicit *.conf keeps backups like arch.conf.bak out of the report, so the
  # user is never told to edit a file the bootloader does not read.
  missing=""
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    sudo grep -qs "initrd.*${img_name}" "$entry" || missing="$missing $entry"
  done <<< "$(sudo find /boot/loader/entries -maxdepth 1 -name '*.conf' 2>/dev/null)"
  if [ -z "$missing" ]; then
    printf "${OK} systemd-boot entries already load ${MAGENTA}${img_name}${RESET}.\n" | tee -a "$LOG"
  else
    printf "\n${WARN} systemd-boot entries are NOT loading the microcode:\n" | tee -a "$LOG"
    printf "${WARN}   %s\n" $missing | tee -a "$LOG"
    printf "${NOTE} Add this line to each, ${YELLOW}above${RESET} the existing 'initrd' line:\n" | tee -a "$LOG"
    printf "${NOTE}   ${MAGENTA}initrd /${img_name}${RESET}\n" | tee -a "$LOG"
    printf "${NOTE} Order matters - the microcode initrd must come first.\n" | tee -a "$LOG"
  fi

elif sudo test -f /boot/limine.conf || sudo test -f /boot/limine.cfg; then
  # Limine, also report-only. Its entries take the microcode as a module listed
  # before the initramfs one; order matters the same way it does everywhere.
  img_name="${ucode_img##*/}"
  printf "\n${NOTE} ${SKY_BLUE}Limine${RESET} detected. Make sure each boot entry loads the microcode\n" | tee -a "$LOG"
  printf "${NOTE} ${YELLOW}above${RESET} the initramfs module:\n" | tee -a "$LOG"
  printf "${NOTE}   ${MAGENTA}module_path: boot():/${img_name}${RESET}\n" | tee -a "$LOG"
  printf "${NOTE} If limine-mkinitcpio-hook or limine-entry-tool generates your entries,\n" | tee -a "$LOG"
  printf "${NOTE} they already handle this and there is nothing to do.\n" | tee -a "$LOG"

else
  printf "${NOTE} Bootloader not recognised (rEFInd, a UKI, something else?).\n" | tee -a "$LOG"
  printf "${NOTE} Make sure it loads ${MAGENTA}${ucode_img##*/}${RESET} as an initrd before the\n" | tee -a "$LOG"
  printf "${NOTE} main one, or the microcode update will not apply.\n" | tee -a "$LOG"
fi

printf "\n${NOTE} After rebooting, confirm with: ${MAGENTA}journalctl -k -b | grep microcode${RESET}\n"
printf "${NOTE} A working setup reports ${SKY_BLUE}'microcode updated early'${RESET}.\n"
printf "\n%.0s" {1..2}
