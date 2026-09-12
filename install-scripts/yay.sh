#!/bin/bash
# Yay AUR Helper #
# NOTE: If paru is already installed, yay will not be installed #

pkg="yay-bin"

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
# Anchor to the repo root rather than trusting the caller's cwd, so the vendored
# PKGBUILD and Install-Logs/ are found wherever this is invoked from.
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "Failed to change directory to $PARENT_DIR"; exit 1; }

# Set the name of the log file to include the current date and time
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_yay.log"

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
ISAUR=$(command -v yay || command -v paru)
if [ -n "$ISAUR" ]; then
  printf "\n%s - ${SKY_BLUE}AUR helper${RESET} already installed, moving on.\n" "${OK}"
else
  # Build from the yay-bin/ PKGBUILD vendored in this repo, which is what the
  # README and install.sh both promise. This block used to `rm -rf "$pkg"` and
  # clone from aur.archlinux.org instead, with cwd at the repo root - so it
  # deleted the tracked yay-bin/PKGBUILD and .SRCINFO, left the working tree
  # dirty (which the next auto-install.sh then refuses to `git pull` over), and
  # made bootstrapping depend on the AUR being reachable. The vendored copy was
  # never once used.
  #
  # The build runs in a temp dir, never in the repo: makepkg writes pkg/, src/
  # and the built package next to the PKGBUILD, and those landing in the repo
  # is the only reason they are in .gitignore at all.
  TMP_ROOT="$(mktemp -d)" || { printf "%s - Failed to create a temporary build directory\n" "${ERROR}"; exit 1; }
  trap 'rm -rf "$TMP_ROOT"' EXIT
  BUILD_DIR="$TMP_ROOT/$pkg"

  if [ -f "$PARENT_DIR/$pkg/PKGBUILD" ]; then
    printf "\n%s - Building ${SKY_BLUE}$pkg${RESET} from the vendored PKGBUILD\n" "${NOTE}"
    mkdir -p "$BUILD_DIR"
    cp "$PARENT_DIR/$pkg/PKGBUILD" "$BUILD_DIR/" || { printf "%s - Failed to stage the vendored PKGBUILD\n" "${ERROR}"; exit 1; }
    # .SRCINFO is metadata only; makepkg does not need it, so a missing one is
    # not fatal.
    cp "$PARENT_DIR/$pkg/.SRCINFO" "$BUILD_DIR/" 2>/dev/null || true
  else
    printf "\n%s - No vendored PKGBUILD found. Cloning ${SKY_BLUE}$pkg${RESET} from the AUR\n" "${NOTE}"
    git clone "https://aur.archlinux.org/$pkg.git" "$BUILD_DIR" || { printf "%s - Failed to clone ${YELLOW}$pkg${RESET} from AUR\n" "${ERROR}"; exit 1; }
  fi

  # Subshell, so a failed cd cannot leave the rest of the script running from
  # the wrong directory.
  (
    cd "$BUILD_DIR" || exit 1
    makepkg -si --noconfirm 2>&1
  ) | tee -a "$LOG"

  # tee is last in the pipeline, so ${PIPESTATUS[0]} is makepkg's status, not
  # tee's. Checking $? here would report success on every failed build.
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    printf "%s - Failed to build and install ${YELLOW}$pkg${RESET}\n" "${ERROR}"
    exit 1
  fi

  # Keep any makepkg logs; the temp dir is about to be removed.
  mv "$BUILD_DIR"/*.log "$PARENT_DIR/Install-Logs/" 2>/dev/null || true

  rm -rf "$TMP_ROOT"
  trap - EXIT
fi

# Update system before proceeding
printf "\n%s - Performing a full system update to avoid issues.... \n" "${NOTE}"
ISAUR=$(command -v yay || command -v paru)

# PIPESTATUS, not the pipeline status: `cmd | tee` reports tee's exit code, so
# a failed system upgrade used to pass this check every time.
$ISAUR -Syu --noconfirm 2>&1 | tee -a "$LOG"
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
  printf "%s - Failed to update system\n" "${ERROR}"
  exit 1
fi

printf "\n%.0s" {1..2}