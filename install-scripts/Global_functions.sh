#!/bin/bash
# Global Functions for Scripts #

set -e

# Colour, via a wrapper that cannot fail.
#
# These used to be bare `$(tput setaf N)`. tput exits non-zero on a terminal
# with no colour capability - TERM=dumb, or TERM unset, which is what a serial
# console, a cron/systemd context or CI gives you - and with `set -e` directly
# above, that non-zero status killed the script *sourcing* this file at line 7,
# before it ran a single line of its own and with nothing printed. install.sh
# has the same colour block but no set -e, so it survived: the installer would
# appear to run normally while every one of its sub-scripts silently did
# nothing. Verified: TERM=xterm-256color and TERM=linux source fine, TERM=dumb
# and TERM unset died silently.
#
# _tput swallows both the output and the status, so a colourless terminal just
# gets uncoloured text.
_tput() { tput "$@" 2>/dev/null || true; }

OK="$(_tput setaf 2)[OK]$(_tput sgr0)"
ERROR="$(_tput setaf 1)[ERROR]$(_tput sgr0)"
NOTE="$(_tput setaf 3)[NOTE]$(_tput sgr0)"
INFO="$(_tput setaf 4)[INFO]$(_tput sgr0)"
WARN="$(_tput setaf 1)[WARN]$(_tput sgr0)"
CAT="$(_tput setaf 6)[ACTION]$(_tput sgr0)"
MAGENTA="$(_tput setaf 5)"
ORANGE="$(_tput setaf 214)"
WARNING="$(_tput setaf 1)"
YELLOW="$(_tput setaf 3)"
GREEN="$(_tput setaf 2)"
BLUE="$(_tput setaf 4)"
SKY_BLUE="$(_tput setaf 6)"
RESET="$(_tput sgr0)"

# Create Directory for Install Logs
if [ ! -d Install-Logs ]; then
    mkdir Install-Logs
fi

# Manifest of packages that failed to install, read by 02-Final-Check.sh.
#
# Each install_* function below already double-checks its package and prints an
# error on a miss, but printing was all it did: the message scrolls past, the
# install carries on, and a preset run reboots 15 seconds later into a desktop
# that is quietly missing pieces. Recording every failure here gives the final
# check a complete picture - every package actually attempted by any script,
# rather than the short hardcoded list it used to be limited to.
#
# The path is relative to the repo root, which every install script cd's into
# before sourcing this file. install.sh truncates it at the start of each run,
# so a failure from a previous install is never reported against this one.
FAILED_PACKAGES_MANIFEST="Install-Logs/.failed-packages"

record_package_failure() {
  echo "$1" >> "$FAILED_PACKAGES_MANIFEST"
}

# Packages that failed makepkg's source integrity check rather than failing to
# build. Kept apart from the manifest above because the two need different
# advice: a build failure is usually a missing dependency or a compiler error,
# while a checksum failure is almost always an upstream tarball that was
# regenerated - and the fix for it is a flag, not a code change. 02-Final-Check.sh
# reports these separately with the exact command to run.
CHECKSUM_FAILURES_MANIFEST="Install-Logs/.checksum-failures"

record_checksum_failure() {
  echo "$1" >> "$CHECKSUM_FAILURES_MANIFEST"
}

# Packages allowed to rebuild with integrity verification off. See the file
# itself for what that means and what to check before adding a name.
CHECKSUM_SKIP_LIST="install-scripts/checksum-skip.conf"

checksum_skip_allowed() {
  [ -f "$CHECKSUM_SKIP_LIST" ] || return 1
  grep -vE '^[[:space:]]*(#|$)' "$CHECKSUM_SKIP_LIST" 2>/dev/null \
    | tr -d '[:blank:]' | grep -qx "$1"
}

