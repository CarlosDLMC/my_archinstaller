#!/bin/bash
# Paru AUR Helper #
# NOTE: If yay is already installed, paru will not be installed #

# `paru`, built from source - not paru-bin. The prebuilt release binary is linked
# against a specific libalpm soname (paru-bin 2.1.0 wants libalpm.so.15) while
# its PKGBUILD only asks for libalpm.so>=14, so after a pacman bump it installs
# cleanly and then cannot start: every AUR install after it fails. Building from
# source links against the libalpm on this machine. Slower (it pulls in rust as
# a make dependency), but it works.
pkg="paru"

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
# Anchor to the repo root rather than trusting the caller's cwd.
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "Failed to change directory to $PARENT_DIR"; exit 1; }

# Set the name of the log file to include the current date and time
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_paru.log"

# Set some colors for output messages
OK="$(tput setaf 2)[OK]$(tput sgr0)"
ERROR="$(tput setaf 1)[ERROR]$(tput sgr0)"
NOTE="$(tput setaf 3)[NOTE]$(tput sgr0)"
INFO="$(tput setaf 4)[INFO]$(tput sgr0)"
WARN="$(tput setaf 1)[WARN]$(tput sgr0)"
CAT="$(tput setaf 6)[ACTION]$(tput sgr0)"
MAGENTA="$(tput setaf 5)"
ORANGE="$(tput setaf 214)"
WARNING="$(tput setaf 1)"
YELLOW="$(tput setaf 3)"
GREEN="$(tput setaf 2)"
BLUE="$(tput setaf 4)"
SKY_BLUE="$(tput setaf 6)"
RESET="$(tput sgr0)"

# Create Directory for Install Logs
if [ ! -d Install-Logs ]; then
    mkdir Install-Logs
fi

# Check for AUR helper and install if not found
# A helper that is on PATH but does not start (libalpm soname bump) is not
# "already installed" - it is the case this script exists to fix.
ISAUR=""
for _h in yay paru; do
  if command -v "$_h" &>/dev/null && "$_h" --version &>/dev/null; then
    ISAUR=$(command -v "$_h")
    break
  fi
done
if [ -n "$ISAUR" ]; then
  printf "\n%s - ${SKY_BLUE}AUR helper${RESET} already installed, moving on.\n" "${OK}"
else
  printf "\n%s - Installing ${SKY_BLUE}$pkg${RESET} from AUR\n" "${NOTE}"

  # Clone and build in a temp dir, never in the repo. This used to clone into
  # the repo root and build there, which left an untracked $pkg/ directory
  # plus makepkg's pkg/ and src/ output sitting in the working tree.
  TMP_ROOT="$(mktemp -d)" || { printf "%s - Failed to create a temporary build directory\n" "${ERROR}"; exit 1; }
  trap 'rm -rf "$TMP_ROOT"' EXIT
  BUILD_DIR="$TMP_ROOT/$pkg"

  git clone "https://aur.archlinux.org/$pkg.git" "$BUILD_DIR" || { printf "%s - Failed to clone ${YELLOW}$pkg${RESET} from AUR\n" "${ERROR}"; exit 1; }

  # Subshell, so a failed cd cannot leave the rest of the script running from
  # the wrong directory.
  #
  # Built with -s, installed separately: `makepkg -si` hands the package to
  # `pacman -U --noconfirm`, and when a broken helper of the same family is
  # installed (paru-bin, paru-git - the libalpm soname case this script now rebuilds for) pacman
  # asks "Remove it? [y/N]" and --noconfirm takes the N. The build finished and
  # the install failed every time. The conflicting package is removed only
  # after the build succeeded, so a failed build never leaves less than before.
  (
    cd "$BUILD_DIR" || exit 1
    # -f: with PKGDEST set to a folder that persists, a package of the same
    # version already there made -s stop with "A package has already been built"
    # (and the old -si reinstalled that stale package - for a paru broken by a
    # libalpm bump, the broken one). Always a fresh build.
    makepkg -sf --noconfirm 2>&1
  ) | tee -a "$LOG"

  # tee is last in the pipeline, so ${PIPESTATUS[0]} is makepkg's status, not
  # tee's. Checking $? here would report success on every failed build.
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    printf "%s - Failed to build ${YELLOW}$pkg${RESET}\n" "${ERROR}"
    exit 1
  fi

  # --packagelist, not a glob: makepkg.conf may set PKGDEST elsewhere.
  _built=()
  while IFS= read -r _p; do
    case "${_p##*/}" in *-debug-*) continue ;; esac
    if [ -f "$_p" ]; then
      _built+=("$_p")
    fi
  done < <(cd "$BUILD_DIR" && makepkg --packagelist 2>/dev/null)
  if [ ${#_built[@]} -eq 0 ]; then
    printf "%s - Built ${YELLOW}$pkg${RESET}, but found no package file to install\n" "${ERROR}"
    exit 1
  fi
  _conflicting=()
  for _c in paru-bin paru-git; do
    # Exact name: pacman -Q also answers for a package that merely provides
    # it (`pacman -Q yay` prints yay-bin).
    if [ "$(pacman -Qq "$_c" 2>/dev/null)" = "$_c" ]; then
      _conflicting+=("$_c")
    fi
  done
  if [ ${#_conflicting[@]} -gt 0 ]; then
    printf "%s - Removing ${YELLOW}${_conflicting[*]}${RESET}, which conflicts with $pkg\n" "${NOTE}" | tee -a "$LOG"
    sudo pacman -Rdd --noconfirm "${_conflicting[@]}" 2>&1 | tee -a "$LOG"
  fi
  sudo pacman -U --noconfirm "${_built[@]}" 2>&1 | tee -a "$LOG"
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    printf "%s - Failed to install ${YELLOW}$pkg${RESET}\n" "${ERROR}"
    exit 1
  fi

  # Built is not the same as working - see the note on pkg above.
  if ! paru --version >/dev/null 2>&1; then
    printf "%s - ${YELLOW}$pkg${RESET} installed but does not run:\n" "${ERROR}"
    paru --version 2>&1 | head -3
    exit 1
  fi

  # Keep any makepkg logs; the temp dir is about to be removed.
  mv "$BUILD_DIR"/*.log "$PARENT_DIR/Install-Logs/" 2>/dev/null || true

  rm -rf "$TMP_ROOT"
  trap - EXIT
fi

# No `-Syu` here, for the same reason as in yay.sh: pacman.sh ran a full
# upgrade moments before, and this script only runs when no AUR helper existed
# yet, so there are no foreign packages to upgrade besides the paru just built.

printf "\n%.0s" {1..2}