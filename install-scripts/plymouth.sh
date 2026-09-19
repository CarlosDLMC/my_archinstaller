#!/bin/bash
# Plymouth boot splash - the repo logo instead of the distro's.
#
# CachyOS ships plymouth with its "cachyos" theme, which keeps the motherboard's
# firmware logo (ACPI BGRT) as the background and stamps a CachyOS watermark at
# the bottom. This installs a theme that paints black and shows the repo's own
# boot logo, icons/gopnik-watermark.png, instead, with the stock spinner and
# the LUKS password prompt underneath. Disable "Boot Logo Display" in the BIOS and
# the vendor logo is gone for good, without touching the firmware.
#
# Only the theme is shipped. The spinner frames and the dialog artwork
# (entry.png, lock.png, keyboard.png...) are copied at install time from
# plymouth's own "spinner" theme, which every plymouth package carries, so the
# repo does not have to vendor GPL artwork and stays in step with the installed
# plymouth version.
#
# The preset default is plymouth="auto": act only where plymouth is already
# installed AND already in the mkinitcpio HOOKS, i.e. a distro that set it up
# (CachyOS). Nothing here edits HOOKS or the kernel command line - `splash` on
# the cmdline lives in the bootloader entry, and this repo never writes to a
# bootloader (see the 03b313a commit). plymouth="ON" forces the theme onto a
# machine without plymouth: the package is installed and the theme set, and the
# two remaining steps are printed for you to do by hand.

THEME="soviet"
SRC_DIR="assets/plymouth/$THEME"
# The picture itself lives with the other logos in icons/, next to LOGO.JPG,
# so the firmware logo and the boot splash are picked from one place. It is
# installed as the theme's watermark.png, the name the two-step module reads.
WATERMARK="icons/gopnik-watermark.png"
DEST_DIR="/usr/share/plymouth/themes/$THEME"
SPINNER_DIR="/usr/share/plymouth/themes/spinner"

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "${ERROR} Failed to change directory to $PARENT_DIR"; exit 1; }

if ! source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_plymouth.log"

printf "\n%s - Installing the ${SKY_BLUE}Plymouth boot splash${RESET} theme \n" "${NOTE}"

install_package plymouth "$LOG"
if ! pacman -Qi plymouth &>/dev/null; then
  echo "${ERROR} plymouth did not install. Skipping the theme." | tee -a "$LOG"
  exit 1
fi

if [ ! -d "$SPINNER_DIR" ]; then
  echo "${ERROR} $SPINNER_DIR is missing - this plymouth build has no spinner theme to borrow artwork from." | tee -a "$LOG"
  exit 1
fi

# Theme files: ours on top of the spinner theme's frames and dialog artwork.
# -n on the spinner copy so our watermark.png is never replaced by theirs.
sudo mkdir -p "$DEST_DIR"
sudo cp "$SRC_DIR/$THEME.plymouth" "$DEST_DIR/" 2>&1 | tee -a "$LOG"
sudo cp "$WATERMARK" "$DEST_DIR/watermark.png" 2>&1 | tee -a "$LOG"
sudo find "$SPINNER_DIR" -maxdepth 1 -name '*.png' ! -name 'watermark.png' \
  -exec cp -n {} "$DEST_DIR/" \; 2>&1 | tee -a "$LOG"
sudo chmod 644 "$DEST_DIR"/* 2>&1 | tee -a "$LOG"

# -R rewrites /etc/plymouth/plymouthd.conf and regenerates every initramfs
# (mkinitcpio -P). On CachyOS the limine-mkinitcpio-hook then refreshes the
# boot entries on its own. This is the slow step.
echo "${NOTE} Setting ${SKY_BLUE}$THEME${RESET} as the default theme and rebuilding the initramfs..." | tee -a "$LOG"
if sudo plymouth-set-default-theme -R "$THEME" >> "$LOG" 2>&1; then
  echo "${OK} plymouth theme is now $(plymouth-set-default-theme)." | tee -a "$LOG"
else
  echo "${ERROR} plymouth-set-default-theme -R failed - see $LOG" | tee -a "$LOG"
  exit 1
fi

# Report-only: what the splash needs from files this repo does not write.
hooks_have_plymouth=false
while IFS= read -r conf; do
  [ -n "$conf" ] || continue
  if grep -qsE '^HOOKS=.*[ (]plymouth[ )]' "$conf"; then hooks_have_plymouth=true; break; fi
done <<< "$(printf '/etc/mkinitcpio.conf\n'; find /etc/mkinitcpio.conf.d -maxdepth 1 -name '*.conf' 2>/dev/null)"
if [ "$hooks_have_plymouth" != "true" ]; then
  echo "${WARN} 'plymouth' is not in HOOKS (/etc/mkinitcpio.conf or /etc/mkinitcpio.conf.d/*.conf). Add it after 'systemd' (or after 'base udev'), then run: sudo mkinitcpio -P" | tee -a "$LOG"
fi
if ! grep -qw splash /proc/cmdline; then
  echo "${WARN} 'splash' is not on the kernel command line, so plymouth will show text, not the logo." | tee -a "$LOG"
  echo "${NOTE} Add 'splash' (and 'quiet') to the cmdline in your bootloader entry. This repo does not edit bootloaders." | tee -a "$LOG"
fi
echo "${NOTE} To hide the motherboard's own logo as well, disable 'Boot Logo Display' in the BIOS." | tee -a "$LOG"
# /boot is root-only on CachyOS, so test through sudo or this is always false.
if sudo test -f /boot/limine.conf && ! sudo grep -q 'my_archinstaller Limine theme' /boot/limine.conf 2>/dev/null; then
  echo "${NOTE} Limine is installed and unthemed. The 'limine' preset option (install-scripts/limine.sh) applies the matching boot-menu theme; see README 'Limine boot menu theme'." | tee -a "$LOG"
fi

printf "\n%.0s" {1..1}
