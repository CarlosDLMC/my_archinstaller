#!/bin/bash
# The desktop bar: rust-bar, built from this repo's rust-bar/ crate with
# pkgbuilds/rust-bar. The bar strip, its cards, the overview (SUPER+A), the
# wallpaper carousel, the clipboard history, the screenshot/record dialogs,
# the power menu, the polkit agent and the CRT power-off are all this one
# binary. Its scripts and the wallust palette live in ~/.config/rust-bar
# (dots).
#
# The package's version is the crate's plus a hash of the crate (0.1.0.<hash>);
# a re-run builds again only when the crate changed since.

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

# A failure is recorded under this name, not the package's: 02-Final-Check.sh
# drops every name `pacman -Qi` finds, so with an older build still installed
# a failed rebuild passed the final check and the preset rebooted onto the old
# bar. mango-patched.sh records "mangowm-patched" for the same reason.
FAIL=rust-bar-build
HAVE=$(pacman -Q "$PKG" 2>/dev/null | awk '{print $2}')
if [ -n "$HAVE" ]; then
  LEFT="the installed rust-bar $HAVE stays"
else
  LEFT="the desktop has no bar"
fi

if [ ! -f "$SRC/PKGBUILD" ] || [ ! -f "$CRATE/Cargo.toml" ]; then
  echo "${ERROR} No rust-bar crate or PKGBUILD in the repo - $LEFT." | tee -a "$LOG"
  record_package_failure "$FAIL"
  exit 0
fi

# The bar draws with Vulkan. graphics.sh (and nvidia.sh, which runs before this
# one) installed a driver for every GPU it recognised; a virtual machine gets
# none, so Mesa's software Vulkan (lavapipe) stands in there. Any virtual
# machine, not only one without a driver file: a base install that brought
# vulkan-intel or vulkan-radeon along leaves their files here with no device
# behind them, and the bar then finds no adapter and exits at its first frame.
# A real or virtual GPU still wins - the bar takes the CPU adapter only when
# there is no other.
if systemd-detect-virt --vm --quiet \
   || ! ls /usr/share/vulkan/icd.d/*.json /etc/vulkan/icd.d/*.json 2>/dev/null | grep -qv 'lvp_icd'; then
  echo "${NOTE} No Vulkan driver for this GPU (or a virtual machine) - installing Mesa's software Vulkan for the bar." | tee -a "$LOG"
  install_package vulkan-swrast "$LOG"
fi

# A driver file is not a device: Sandy Bridge and older Intel with
# vulkan-intel, a GCN 1/2 card on radeon.ko, an NVIDIA card or module the
# driver does not take. Only Vulkan can tell: `rust-bar gpu-check` asks it for
# the adapter the bar would draw with (exit 1 when there is none). Then Mesa's
# software Vulkan too, which the bar takes when there is no other adapter.
# This only adds lavapipe and never fails the final check. Not right after
# nvidia.sh in this run: its module loads with the reboot, and the NVIDIA
# device is not there before it.
gpu_check() {
  command -v rust-bar >/dev/null 2>&1 || return 0
  if [[ " ${INSTALL_SELECTED_OPTIONS:-} " == *" nvidia "* ]] && [ ! -d /sys/module/nvidia ]; then
    return 0
  fi
  if ! timeout 30 rust-bar gpu-check >>"$LOG" 2>&1; then
    echo "${NOTE} Vulkan has no GPU the bar can draw with - installing Mesa's software Vulkan for it." | tee -a "$LOG"
    install_package vulkan-swrast "$LOG"
  fi
}

# The version: the crate's own, then a hash of every file of the crate in a
# fixed order, so the build is redone when any of them changed. pkgrel stays 1.
CRATE_VER=$(sed -n 's/^version *= *"\(.*\)"/\1/p' "$CRATE/Cargo.toml" | head -n1)
HASH=$( cd "$CRATE" && find . -path ./target -prune -o -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -c1-12 )
WANT="${CRATE_VER:-0}.${HASH}-1"
if [ "$HAVE" = "$WANT" ]; then
  echo "${INFO} ${MAGENTA}rust-bar${RESET} $HAVE is already built from this crate. Skipping..." | tee -a "$LOG"
  clear_package_failure "$FAIL"
  gpu_check
  exit 0
fi

printf "\n%s - Building ${SKY_BLUE}rust-bar${RESET} (the desktop bar) from rust-bar/ - a few minutes .... \n" "${NOTE}"
# Built in a temp dir, never in the repo: makepkg writes src/, pkg/ and the
# sources next to the PKGBUILD (see yay.sh). The crate goes in as a tarball,
# the PKGBUILD's only source.
if ! TMPD=$(mktemp -d) || ! cp -r "$SRC/." "$TMPD/" \
   || ! sed -i "s/^pkgver=.*/pkgver=${WANT%-1}/" "$TMPD/PKGBUILD" \
   || ! tar -C "$PARENT_DIR" --exclude=rust-bar/target -czf "$TMPD/rust-bar.tar.gz" rust-bar; then
  echo "${ERROR} Could not set up a build directory for rust-bar (a full /tmp?) - $LEFT." | tee -a "$LOG"
  record_package_failure "$FAIL"
  [ -n "${TMPD:-}" ] && rm -rf "$TMPD"
  exit 0
fi

# -s pulls the build deps (cargo, clang) from the repos. -f: a package of the
# same version left in a persistent PKGDEST must not stop the build.
( cd "$TMPD" && makepkg -sf --noconfirm 2>&1 ) | tee -a "$LOG"
# tee is last in the pipeline: PIPESTATUS[0] is makepkg's status.
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
  echo "${ERROR} Failed to build rust-bar - $LEFT. See $LOG." | tee -a "$LOG"
  record_package_failure "$FAIL"
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

# The version is a hash, so it can sort below the installed one: pacman -U
# then only warns that it is downgrading, and installs it.
if [ ${#BUILT[@]} -gt 0 ]; then
  sudo pacman -U --noconfirm "${BUILT[@]}" 2>&1 | tee -a "$LOG"
fi
mv "$TMPD"/*.log "$PARENT_DIR/Install-Logs/" 2>/dev/null || true
rm -rf "$TMPD"

if [ "$(pacman -Q "$PKG" 2>/dev/null | awk '{print $2}')" = "$WANT" ]; then
  echo "${OK} ${YELLOW}rust-bar${RESET} $WANT is installed." | tee -a "$LOG"
  clear_package_failure "$FAIL"
  gpu_check
else
  echo "${ERROR} rust-bar did not install - $LEFT. See $LOG." | tee -a "$LOG"
  record_package_failure "$FAIL"
fi

printf "\n%.0s" {1..1}
