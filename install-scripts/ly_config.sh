#!/bin/bash
# Configure ly display manager

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
# Determine the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Change the working directory to the parent directory of the script
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || exit 1

source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"

# Set the name of the log file to include the current date and time
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_ly_config.log"

printf "${NOTE} Configuring ly display manager...\n"

# Copy ly configuration files
printf "${NOTE} Installing ly configuration...\n"
# `install`, checked: config.ini points ly at every one of these files, so a
# missing one used to give a login screen with no flag, no language and an OK.
ly_install() { # mode src dst
  local st
  # Read PIPESTATUS straight after the pipeline. It used to sit behind an
  # `if ! ... | tee; then :; fi` whose body, had tee ever failed, would have
  # reset PIPESTATUS before it was read.
  sudo install -D -m "$1" "$2" "$3" 2>&1 | tee -a "$LOG"
  st="${PIPESTATUS[0]}"
  if [ "$st" -ne 0 ]; then echo "${ERROR} Failed to install $3" | tee -a "$LOG"; exit 1; fi
}
ly_install 644 "$PARENT_DIR/assets/ly/config.ini" /etc/ly/config.ini

printf "${NOTE} Installing ly start script...\n"
ly_install 755 "$PARENT_DIR/assets/ly/start.sh" /etc/ly/start.sh

printf "${NOTE} Installing 8-bit soviet flag animation...\n"
# config.ini sets animation = dur_file and points dur_file_path here, so the
# flag has to land in /etc/ly or ly draws nothing at all. Both the waving and
# the still version are installed, so switching is a one-line config edit
# rather than a re-run of this script.
ly_install 644 "$PARENT_DIR/assets/ly/soviet-flag-animated.dur" /etc/ly/soviet-flag-animated.dur
ly_install 644 "$PARENT_DIR/assets/ly/soviet-flag-static.dur" /etc/ly/soviet-flag-static.dur

printf "${NOTE} Installing custom soviet language...\n"
ly_install 644 "$PARENT_DIR/assets/ly/lang/soviet.ini" /etc/ly/lang/soviet.ini

# Console font: scale the login screen to the panel
#
# ly is a TUI. Its box is measured in character cells, so what sets its
# apparent size is the console font, not the resolution - and the two pull in
# opposite directions. With the kernel's 8x16 default, 2560x1440 gives a
# 320x90 grid and the login box covers a small patch in the middle of the
# screen; the same box on 1920x1080 sits on a 240x67 grid and looks half again
# as large. Left alone, the login screen shrinks as the monitor improves.
#
# Both fonts below ship with kbd, which is already a dependency here (setfont
# comes from it), so this installs nothing. Both also carry Cyrillic, and that
# is not a detail: lang/soviet.ini installed above is Russian, and the kernel's
# built-in default8x16 has no Cyrillic at all - with it every prompt on the
# login screen renders as empty boxes.
#
#   >= 1440p : latarcyrheb-sun32 (16x32) -> 160x45 grid
#   otherwise: latarcyrheb-sun16 (8x16)  -> 240x67 grid at 1080p
#
# The SMALLEST connected output decides, not the largest. The failure modes are
# not symmetric: too small a font is merely cosmetic, while too large a one
# clips ly's box on the panel that has the fewest rows. So the display that
# fits least is the one that has to fit.
printf "${NOTE} Selecting the console font for the login screen...\n"

_min_h=""
for _modes in /sys/class/drm/*/modes; do
  [ -r "$_modes" ] || continue
  _conn="${_modes%/modes}"
  [ "$(cat "$_conn/status" 2>/dev/null)" = "connected" ] || continue
  # First line of modes is the preferred (native) mode, e.g. "2560x1440".
  _h=$(head -1 "$_modes" 2>/dev/null | cut -d'x' -f2 | tr -cd '0-9')
  [ -n "$_h" ] || continue
  if [ -z "$_min_h" ] || [ "$_h" -lt "$_min_h" ]; then _min_h="$_h"; fi
done
# Fallback: the framebuffer the console is actually on. Covers a machine whose
# connectors report no modes yet (and any future non-DRM console).
if [ -z "$_min_h" ] && [ -r /sys/class/graphics/fb0/virtual_size ]; then
  _min_h=$(cut -d, -f2 /sys/class/graphics/fb0/virtual_size 2>/dev/null | tr -cd '0-9')
fi

if [ -z "$_min_h" ]; then
  echo "${WARN} Could not read any display height - leaving the console font alone." | tee -a "$LOG"
else
  if [ "$_min_h" -ge 1440 ]; then
    CONSOLE_FONT="latarcyrheb-sun32"
  else
    CONSOLE_FONT="latarcyrheb-sun16"
  fi
  echo "${NOTE} Smallest connected display is ${_min_h}px tall -> ${CONSOLE_FONT}" | tee -a "$LOG"

  # vconsole.conf may not exist on a bare install, and it carries KEYMAP and the
  # XKB* lines that locales.sh/the installer set - so edit the FONT line in
  # place rather than writing the file out.
  sudo touch /etc/vconsole.conf
  if sudo grep -q '^FONT=' /etc/vconsole.conf 2>/dev/null; then
    sudo sed -i "s/^FONT=.*/FONT=$CONSOLE_FONT/" /etc/vconsole.conf 2>&1 | tee -a "$LOG"
  else
    echo "FONT=$CONSOLE_FONT" | sudo tee -a /etc/vconsole.conf >/dev/null
  fi

  if sudo grep -q "^FONT=$CONSOLE_FONT$" /etc/vconsole.conf; then
    echo "${OK} /etc/vconsole.conf sets FONT=$CONSOLE_FONT" | tee -a "$LOG"
  else
    echo "${ERROR} Could not set FONT in /etc/vconsole.conf - the login screen keeps the default font." | tee -a "$LOG"
  fi

  # Apply now instead of only at the next boot. systemd-vconsole-setup reads the
  # file we just wrote and pushes the font to every allocated VT.
  if sudo systemctl restart systemd-vconsole-setup.service >> "$LOG" 2>&1; then
    echo "${OK} Console font applied to the active VTs." | tee -a "$LOG"
  else
    echo "${NOTE} Could not apply it now - it takes effect at the next boot." | tee -a "$LOG"
  fi
fi

printf "${OK} ly display manager configured successfully!\n"

