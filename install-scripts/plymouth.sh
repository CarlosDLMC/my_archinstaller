#!/bin/bash
# Plymouth boot splash - the repo logo instead of the distro's.
#
# CachyOS ships plymouth with its "cachyos" theme, which keeps the motherboard's
# firmware logo (ACPI BGRT) as the background and stamps a CachyOS watermark at
# the bottom. This installs a theme that paints black and shows the repo's own
# boot logo from icons/ instead, with the stock spinner and the LUKS password
# prompt underneath. Disable "Boot Logo Display" in the BIOS and
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
# The picture lives with the other logos in icons/, next to LOGO.JPG, so the
# firmware logo and the boot splash come from one place. Plymouth draws the
# watermark at its native pixel size - only the anchor in soviet.plymouth is a
# fraction of the screen - so there is one cut per panel height and the right
# one is installed as watermark.png, the name the two-step module reads. All
# three are downscales of icons/aisaka.icon (1920x1920), cut so the bottom
# edge clears the password prompt by ~35 px at that height.
WATERMARK_1080="icons/gopnik-watermark-1080p.png"   # 468x620
WATERMARK_1440="icons/gopnik-watermark-1440p.png"   # 649x860, the fallback
WATERMARK_2160="icons/gopnik-watermark-2160p.png"   # 1011x1340
DEST_DIR="/usr/share/plymouth/themes/$THEME"
SPINNER_DIR="/usr/share/plymouth/themes/spinner"

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "[ERROR] Failed to change directory to $PARENT_DIR"; exit 1; }

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

# Which cut fits this machine. The preferred (first) mode of every connected
# DRM connector is the panel's native resolution, and it is readable from
# sysfs with no compositor running - this script runs in a TTY as often as not,
# so hyprctl/wlr-randr are no help. The *smallest* connected panel decides:
# plymouth paints the same image on every display, so a cut sized for the big
# screen of a mixed pair would land on the password prompt on the small one.
# Sets WATERMARK and SCREEN_H. It assigns rather than echoes: $(...) would run
# it in a subshell and SCREEN_H would never come back.
pick_watermark() {
  local modes conn h smallest=0
  for modes in /sys/class/drm/card*-*/modes; do
    [ -r "$modes" ] || continue
    conn="${modes%/modes}"
    [ "$(cat "$conn/status" 2>/dev/null)" = "connected" ] || continue
    h=$(head -1 "$modes" | cut -d x -f2 | tr -cd '0-9')
    [ -n "$h" ] || continue
    if [ "$smallest" -eq 0 ] || [ "$h" -lt "$smallest" ]; then smallest=$h; fi
  done
  SCREEN_H="$smallest"
  if   [ "$smallest" -ge 2160 ]; then WATERMARK="$WATERMARK_2160"
  elif [ "$smallest" -ge 1440 ]; then WATERMARK="$WATERMARK_1440"
  elif [ "$smallest" -gt 0 ];    then WATERMARK="$WATERMARK_1080"
  else                                WATERMARK="$WATERMARK_1440"
  fi
}

pick_watermark
if [ "$SCREEN_H" -eq 0 ]; then
  echo "${WARN} No connected DRM connector reported a mode - falling back to $(basename "$WATERMARK"). If the logo overlaps the password prompt, copy another icons/gopnik-watermark-*.png over $DEST_DIR/watermark.png by hand." | tee -a "$LOG"
elif [ "$SCREEN_H" -lt 1000 ]; then
  echo "${WARN} The smallest connected panel is only ${SCREEN_H} px tall - even the 620 px cut will crowd the password prompt. Re-render it shorter from icons/aisaka.icon if that bothers you." | tee -a "$LOG"
else
  echo "${NOTE} Smallest connected panel is ${SCREEN_H} px - using ${SKY_BLUE}$(basename "$WATERMARK")${RESET}." | tee -a "$LOG"
fi
# A 4K panel small enough to be HiDPI (plymouth's own guess: roughly >192 dpi)
# makes plymouth double everything, which halves the logical screen and makes
# the 1080p cut the right one. Override plymouth's guess on the kernel command
# line with plymouth.force-scale=1 if the 4K cut comes out twice the size.

# Theme files: ours on top of the spinner theme's frames and dialog artwork.
# -n on the spinner copy so our watermark.png is never replaced by theirs.
# Each copy's status is checked through PIPESTATUS: `cmd | tee` reports tee's,
# so a missing watermark used to pass silently, the theme was still selected,
# and the splash booted with no logo while the final check (which only reads the
# theme name) passed.
sudo mkdir -p "$DEST_DIR"
sudo cp "$SRC_DIR/$THEME.plymouth" "$DEST_DIR/" 2>&1 | tee -a "$LOG"
_cp_theme=${PIPESTATUS[0]}
sudo cp "$WATERMARK" "$DEST_DIR/watermark.png" 2>&1 | tee -a "$LOG"
_cp_mark=${PIPESTATUS[0]}
if [ "$_cp_theme" -ne 0 ] || [ "$_cp_mark" -ne 0 ]; then
  echo "${ERROR} Could not copy the theme files into $DEST_DIR - leaving the current splash theme selected. See $LOG" | tee -a "$LOG"
  record_package_failure "plymouth-theme-$THEME"
  exit 1
fi
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
mkinitcpio_has_hook plymouth && hooks_have_plymouth=true
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
