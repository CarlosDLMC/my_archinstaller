#!/bin/bash
# Paru AUR Helper #
# NOTE: If yay is already installed, paru will not be installed #

pkg="paru-bin"

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
ISAUR=$(command -v yay || command -v paru)
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

$ISAUR -Syu --noconfirm 2>&1 | tee -a "$LOG" || { printf "%s - Failed to update system\n" "${ERROR}"; exit 1; }

printf "\n%.0s" {1..2}