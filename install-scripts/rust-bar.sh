#!/bin/bash
# The desktop bar: rust-bar, built from this repo's rust-bar/ crate with
# pkgbuilds/rust-bar. It replaces quickshell - the bar strip, its cards, the
# overview (SUPER+A), the wallpaper carousel, the clipboard history, the
# screenshot/record dialogs, the power menu, the polkit agent and the CRT
# power-off are all this one binary now. Its scripts and the wallust palette
# stay where the QML bar had them, in ~/.config/quickshell/bar (dots).
#
# The package records a hash of the crate it was built from; a re-run builds
# again only when the crate changed since.

PKG=rust-bar

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "[ERROR] Failed to change directory to $PARENT_DIR"; exit 1; }

if ! source "$SCRIPT_DIR/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_rust-bar.log"
SRC="$PARENT_DIR/pkgbuilds/$PKG"
CRATE="$PARENT_DIR/rust-bar"

if [ ! -f "$SRC/PKGBUILD" ] || [ ! -f "$CRATE/Cargo.toml" ]; then
  echo "${ERROR} No rust-bar crate or PKGBUILD in the repo - the desktop has no bar." | tee -a "$LOG"
  record_package_failure "$PKG"
  exit 0
fi

# The bar draws with Vulkan. graphics.sh (and nvidia.sh, which runs before this
# one) installed a driver for every GPU it recognised; a virtual machine gets
# none, so Mesa's software Vulkan (lavapipe) stands in there.
if ! ls /usr/share/vulkan/icd.d/*.json /etc/vulkan/icd.d/*.json 2>/dev/null | grep -qv 'lvp_icd'; then
  echo "${NOTE} No Vulkan driver for this GPU - installing Mesa's software Vulkan for the bar." | tee -a "$LOG"
  install_package vulkan-swrast "$LOG"
fi

# Every file of the crate, in a fixed order: the build is redone when any of them changed.
WANT=$( cd "$CRATE" && find . -path ./target -prune -o -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -c1-16 )
HAVE=$(cat /usr/share/rust-bar/source 2>/dev/null || true)
if pacman -Q "$PKG" &>/dev/null && [ "$HAVE" = "$WANT" ]; then
  echo "${INFO} ${MAGENTA}rust-bar${RESET} is already built from this crate ($WANT). Skipping..." | tee -a "$LOG"
  clear_package_failure "$PKG"
  exit 0
fi

printf "\n%s - Building ${SKY_BLUE}rust-bar${RESET} (the desktop bar) from rust-bar/ - a few minutes .... \n" "${NOTE}"
# Built in a temp dir, never in the repo: makepkg writes src/, pkg/ and the
# sources next to the PKGBUILD (see yay.sh). The crate goes in as a tarball,
# the PKGBUILD's only source.
if ! TMPD=$(mktemp -d) || ! cp -r "$SRC/." "$TMPD/" \
   || ! tar -C "$PARENT_DIR" --exclude=rust-bar/target -czf "$TMPD/rust-bar.tar.gz" rust-bar; then
  echo "${ERROR} Could not set up a build directory for rust-bar (a full /tmp?) - the desktop has no bar." | tee -a "$LOG"
  record_package_failure "$PKG"
  [ -n "${TMPD:-}" ] && rm -rf "$TMPD"
  exit 0
fi

# -s pulls the build deps (cargo, clang) from the repos. -f: a package of the
# same version left in a persistent PKGDEST must not stop the build.
( cd "$TMPD" && RUST_BAR_SOURCE="$WANT" makepkg -sf --noconfirm 2>&1 ) | tee -a "$LOG"
# tee is last in the pipeline: PIPESTATUS[0] is makepkg's status.
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
  echo "${ERROR} Failed to build rust-bar - the desktop has no bar. See $LOG." | tee -a "$LOG"
  record_package_failure "$PKG"
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

if [ "$(cat /usr/share/rust-bar/source 2>/dev/null || true)" = "$WANT" ]; then
  echo "${OK} ${YELLOW}rust-bar${RESET} is installed." | tee -a "$LOG"
  clear_package_failure "$PKG"
else
  echo "${ERROR} rust-bar did not install - the desktop has no bar. See $LOG." | tee -a "$LOG"
  record_package_failure "$PKG"
fi

printf "\n%.0s" {1..1}