# Did THIS package's slice of the log show a checksum failure?
#
# The offset matters: $LOG is appended to by every package in the run, so
# grepping the whole file would blame the current package for a mismatch that
# happened twenty packages ago. Callers record the log size before they start
# and pass it in.
#
# Matches makepkg's own wording (integrity/verify_checksum.sh). A PGP failure
# prints "One or more PGP signatures could not be verified!" instead - that is
# a different problem which --skipchecksums does not address, so it is
# deliberately not matched here.
#
# The English wording is guaranteed because every AUR call below runs under
# LC_ALL=C.UTF-8 (see AUR_ENV): makepkg translates that message, so on a Swedish or
# Spanish system the log never contained it and the retry never fired.
log_shows_checksum_failure() {
  local from="${1:-0}"
  [ -f "$LOG" ] || return 1
  tail -c "+$((from + 1))" "$LOG" 2>/dev/null \
    | grep -q 'did not pass the validity check'
}

# Name(s) of the package(s) whose validity check failed in this slice.
#
# Not always the package that was asked for: the helper builds AUR dependencies
# on the way, and a mismatch in one of those used to be blamed on the parent -
# the allowlist was checked against the wrong name, and the final screen told
# you to turn checksums off for a package whose checksums were fine. makepkg
# announces each build with "==> Making package: <name> <version>", so the
# failure belongs to the last one announced before it.
checksum_failed_packages() {
  local from="${1:-0}"
  [ -f "$LOG" ] || return 0
  tail -c "+$((from + 1))" "$LOG" 2>/dev/null \
    | sed 's/\x1b\[[0-9;]*m//g' \
    | awk '/==> Making package: / { for (i = 1; i <= NF; i++) if ($i == "package:") { name = $(i + 1); break } }
           /did not pass the validity check/ && name != "" { print name; name = "" }' \
    | awk '!seen[$0]++'
}

# Current size of $LOG, for the offset above.
log_mark() {
  stat -c %s "$LOG" 2>/dev/null || echo 0
}

# Retry one package with --skipchecksums, but only if it is allowlisted.
# Returns 0 if the package is installed afterwards.
retry_without_checksums() {
  local asked="$1" mark="$2" pkg

  log_shows_checksum_failure "$mark" || return 1

  # The package whose checksum failed - the one asked for, or a dependency the
  # helper was building for it. Fall back to the asked-for name if the log does
  # not say (it always should under AUR_ENV).
  pkg=$(checksum_failed_packages "$mark" | tail -1)
  [ -n "$pkg" ] || pkg="$asked"
  if [ "$pkg" != "$asked" ]; then
    echo -e "\n${NOTE} The checksum failure is in ${YELLOW}${pkg}${RESET}, a dependency of ${YELLOW}${asked}${RESET}."
  fi

  if ! checksum_skip_allowed "$pkg"; then
    echo -e "\n${WARN} ${YELLOW}${pkg}${RESET} failed its ${YELLOW}source checksum${RESET}, not its build."
    echo -e "${NOTE} The downloaded source does not match what the AUR PKGBUILD pins. Usually an"
    echo -e "${NOTE} upstream tarball that was regenerated - but verify before assuming that."
    echo -e "${NOTE} Check it, then either build it by hand:"
    echo -e "${NOTE}   ${MAGENTA}$(basename "${ISAUR:-yay}") -S ${pkg} --mflags --skipchecksums${RESET}"
    echo -e "${NOTE} or add ${MAGENTA}${pkg}${RESET} to ${MAGENTA}${CHECKSUM_SKIP_LIST}${RESET} to let re-runs do it."
    record_checksum_failure "$pkg"
    return 1
  fi

  echo -e "\n${WARN} ${YELLOW}${pkg}${RESET} failed its source checksum."
  echo -e "${NOTE} It is listed in ${MAGENTA}${CHECKSUM_SKIP_LIST}${RESET}, so rebuilding it with"
  echo -e "${NOTE} ${YELLOW}integrity verification disabled for this package${RESET}."
  {
    echo "=== checksum override: rebuilding $pkg with --skipchecksums ==="
    echo "=== allowlisted in $CHECKSUM_SKIP_LIST ==="
  } >> "$LOG"

  (
    stdbuf -oL env $AUR_ENV $ISAUR -S --noconfirm --mflags --skipchecksums "$pkg" 2>&1
  ) >> "$LOG" 2>&1 &
  local pid=$!
  show_progress "$pid" "$pkg (--skipchecksums)"

  if $ISAUR -Q "$pkg" &>/dev/null; then
    echo -e "${OK} ${YELLOW}${pkg}${RESET} installed with checksums skipped."
    # A dependency was the problem: now build what was actually asked for,
    # with verification ON - only the allowlisted package gets the override.
    if [ "$pkg" != "$asked" ]; then
      (
        stdbuf -oL env $AUR_ENV $ISAUR -S --noconfirm "$asked" 2>&1
      ) >> "$LOG" 2>&1 &
      pid=$!
      show_progress "$pid" "$asked"
      $ISAUR -Q "$asked" &>/dev/null && return 0
      return 1
    fi
    return 0
  fi
  echo -e "${ERROR} ${YELLOW}${pkg}${RESET} still failed with checksums skipped - this is not just a stale checksum."
  record_checksum_failure "$pkg"
  return 1
}

