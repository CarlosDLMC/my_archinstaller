#!/bin/bash
# Omarchy's small apps - borrowed for what they do, not how omarchy looks:
#
#   omawrite  dead-simple Markdown writing app (Qt Quick)
#   omacut    dead-simple video trimmer/cutter (Qt Quick + ffmpeg)
#
# omacut is not in the AUR at all, and the AUR's omawrite is a stale 0.5.0 under
# the old omacom-io org. Both are built here from the PKGBUILDs omarchy ships
# them with, vendored in pkgbuilds/ (source pinned by sha256, like yay-bin/).
# They become real pacman packages, so `pacman -R` removes them cleanly - but
# nothing updates them: bump the vendored PKGBUILD and re-run this script. They
# are in pacman.conf's IgnorePkg, so -Syu never swaps in the AUR's omawrite.
#
# Both apps colour themselves from omarchy's theme file,
# ~/.local/state/omarchy/current/theme/colors.toml, and watch it. Here wallust
# writes it on every wallpaper change (config/wallust/templates/
# omarchy-colors.toml), so omacut's accent follows the wallpaper. omawrite is
# patched to use it only in its Unsaved changes / Changed on disk dialogs - see
# pkgbuilds/omawrite/PKGBUILD.

# Built from pkgbuilds/<name>/.
omarchy_apps_vendored=(
  omawrite
  omacut
)

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "[ERROR] Failed to change directory to $PARENT_DIR"; exit 1; }

if ! source "$SCRIPT_DIR/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_omarchy-apps.log"

# Kept off -Syu. The AUR has an omawrite under the same name, so a routine
# `yay -Syu` checks this build against it: once the AUR's version passed the
# vendored one, the unpatched upstream app would replace it - no portal
# wrapper, none of the patches. IgnorePkg (pacman.conf) stops that for pacman
# and yay alike, while `pacman -U` below still installs and updates them. Our
# own line under [options], with a comment above it - pacman has no comments
# at the end of a line. Names another IgnorePkg line already holds are left out.
_ignore=()
for PKG in "${omarchy_apps_vendored[@]}"; do
  if ! pacman-conf IgnorePkg 2>/dev/null | grep -qxF "$PKG"; then
    _ignore+=("$PKG")
  fi
done
if [ ${#_ignore[@]} -gt 0 ]; then
  if sudo cp -p /etc/pacman.conf "/etc/pacman.conf.bak-$(date +%Y%m%d-%H%M%S)" \
     && sudo sed -i "/^\[options\]/a # Built from pkgbuilds/ by my_archinstaller (install-scripts/omarchy-apps.sh) - not from the AUR\nIgnorePkg = ${_ignore[*]}" /etc/pacman.conf \
     && pacman-conf IgnorePkg 2>/dev/null | grep -qxF "${_ignore[0]}"; then
    echo "${OK} ${_ignore[*]} added to IgnorePkg in /etc/pacman.conf - updated from pkgbuilds/, never by -Syu." | tee -a "$LOG"
  else
    echo "${WARN} Could not add ${_ignore[*]} to IgnorePkg in /etc/pacman.conf - a newer AUR omawrite could replace this build on -Syu." | tee -a "$LOG"
  fi
fi

for PKG in "${omarchy_apps_vendored[@]}"; do
  SRC="$PARENT_DIR/pkgbuilds/$PKG"
  if [ ! -f "$SRC/PKGBUILD" ]; then
    echo "${ERROR} No vendored PKGBUILD at pkgbuilds/$PKG. Skipping $PKG." | tee -a "$LOG"
    record_package_failure "$PKG"
    continue
  fi

  # The version the vendored PKGBUILD builds, read in a subshell so its
  # variables and functions stay out of this script.
  WANT=$( set +e; source "$SRC/PKGBUILD" >/dev/null 2>&1; echo "${pkgver}-${pkgrel}" )
  HAVE=$(pacman -Q "$PKG" 2>/dev/null | awk '{print $2}')
  # Not just "equal": a newer one from elsewhere (omarchy's repo, a later AUR
  # package) is kept rather than downgraded to the vendored copy.
  if [ -n "$HAVE" ] && [ "$(vercmp "$HAVE" "$WANT")" -ge 0 ]; then
    echo "${INFO} ${MAGENTA}$PKG${RESET} $HAVE is already installed. Skipping..." | tee -a "$LOG"
    clear_package_failure "$PKG"
    clear_package_failure "$PKG-$WANT"
    continue
  fi

  printf "\n%s - Building ${SKY_BLUE}$PKG $WANT${RESET} from the vendored PKGBUILD .... \n" "${NOTE}"
  # Built in a temp dir, never in the repo: makepkg writes src/, pkg/ and the
  # source tarball next to the PKGBUILD (see yay.sh).
  TMPD=$(mktemp -d) || { record_package_failure "$PKG"; continue; }
  cp -r "$SRC/." "$TMPD/"

  # -s pulls the build and runtime deps (qt6-multimedia for omacut) from the
  # repos. Built with -s and installed separately, as yay.sh does, so a failed
  # install can be told apart from a failed build. -f: a package of the same
  # version left in a persistent PKGDEST must not stop the build.
  ( cd "$TMPD" && makepkg -sf --noconfirm 2>&1 ) | tee -a "$LOG"
  # tee is last in the pipeline: PIPESTATUS[0] is makepkg's status.
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo "${ERROR} Failed to build $PKG. See $LOG." | tee -a "$LOG"
    record_package_failure "$PKG"
    rm -rf "$TMPD"
    continue
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
  else
    echo "${ERROR} Built $PKG, but found no package file to install." | tee -a "$LOG"
  fi
  mv "$TMPD"/*.log "$PARENT_DIR/Install-Logs/" 2>/dev/null || true
  rm -rf "$TMPD"

  # Installed at the version just built, not merely installed: after a failed
  # update (a file conflict, the pacman lock held) the previous build is still
  # there, and reading that as success cleared the failure and let the preset
  # reboot on the old build.
  NOW=$(pacman -Q "$PKG" 2>/dev/null | awk '{print $2}')
  if [ "$NOW" = "$WANT" ]; then
    echo "${OK} Package ${YELLOW}$PKG${RESET} $WANT has been successfully installed!" | tee -a "$LOG"
    clear_package_failure "$PKG"
    clear_package_failure "$PKG-$WANT"
  elif [ -n "$NOW" ]; then
    echo "${ERROR} ${YELLOW}$PKG${RESET} $WANT did not install - $NOW is still the one installed. See $LOG." | tee -a "$LOG"
    # Recorded with the version: the final check re-verifies each name with
    # pacman, and plain "$PKG" is installed.
    record_package_failure "$PKG-$WANT"
  else
    echo "${ERROR} ${YELLOW}$PKG${RESET} failed to install. See $LOG." | tee -a "$LOG"
    record_package_failure "$PKG"
  fi
done

printf "\n${NOTE} ${SKY_BLUE}omawrite${RESET} and ${SKY_BLUE}omacut${RESET} are in the app launcher. Update them by bumping ${MAGENTA}pkgbuilds/<name>/PKGBUILD${RESET} and re-running ${MAGENTA}install-scripts/omarchy-apps.sh${RESET}.\n"
printf "\n%.0s" {1..2}
