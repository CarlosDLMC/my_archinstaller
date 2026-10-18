#!/bin/bash
# rofi with on-demand keyboard focus, built from pkgbuilds/rofi/.
#
# Stock rofi on Wayland always takes the keyboard exclusively, so nothing else
# can be clicked or typed into while it is open. The vendored PKGBUILD is Arch's
# rofi plus keyboard-on-demand.patch: with ROFI_KEYBOARD_ON_DEMAND set (the
# SUPER D bind sets it), a click on a window gives that window the keyboard
# while the launcher stays open - a file opened beside it with Shift+Enter in
# the ФАЙЛЫ tab can be used. Three smaller patches ride along: the launcher's
# row-position counter (num-current-row), the cursor's blink-interval, and
# keep-list (Shift+Enter toggles the preview without reloading the list). See
# pkgbuilds/rofi/PKGBUILD.
#
# Runs after 01-hypr-pkgs.sh, which installs the stock rofi. If this build
# fails, that stock rofi stays and the launcher works without click-to-focus,
# so a failure is a warning here, not a failed package for the final check.

PKG=rofi

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "[ERROR] Failed to change directory to $PARENT_DIR"; exit 1; }

if ! source "$SCRIPT_DIR/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_rofi-ondemand.log"
SRC="$PARENT_DIR/pkgbuilds/$PKG"

if [ ! -f "$SRC/PKGBUILD" ]; then
  echo "${WARN} No vendored PKGBUILD at pkgbuilds/$PKG - keeping the stock rofi." | tee -a "$LOG"
  exit 0
fi

# The version the vendored PKGBUILD builds, read in a subshell so its variables
# and functions stay out of this script.
WANT=$( set +e; source "$SRC/PKGBUILD" >/dev/null 2>&1; echo "${pkgver}-${pkgrel}" )
HAVE=$(pacman -Q "$PKG" 2>/dev/null | awk '{print $2}')
# Not just "equal": a newer rofi from the repos is kept rather than downgraded
# to the vendored copy - it has no click-to-focus until the patch is rebuilt
# for that version.
if [ -n "$HAVE" ] && [ "$(vercmp "$HAVE" "$WANT")" -ge 0 ]; then
  if [ "$HAVE" = "$WANT" ]; then
    echo "${INFO} The patched ${MAGENTA}rofi${RESET} $HAVE is already installed. Skipping..." | tee -a "$LOG"
  else
    echo "${NOTE} ${MAGENTA}rofi${RESET} $HAVE is newer than the vendored $WANT - keeping it (no click-to-focus in the launcher until pkgbuilds/rofi is updated)." | tee -a "$LOG"
  fi
  exit 0
fi

printf "\n%s - Building ${SKY_BLUE}rofi $WANT${RESET} (on-demand keyboard focus) from the vendored PKGBUILD .... \n" "${NOTE}"
# Built in a temp dir, never in the repo: makepkg writes src/, pkg/ and the
# sources next to the PKGBUILD (see yay.sh).
TMPD=$(mktemp -d) || exit 0
cp -r "$SRC/." "$TMPD/"

# -s pulls the build deps (meson) from the repos. -f: a package of the same
# version left in a persistent PKGDEST must not stop the build.
( cd "$TMPD" && makepkg -sf --noconfirm 2>&1 ) | tee -a "$LOG"
# tee is last in the pipeline: PIPESTATUS[0] is makepkg's status.
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
  echo "${WARN} Failed to build the patched rofi - keeping the stock one. See $LOG." | tee -a "$LOG"
  rm -rf "$TMPD"
  exit 0
fi

# --packagelist, not a glob: makepkg.conf may set PKGDEST elsewhere.
BUILT=()
while IFS= read -r _p; do
  case "${_p##*/}" in *-debug-*) continue ;; esac
  # An if, not `[ -f ] &&`: under Global_functions.sh's `set -e` a false test
  # as the loop's last command can end the script.
  if [ -f "$_p" ]; then
    BUILT+=("$_p")
  fi
done < <(cd "$TMPD" && makepkg --packagelist 2>/dev/null)

if [ ${#BUILT[@]} -gt 0 ]; then
  sudo pacman -U --noconfirm "${BUILT[@]}" 2>&1 | tee -a "$LOG"
fi
mv "$TMPD"/*.log "$PARENT_DIR/Install-Logs/" 2>/dev/null || true
rm -rf "$TMPD"

if [ "$(pacman -Q "$PKG" 2>/dev/null | awk '{print $2}')" = "$WANT" ]; then
  echo "${OK} The patched ${YELLOW}rofi${RESET} $WANT is installed." | tee -a "$LOG"
else
  echo "${WARN} The patched rofi did not install - keeping the stock one. See $LOG." | tee -a "$LOG"
fi

printf "\n%.0s" {1..2}
