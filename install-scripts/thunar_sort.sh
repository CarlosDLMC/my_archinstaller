#!/bin/bash
# Thunar per-folder sort - capture folders open newest-first #
# Screenshots and Recordings fill up fast and the file you want is almost always
# the newest one, but Thunar sorts by name. Name order is not chronological here:
# the screenshot filenames have gone through three formats over the years
# (Screenshot_02-Jan_22-00-54_*, Screenshot_20260211_114704, plus hand-renamed
# files), so only mtime sorting actually puts the latest capture on top.
# NOTE: must run AFTER thunar.sh - needs Thunar installed for the xfconf channel.

# Folders that should open newest-first. Add more paths here if you want.
# Resolved from the XDG user dirs so these match what ScreenShot.sh and
# ScreenRecord.sh in the dotfiles actually write to.
sort_dirs_relative=(
  "PICTURES:Screenshots"
  "VIDEOS:Recordings"
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
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_thunar-sort.log"

# Both xfconf-query and `gio set` talk to session-bus daemons (xfconfd and
# gvfsd-metadata). Run from a TTY with no session bus they exit non-zero and the
# setting silently never lands, so fall back to a private bus - its daemons still
# write to the same files on disk. Prefer the live session bus when there is one:
# a second gvfsd-metadata opening the same database is asking for lost writes.
run_with_bus() {
  if [ -n "$DBUS_SESSION_BUS_ADDRESS" ]; then
    "$@"
  elif command -v dbus-run-session >/dev/null 2>&1; then
    dbus-run-session -- "$@"
  else
    "$@"
  fi
}

# Resolve an XDG user dir, falling back to the conventional path. xdg-user-dir
# prints $HOME for a dir it does not know, which would target the wrong folder.
resolve_xdg_dir() {
  local key="$1" fallback="$2" resolved=""
  if command -v xdg-user-dir >/dev/null 2>&1; then
    resolved="$(xdg-user-dir "$key" 2>/dev/null)"
  fi
  if [ -z "$resolved" ] || [ "$resolved" = "$HOME" ]; then
    resolved="$HOME/$fallback"
  fi
  printf '%s' "$resolved"
}

printf "${INFO} Configuring ${SKY_BLUE}Thunar${RESET} sort order for capture folders...\n"

if ! command -v thunar >/dev/null 2>&1; then
  echo "${WARN} Thunar not installed - run thunar.sh first. Skipping." | tee -a "$LOG"
  exit 0
fi

# Per-folder view settings are ignored entirely unless this is on - without it
# Thunar keeps a single sort order shared by every folder, so setting one folder
# to newest-first would reorder the whole filesystem.
if [ "$(run_with_bus xfconf-query -c thunar -p /misc-directory-specific-settings 2>/dev/null)" = "true" ]; then
  echo "${INFO} Directory-specific settings already enabled, skipping." | tee -a "$LOG"
else
  if run_with_bus xfconf-query -c thunar -p /misc-directory-specific-settings -n -t bool -s true 2>&1 | tee -a "$LOG"; then
    echo "${OK} Enabled per-directory view settings in Thunar." | tee -a "$LOG"
  else
    echo "${ERROR} Failed to enable per-directory view settings - the per-folder sort below will not take effect." | tee -a "$LOG"
  fi
fi

printf "\n%.0s" {1..1}

# Thunar stores per-folder view settings as GVFS metadata on the directory
# itself, not as a dotfile inside it and not under ~/.config/Thunar - so these
# cannot be shipped as a config file, they have to be written with gio.
for ENTRY in "${sort_dirs_relative[@]}"; do
  XDG_KEY="${ENTRY%%:*}"
  SUBDIR="${ENTRY#*:}"

  case "$XDG_KEY" in
    PICTURES) BASE="$(resolve_xdg_dir PICTURES Pictures)" ;;
    VIDEOS)   BASE="$(resolve_xdg_dir VIDEOS Videos)" ;;
    *)        BASE="$(resolve_xdg_dir "$XDG_KEY" "$XDG_KEY")" ;;
  esac

  TARGET="$BASE/$SUBDIR"

  # Created here rather than assumed: on a fresh install nothing has taken a
  # screenshot yet, and gio will not attach metadata to a path that is not there.
  if [ ! -d "$TARGET" ]; then
    mkdir -p "$TARGET" && echo "${NOTE} Created ${MAGENTA}$TARGET${RESET}" | tee -a "$LOG"
  fi

  if run_with_bus gio set "$TARGET" metadata::thunar-sort-column THUNAR_COLUMN_DATE_MODIFIED 2>&1 | tee -a "$LOG" &&
     run_with_bus gio set "$TARGET" metadata::thunar-sort-order GTK_SORT_DESCENDING 2>&1 | tee -a "$LOG"; then
    echo "${OK} ${MAGENTA}$TARGET${RESET} set to newest-first." | tee -a "$LOG"
  else
    echo "${ERROR} Failed to set sort order on $TARGET." | tee -a "$LOG"
  fi
done

printf "\n${NOTE} ${SKY_BLUE}Screenshots${RESET} and ${SKY_BLUE}Recordings${RESET} now open newest-first in Thunar; every other folder keeps its own sort order. Already-open Thunar windows do not reload this - run ${YELLOW}thunar -q${RESET} and reopen. To undo one folder: ${MAGENTA}gio set -t unset <folder> metadata::thunar-sort-column${RESET}.\n"

printf "\n%.0s" {1..2}
