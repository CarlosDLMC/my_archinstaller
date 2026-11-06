#!/bin/bash
# satty with our patches, built from pkgbuilds/satty/.
#
# ScreenShot.sh opens every screenshot in satty to draw on it. The vendored
# PKGBUILD is Arch's satty plus one patch per change: rotate.patch adds rotate
# left/right buttons (Ctrl-Shift-R / Ctrl-R), drag-text.patch lets a written
# text be dragged to a new place, move-any.patch lets the pointer tool drag
# anything drawn, edit-text.patch reopens a clicked text for editing, select-delete-nudge.patch makes Delete remove just the picked item and the arrows move it. See pkgbuilds/satty/PKGBUILD.
#
# Runs after 01-desktop-pkgs.sh, which installs the stock satty. If this build
# fails, that stock satty stays and screenshots work without the patches, so a
# failure is a warning here, not a failed package for the final check.
#
# Once the patched satty is installed, satty goes into IgnorePkg: a newer stock
# satty from the repos would replace it on the next -Syu and lose the patches.
# Update it from pkgbuilds/satty (this script) instead.

PKG=satty

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "[ERROR] Failed to change directory to $PARENT_DIR"; exit 1; }

if ! source "$SCRIPT_DIR/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_satty-patched.log"
SRC="$PARENT_DIR/pkgbuilds/$PKG"

if [ ! -f "$SRC/PKGBUILD" ]; then
  echo "${WARN} No vendored PKGBUILD at pkgbuilds/$PKG - keeping the stock satty." | tee -a "$LOG"
  exit 0
fi

# Only once the patched satty is installed: a stock one that is kept (a failed
# build, or a newer one from the repos) goes on updating as usual.
pin_ignorepkg() {
  if pacman-conf IgnorePkg 2>/dev/null | grep -qxF "$PKG"; then
    return 0
  fi
  if sudo cp -p /etc/pacman.conf "/etc/pacman.conf.bak-$(date +%Y%m%d-%H%M%S)" \
     && sudo sed -i "/^\[options\]/a # Built from pkgbuilds/satty by my_archinstaller (install-scripts/satty-patched.sh) - keeps its patches\nIgnorePkg = $PKG" /etc/pacman.conf \
     && pacman-conf IgnorePkg 2>/dev/null | grep -qxF "$PKG"; then
    echo "${OK} $PKG added to IgnorePkg in /etc/pacman.conf - updated from pkgbuilds/satty, never by -Syu." | tee -a "$LOG"
  else
    echo "${WARN} Could not add $PKG to IgnorePkg in /etc/pacman.conf - a newer stock satty could replace the patched one on -Syu." | tee -a "$LOG"
  fi
}

# The version the vendored PKGBUILD builds, read in a subshell so its variables
# and functions stay out of this script.
WANT=$( set +e; source "$SRC/PKGBUILD" >/dev/null 2>&1; echo "${pkgver}-${pkgrel}" )
HAVE=$(pacman -Q "$PKG" 2>/dev/null | awk '{print $2}')
# Not just "equal": a newer satty from the repos is kept rather than downgraded
# to the vendored copy - it has no patches until they are rebuilt for that
# version.
if [ -n "$HAVE" ] && [ "$(vercmp "$HAVE" "$WANT")" -ge 0 ]; then
  if [ "$HAVE" = "$WANT" ]; then
    echo "${INFO} The patched ${MAGENTA}satty${RESET} $HAVE is already installed. Skipping..." | tee -a "$LOG"
    pin_ignorepkg
  else
    echo "${NOTE} ${MAGENTA}satty${RESET} $HAVE is newer than the vendored $WANT - keeping it (no rotate buttons, dragging or text editing until pkgbuilds/satty is updated)." | tee -a "$LOG"
  fi
  exit 0
fi

printf "\n%s - Building ${SKY_BLUE}satty $WANT${RESET} (patched) from the vendored PKGBUILD .... \n" "${NOTE}"
# Built in a temp dir, never in the repo: makepkg writes src/, pkg/ and the
# sources next to the PKGBUILD (see yay.sh).
TMPD=$(mktemp -d) || exit 0
cp -r "$SRC/." "$TMPD/"

# -s pulls the build deps (cargo) from the repos. -f: a package of the same
# version left in a persistent PKGDEST must not stop the build.
( cd "$TMPD" && makepkg -sf --noconfirm 2>&1 ) | tee -a "$LOG"
# tee is last in the pipeline: PIPESTATUS[0] is makepkg's status.
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
  echo "${WARN} Failed to build the patched satty - keeping the stock one. See $LOG." | tee -a "$LOG"
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
  echo "${OK} The patched ${YELLOW}satty${RESET} $WANT is installed." | tee -a "$LOG"
  pin_ignorepkg
else
  echo "${WARN} The patched satty did not install - keeping the stock one. See $LOG." | tee -a "$LOG"
fi

printf "\n%.0s" {1..2}