# Show progress function
show_progress() {
    local pid=$1
    local package_name=$2
    local spin_chars=("●○○○○○○○○○" "○●○○○○○○○○" "○○●○○○○○○○" "○○○●○○○○○○" "○○○○●○○○○" \
                      "○○○○○●○○○○" "○○○○○○●○○○" "○○○○○○○●○○" "○○○○○○○○●○" "○○○○○○○○○●") 
    local i=0

    _tput civis
    printf "\r${NOTE} Installing ${YELLOW}%s${RESET} ..." "$package_name"

    while ps -p $pid &> /dev/null; do
        printf "\r${NOTE} Installing ${YELLOW}%s${RESET} %s" "$package_name" "${spin_chars[i]}"
        i=$(( (i + 1) % 10 ))  
        sleep 0.3  
    done

    printf "\r${NOTE} Installing ${YELLOW}%s${RESET} ... Done!%-20s \n" "$package_name" ""
    _tput cnorm
}



# Function to install packages with pacman
install_package_pacman() {
  # Check if package is already installed
  if pacman -Q "$1" &>/dev/null ; then
    echo -e "${INFO} ${MAGENTA}$1${RESET} is already installed. Skipping..."
  else
    # Run pacman and redirect all output to a log file
    (
      stdbuf -oL sudo pacman -S --noconfirm "$1" 2>&1
    ) >> "$LOG" 2>&1 &
    PID=$!
    show_progress $PID "$1" 

    # Double check if package is installed
    if pacman -Q "$1" &>/dev/null ; then
      echo -e "${OK} Package ${YELLOW}$1${RESET} has been successfully installed!"
    else
      echo -e "\n${ERROR} ${YELLOW}$1${RESET} failed to install. Please check the $LOG. You may need to install manually."
      record_package_failure "$1"
    fi
  fi
}

