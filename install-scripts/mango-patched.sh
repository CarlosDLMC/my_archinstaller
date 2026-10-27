#!/bin/bash
# The patched mango, built from pkgbuilds/mangowm/.
#
# Arch's mangowm built from our fork, github.com/CarlosDLMC/mango (branch
# patched, one commit per change), whose changes make mango look and behave
# like the Hyprland setup this desktop came from: windows that keep their content at
# native size while they move (no stretch), binds that repeat only when
# flagged (binde), reloads that keep the keyboard layout, Hyprland's groups
# and tab bar, layer fades, shadow colours, the special workspace slide,
# desktop zoom and more - see pkgbuilds/mangowm/PKGBUILD.
#
# This is the only place mango is installed: no stock mangowm goes in first.
# makepkg -s pulls what the build and mango itself need from the repos -
# meson, wlroots0.20 and scenefx (named by soname), xorg-xwayland and the rest
# of depends. The config in dotfiles/config/mango uses the patches' options
# and binds, which stock mango does not know - so a failed build is an error
# here (the final check lists it), not a warning.
#
# Once it is installed, mangowm goes into IgnorePkg: a newer stock mango from
# the repos would replace the patched one on the next -Syu. The package names scenefx and
# wlroots by soname, so pacman refuses a library update this build would not
# survive; rebuild it (this script) after updating pkgbuilds/mangowm.

PKG=mangowm

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "[ERROR] Failed to change directory to $PARENT_DIR"; exit 1; }

if ! source "$SCRIPT_DIR/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_mango-patched.log"
SRC="$PARENT_DIR/pkgbuilds/$PKG"

if [ ! -f "$SRC/PKGBUILD" ]; then
  echo "${ERROR} No vendored PKGBUILD at pkgbuilds/$PKG - the mango config needs the patched mango." | tee -a "$LOG"
  record_package_failure "mangowm-patched"
  exit 0
fi

# Kept off -Syu: our own line under [options], with a comment above it (pacman
# has no comments at the end of a line). Not added twice. Only once the
# patched mango is installed: a failed build leaves a stock one (CachyOS's
# Mango edition) updating as usual.
pin_ignorepkg() {
  if pacman-conf IgnorePkg 2>/dev/null | grep -qxF "$PKG"; then
    return 0
  fi
  if sudo cp -p /etc/pacman.conf "/etc/pacman.conf.bak-$(date +%Y%m%d-%H%M%S)" \
     && sudo sed -i "/^\[options\]/a # Built from pkgbuilds/mangowm by my_archinstaller (install-scripts/mango-patched.sh) - the config needs its options\nIgnorePkg = $PKG" /etc/pacman.conf \
     && pacman-conf IgnorePkg 2>/dev/null | grep -qxF "$PKG"; then
    echo "${OK} $PKG added to IgnorePkg in /etc/pacman.conf - updated from pkgbuilds/mangowm, never by -Syu." | tee -a "$LOG"
  else
    echo "${WARN} Could not add $PKG to IgnorePkg in /etc/pacman.conf - a newer stock mango could replace the patched one on -Syu." | tee -a "$LOG"
  fi
}

# The version the vendored PKGBUILD builds, read in a subshell so its variables
# and functions stay out of this script.
WANT=$( set +e; source "$SRC/PKGBUILD" >/dev/null 2>&1; echo "${pkgver}-${pkgrel}" )
HAVE=$(pacman -Q "$PKG" 2>/dev/null | awk '{print $2}')
if [ "$HAVE" = "$WANT" ]; then
  echo "${INFO} The patched ${MAGENTA}mango${RESET} $HAVE is already installed. Skipping..." | tee -a "$LOG"
  pin_ignorepkg
  clear_package_failure "mangowm-patched"
  exit 0
fi

printf "\n%s - Building the patched ${SKY_BLUE}mango $WANT${RESET} from the vendored PKGBUILD .... \n" "${NOTE}"
# Built in a temp dir, never in the repo: makepkg writes src/, pkg/ and the
# sources next to the PKGBUILD (see yay.sh).
if ! TMPD=$(mktemp -d) || ! cp -r "$SRC/." "$TMPD/"; then
  echo "${ERROR} Could not set up a build directory for the patched mango (a full /tmp?) - the mango config needs it." | tee -a "$LOG"
  record_package_failure "mangowm-patched"
  [ -n "${TMPD:-}" ] && rm -rf "$TMPD"
  exit 0
fi

# -s pulls the build and runtime deps from the repos (see the top). -f: a package of the same version left in a persistent PKGDEST must
# not stop the build.
( cd "$TMPD" && makepkg -sf --noconfirm 2>&1 ) | tee -a "$LOG"
# tee is last in the pipeline: PIPESTATUS[0] is makepkg's status.
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
  echo "${ERROR} Failed to build the patched mango - the mango config needs it. See $LOG." | tee -a "$LOG"
  record_package_failure "mangowm-patched"
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
  echo "${OK} The patched ${YELLOW}mango${RESET} $WANT is installed." | tee -a "$LOG"
  pin_ignorepkg
  clear_package_failure "mangowm-patched"
  # Explicit, so no orphan clean-up takes it (pacman -U keeps the reason of a
  # stock mango it replaces - mango.sh marked that one explicit too).
  sudo pacman -D --asexplicit "$PKG" >>"$LOG" 2>&1 || true
else
  echo "${ERROR} The patched mango did not install - the mango config needs it. See $LOG." | tee -a "$LOG"
  record_package_failure "mangowm-patched"
fi

printf "\n%.0s" {1..2}
