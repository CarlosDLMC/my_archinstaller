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

# The session list ly builds from a config.ini, in ly's own order, one
# "<kind>:<name>" per line. It mirrors ly 1.4.1's main.zig: the shell entry
# unless `shell = false`, the xinitrc entry unless `xinitrc = null`, then the
# *.desktop files of the waylandsessions, xsessions and custom_sessions
# directories. Each directory is listed in READDIR order (ls -U), because
# that is what ly's crawl() walks and it never sorts: a sorted glob orders
# hyprland.desktop and hyprland-uwsm.desktop by locale instead, and would get
# the numbers below wrong. A key the file does not set takes ly's built-in
# default.
ly_conf_get() { # file key default
  local v
  v=$(sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*//p" "$1" 2>/dev/null | tail -n 1)
  v="${v%"${v##*[![:space:]]}"}"
  printf '%s\n' "${v:-$3}"
}
ly_sessions() { # config.ini
  local spec kind key def dirs dir f
  local -a dir_list
  [ "$(ly_conf_get "$1" shell true)" = "false" ] || echo "shell"
  [ "$(ly_conf_get "$1" xinitrc '~/.xinitrc')" = "null" ] || echo "xinitrc"
  for spec in wayland:waylandsessions:/usr/share/wayland-sessions \
              x11:xsessions:/usr/share/xsessions \
              custom:custom_sessions:/etc/ly/custom-sessions; do
    IFS=: read -r kind key def <<<"$spec"
    dirs=$(ly_conf_get "$1" "$key" "$def")
    [ "$dirs" = "null" ] && continue
    IFS=: read -ra dir_list <<<"$dirs"
    for dir in "${dir_list[@]}"; do
      [ -d "$dir" ] || continue
      while IFS= read -r f; do
        case "$f" in *.desktop) echo "$kind:${f%.desktop}" ;; esac
      done < <(ls -U1A -- "$dir" 2>/dev/null)
    done
  done
  # Explicit: the callers are plain assignments, and under Global_functions.sh's
  # set -e a stray non-zero status here would end the whole script.
  return 0
}

# Taken BEFORE config.ini is replaced: the numbers in /etc/ly/save.txt index
# the list this produces, and the new config.ini (and the uwsm entry going,
# below) changes that list. See "Session list" further down.
_old_sessions=""
[ -r /etc/ly/config.ini ] && _old_sessions=$(ly_sessions /etc/ly/config.ini)

ly_install 644 "$PARENT_DIR/assets/ly/config.ini" /etc/ly/config.ini

printf "${NOTE} Installing ly start script...\n"
ly_install 755 "$PARENT_DIR/assets/ly/start.sh" /etc/ly/start.sh

# Session list: Hyprland, and only Hyprland
#
# The hyprland package ships two session files: hyprland.desktop
# (Exec=/usr/bin/start-hyprland, what this setup logs in with) and
# hyprland-uwsm.desktop (Exec=uwsm start ...). Other display managers hide the
# second through its TryExec=uwsm, but ly 1.4.1 never reads TryExec and
# nothing here installs uwsm, so ly listed a "Hyprland (uwsm-managed)" that
# drops straight back to the login screen. Worse, with no save.txt yet ly
# preselects the LAST session it adds, and which of the two readdir returns
# last depends on the filesystem's hash seed: on this laptop's ext4 it was the
# uwsm one, so the first login after the install bounced (ly.log, Sep 13).
#
# pacman.sh adds `NoExtract` for the file, and runs before hyprland.sh, so a
# fresh install never gets it at all. This removes the copy an earlier install
# already put there - NoExtract only governs future extraction - and pacman -Qk
# counts a missing NoExtract file as intended, not as damage.
_uwsm_entry=/usr/share/wayland-sessions/hyprland-uwsm.desktop
if pacman -Q uwsm &>/dev/null; then
  echo "${NOTE} uwsm is installed, so ${_uwsm_entry##*/} works - leaving it in ly's session list." | tee -a "$LOG"
else
  if [ -e "$_uwsm_entry" ]; then
    sudo rm -f "$_uwsm_entry" 2>&1 | tee -a "$LOG"
    if [ -e "$_uwsm_entry" ]; then
      echo "${WARN} Could not remove $_uwsm_entry - ly will list a uwsm session that cannot start." | tee -a "$LOG"
    else
      echo "${OK} Removed ${_uwsm_entry##*/}: ly lists no uwsm session without uwsm." | tee -a "$LOG"
    fi
  fi
  if ! grep -qE '^[[:space:]]*NoExtract[[:space:]]*=.*usr/share/wayland-sessions/hyprland-uwsm\.desktop' /etc/pacman.conf 2>/dev/null; then
    echo "${WARN} /etc/pacman.conf has no NoExtract for ${_uwsm_entry##*/} (pacman.sh adds it) - the next hyprland upgrade puts the entry back." | tee -a "$LOG"
  fi
fi

# Keep save.txt pointing at the same sessions.
#
# ly stores each user's last session as an INDEX into that list, not a name
# (/etc/ly/save.txt, "user:N"). config.ini now hides shell and xinitrc and the
# uwsm entry is gone, so every entry shifts - this laptop's "mentefria:2" was
# Hyprland behind shell(0) and xinitrc(1), and Hyprland is now 0. ly clamps an
# out-of-range index to the LAST entry (main.zig: @min(index, len - 1)), so
# with Hyprland alone that would still land right; but the stale 2 stays in
# the file, and once more sessions are ever installed it points at whatever
# happens to sit there. With other sessions already installed, an index can
# land in range on the wrong one straight away.
#
# So when the list changes, rewrite each index to the same session's new
# position, and a session that no longer exists (shell, xinitrc, uwsm) to
# Hyprland's. An index already past the end of the list is stale whatever
# happened - ly never corrects one it clamped - so it goes to Hyprland too,
# which on the next re-run also mends an old index that a running ly wrote
# back (see below). Anything else is left exactly as it is, so a re-run on an
# unchanged list writes nothing. The first line, the index of the last user,
# is not touched.
#
# One caveat: a running ly holds the OLD list in memory and rewrites save.txt
# from it at the next login. A preset run reboots before that happens; after
# an interactive run, reboot before logging out and back in.
_new_sessions=$(ly_sessions /etc/ly/config.ini)
# An EMPTY list gets a warning of its own. config.ini hides shell and xinitrc,
# so the list is now exactly the *.desktop files in /usr/share/wayland-sessions,
# and the shell entry no longer guarantees there is at least one. ly 1.4.1
# never checks for none: main.zig and UserList.zig take `len - 1` of the list
# and the login reads items[current], so an empty one is undefined behaviour
# in a release build, not a clean error on the login screen. hyprland.sh ran
# before this script, so empty here means its session file is missing (a
# failed install, or a package that renamed it) - say so while the log is
# still being read, rather than at a login screen that misbehaves.
if [ -n "$_new_sessions" ]; then
  echo "${NOTE} ly's session list: $(echo "$_new_sessions" | paste -sd' ' -)" | tee -a "$LOG"
else
  echo "${WARN} ly has no sessions to offer: no /usr/share/wayland-sessions/*.desktop (is hyprland installed?). Log in on tty3 (Ctrl+Alt+F3) and fix that first." | tee -a "$LOG"
fi
if [ -n "$_old_sessions" ] && [ -n "$_new_sessions" ] && [ -s /etc/ly/save.txt ] && [ -r /etc/ly/save.txt ]; then
  _saved=$(cat /etc/ly/save.txt)
  _remapped=$(LY_OLD="$_old_sessions" LY_NEW="$_new_sessions" awk '
    BEGIN {
      same = (ENVIRON["LY_OLD"] == ENVIRON["LY_NEW"])
      nold = split(ENVIRON["LY_OLD"], old, "\n")
      n = split(ENVIRON["LY_NEW"], new, "\n")
      fallback = 0
      for (i = 1; i <= n; i++) {
        at[new[i]] = i - 1
        if (new[i] == "wayland:hyprland") fallback = i - 1
      }
    }
    NR == 1 || !/^[^:]+:[0-9]+$/ { print; next }
    {
      user = $0; sub(/:[0-9]+$/, "", user)
      k = substr($0, length(user) + 2) + 0
      if (same && k < n) idx = k
      else if (k < nold && (old[k + 1] in at)) idx = at[old[k + 1]]
      else idx = fallback
      print user ":" idx
    }' <<<"$_saved")
  if [ -n "$_remapped" ] && [ "$_remapped" != "$_saved" ]; then
    if printf '%s\n' "$_remapped" | sudo tee /etc/ly/save.txt >/dev/null &&
       [ "$(cat /etc/ly/save.txt 2>/dev/null)" = "$_remapped" ]; then
      echo "${OK} Re-pointed /etc/ly/save.txt at the new session list: $(echo "$_remapped" | tail -n +2 | paste -sd' ' -)" | tee -a "$LOG"
    else
      echo "${WARN} Could not rewrite /etc/ly/save.txt - pick Hyprland once on the login screen and ly remembers it." | tee -a "$LOG"
    fi
  fi
fi

# Which panel is this? Both the flag and the console font are cut for a
# specific console grid, so both are chosen from the same measurement.
#
# The preferred (first) mode of every connected DRM connector is that
# panel's native resolution, readable from sysfs with no compositor running.
# The SMALLEST connected output decides, not the largest. The failure modes
# are not symmetric: too small is merely cosmetic, while too large clips on
# the panel that has the fewest rows. So the display that fits least is the
# one that has to fit - in each direction, since the narrowest and the
# shortest output need not be the same one.
_min_w=""
_min_h=""
for _modes in /sys/class/drm/*/modes; do
  [ -r "$_modes" ] || continue
  _conn="${_modes%/modes}"
  [ "$(cat "$_conn/status" 2>/dev/null)" = "connected" ] || continue
  # First line of modes is the preferred (native) mode, e.g. "2560x1440".
  _mode=$(head -1 "$_modes" 2>/dev/null) || continue
  _h=$(echo "$_mode" | cut -d'x' -f2 | tr -cd '0-9')
  [ -n "$_h" ] || continue
  if [ -z "$_min_h" ] || [ "$_h" -lt "$_min_h" ]; then _min_h="$_h"; fi
  _w=$(echo "$_mode" | cut -d'x' -f1 | tr -cd '0-9')
  [ -n "$_w" ] || continue
  if [ -z "$_min_w" ] || [ "$_w" -lt "$_min_w" ]; then _min_w="$_w"; fi
done
# Fallback: the framebuffer the console is actually on. Covers a machine whose
# connectors report no modes yet (and any future non-DRM console).
if [ -z "$_min_h" ] && [ -r /sys/class/graphics/fb0/virtual_size ]; then
  _min_w=$(cut -d, -f1 /sys/class/graphics/fb0/virtual_size 2>/dev/null | tr -cd '0-9')
  _min_h=$(cut -d, -f2 /sys/class/graphics/fb0/virtual_size 2>/dev/null | tr -cd '0-9')
fi

printf "${NOTE} Installing 8-bit soviet flag animation...\n"
# config.ini sets animation = dur_file and points dur_file_path here, so the
# flag has to land in /etc/ly or ly draws nothing at all. Both the waving and
# the still version are installed, so switching is a one-line config edit
# rather than a re-run of this script.
#
# ly draws a .dur at its native cell size and never scales it, so the art is
# cut per console grid (assets/ly/soviet-flag.py) and the matching pair is
# installed under the fixed names config.ini points at - config.ini never has
# to change. The grid is width/16 x height/32 because /etc/ly/start.sh loads
# latarcyrheb-sun32 on ly's own VT whatever vconsole.conf below ends up
# saying, so the choice follows the panel, not the font.
#
# The cut is the largest that fits that grid in BOTH directions. It used to go
# by height alone, which gave a 3:2 panel the cut of a 16:9 one its height:
# 2256x1504 (141x47) got the 1440p cut, 160 columns wide, and ly silently
# clipped 19 of them. The sizes are read out of the .dur files themselves
# (sizeX/sizeY in the gzipped JSON), so a cut added to soviet-flag.py is
# picked up here with no table to keep in step.
_cols=""
_rows=""
if [ -n "$_min_w" ] && [ -n "$_min_h" ]; then
  _cols=$(( _min_w / 16 ))
  _rows=$(( _min_h / 32 ))
fi
_flag=""
_flag_size=""
_flag_area=0
_small=""
_small_size=""
_small_area=0
for _dur in "$PARENT_DIR"/assets/ly/soviet-flag-static-*.dur; do
  [ -r "$_dur" ] || continue
  _cut="${_dur##*/soviet-flag-static-}"
  _cut="${_cut%.dur}"
  # Only a complete pair is a candidate: both halves are installed below, and
  # a static cut whose animated twin never made it into the checkout (added
  # to git without it) would otherwise be chosen and then end the script.
  [ -r "$PARENT_DIR/assets/ly/soviet-flag-animated-$_cut.dur" ] || continue
  _sx=$(zcat -- "$_dur" 2>/dev/null | grep -o '"sizeX": *[0-9]*' | tr -cd '0-9')
  _sy=$(zcat -- "$_dur" 2>/dev/null | grep -o '"sizeY": *[0-9]*' | tr -cd '0-9')
  [ -n "$_sx" ] && [ -n "$_sy" ] || continue
  _area=$(( _sx * _sy ))
  if [ -z "$_small" ] || [ "$_area" -lt "$_small_area" ]; then
    _small="$_cut"; _small_size="${_sx}x${_sy}"; _small_area="$_area"
  fi
  if [ -n "$_cols" ] && [ "$_sx" -le "$_cols" ] && [ "$_sy" -le "$_rows" ] && [ "$_area" -gt "$_flag_area" ]; then
    _flag="$_cut"; _flag_size="${_sx}x${_sy}"; _flag_area="$_area"
  fi
done
if [ -z "$_cols" ] || [ -z "$_small" ]; then
  # Nothing readable - no panel size, or no cut size - so the 1080p cut, as
  # before there was any choice. The smallest cut would clip least in theory,
  # but a machine with no connected connector and no fb0 is rare, and on the
  # 1080p-or-larger panel it most likely has, the 768p cut would come out a
  # third smaller than it needs to be.
  _flag="1080p"
  echo "${NOTE} Could not measure the console grid -> ${SKY_BLUE}soviet-flag-*-${_flag}.dur${RESET}" | tee -a "$LOG"
elif [ -n "$_flag" ]; then
  echo "${NOTE} Console grid is ${_cols}x${_rows} cells (${_min_w}x${_min_h} px) -> ${SKY_BLUE}soviet-flag-*-${_flag}.dur${RESET} (${_flag_size} cells)" | tee -a "$LOG"
else
  # Smaller than every cut (1280x720 is 80x22, 1024x768 is 64x24): the
  # smallest one clips least. Say so rather than leave it unexplained.
  _flag="$_small"
  echo "${WARN} Console grid is ${_cols}x${_rows} cells (${_min_w}x${_min_h} px), smaller than every flag cut: installing the smallest (${_small_size} cells), which ly will clip. Set 'animation = none' in /etc/ly/config.ini if that bothers you." | tee -a "$LOG"
fi
ly_install 644 "$PARENT_DIR/assets/ly/soviet-flag-animated-$_flag.dur" /etc/ly/soviet-flag-animated.dur
ly_install 644 "$PARENT_DIR/assets/ly/soviet-flag-static-$_flag.dur" /etc/ly/soviet-flag-static.dur

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
# _min_h was measured above, where the flag cut was chosen from it.
#
# This sets the font for the console at large. ly's own VT does not depend on
# it: /etc/ly/start.sh runs setfont latarcyrheb-sun32 there unconditionally,
# which is what the flag's 16x32 cell arithmetic assumes.
printf "${NOTE} Selecting the console font for the login screen...\n"

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