# `|| true` is load-bearing. This file starts with `set -e`, and on a machine
# with no AUR helper yet both `command -v` calls fail, so the assignment's
# status is 1 and set -e kills whichever script is sourcing this file - before
# it has run a single line of its own, with no message. Any script that runs
# before yay.sh and sources this with a bare `source` (locales.sh did) simply
# never happened on a fresh install: the Russian locale was not generated, and
# the clock, calendar and lock screen quietly fell back to C.
ISAUR=$(command -v yay || command -v paru || true)
# The environment every AUR helper call runs under. LC_ALL=C.UTF-8 (built into
# glibc, so always present; UTF-8 so builds that expect it still work) makes
# makepkg print
# its messages in English, which the checksum-failure detection above greps
# for; LANGUAGE is cleared because gettext would otherwise still honour it.
AUR_ENV="LC_ALL=C.UTF-8 LANGUAGE="
# Function to install packages with either yay or paru
install_package() {
  if $ISAUR -Q "$1" &>> /dev/null ; then
    echo -e "${INFO} ${MAGENTA}$1${RESET} is already installed. Skipping..."
  else
    local _mark; _mark=$(log_mark)
    (
      stdbuf -oL env $AUR_ENV $ISAUR -S --noconfirm "$1" 2>&1
    ) >> "$LOG" 2>&1 &
    PID=$!
    show_progress $PID "$1"  

    # A build that failed its source checksum gets one allowlisted retry with
    # verification off; anything else is reported and left alone.
    if ! $ISAUR -Q "$1" &>>/dev/null; then
      retry_without_checksums "$1" "$_mark" || true
    fi

    # Double check if package is installed
    if $ISAUR -Q "$1" &>> /dev/null ; then
      echo -e "${OK} Package ${YELLOW}$1${RESET} has been successfully installed!"
    else
      # Something is missing, exiting to review log
      echo -e "\n${ERROR} ${YELLOW}$1${RESET} failed to install :( , please check the install.log. You may need to install manually! Sorry I have tried :("
      record_package_failure "$1"
    fi
  fi
}

# Function to just install packages with either yay or paru without checking if installed
install_package_f() {
  local _mark; _mark=$(log_mark)
  (
    stdbuf -oL env $AUR_ENV $ISAUR -S --noconfirm "$1" 2>&1
  ) >> "$LOG" 2>&1 &
  PID=$!
  show_progress $PID "$1"  

  if ! $ISAUR -Q "$1" &>>/dev/null; then
    retry_without_checksums "$1" "$_mark" || true
  fi

  # Double check if package is installed
  if $ISAUR -Q "$1" &>> /dev/null ; then
    echo -e "${OK} Package ${YELLOW}$1${RESET} has been successfully installed!"
  else
    # Something is missing, exiting to review log
    echo -e "\n${ERROR} ${YELLOW}$1${RESET} failed to install :( , please check the install.log. You may need to install manually! Sorry I have tried :("
    record_package_failure "$1"
  fi
}


# Rebuild every initramfs. Returns non-zero on failure.
#
# CachyOS + Limine keeps its initramfs under /boot/<machine-id>/<kernel>/ and
# regenerates the hashed limine.conf entries through a mkinitcpio post hook
# (limine-mkinitcpio-hook), so a plain `mkinitcpio -P` is fine there too -
# plymouth.sh relies on exactly that. limine-mkinitcpio is simply the distro's
# front door for the same rebuild, so prefer it where it exists.
rebuild_initramfs() {
  local log="${1:-$LOG}"
  printf "${INFO} Rebuilding ${YELLOW}Initramfs${RESET}...\n" 2>&1 | tee -a "$log"
  if command -v limine-mkinitcpio &>/dev/null; then
    sudo limine-mkinitcpio 2>&1 | tee -a "$log"
  else
    sudo mkinitcpio -P 2>&1 | tee -a "$log"
  fi
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo "${ERROR} initramfs rebuild failed - check $log" | tee -a "$log"
    return 1
  fi
}

# Function for removing packages
uninstall_package() {
  local pkg="$1"

  # Checking if package is installed
  if pacman -Qi "$pkg" &>/dev/null; then
    echo -e "${NOTE} removing $pkg ..."
    sudo pacman -R --noconfirm "$pkg" 2>&1 | tee -a "$LOG" | grep -v "error: target not found"
    
    if ! pacman -Qi "$pkg" &>/dev/null; then
      echo -e "\e[1A\e[K${OK} $pkg removed."
    else
      echo -e "\e[1A\e[K${ERROR} $pkg Removal failed. No actions required."
      return 1
    fi
  else
    echo -e "${INFO} Package $pkg not installed, skipping."
  fi
  return 0
}