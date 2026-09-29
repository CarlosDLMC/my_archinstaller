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

# Scripts whose initramfs rebuild failed (see rebuild_initramfs). Truncated by
# install.sh per run and read by 02-Final-Check.sh as an outcome failure.
INITRAMFS_FAILED_MANIFEST="Install-Logs/.initramfs-failures"

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
#
# That <name> is the PKGBASE, not necessarily something you can install: a split
# PKGBUILD builds several packages under one base (pkgbase=foo -> foo-cli,
# python-foo), and `yay -S foo` then fails with "target not found". See
# pkgnames_for_base below for turning it back into installable names.
checksum_failed_packages() {
  local from="${1:-0}"
  [ -f "$LOG" ] || return 0
  tail -c "+$((from + 1))" "$LOG" 2>/dev/null \
    | sed 's/\x1b\[[0-9;]*m//g' \
    | awk '/==> Making package: / { for (i = 1; i <= NF; i++) if ($i == "package:") { name = $(i + 1); break } }
           /did not pass the validity check/ && name != "" { print name; name = "" }' \
    | awk '!seen[$0]++'
}

# Every dependency (runtime, make, check) of the given packages, recursively,
# one name per line, version constraints stripped. Used to work out which of a
# split base's packages the asked-for package actually needs. Bounded depth: a
# checksum failure is a few levels down at most, and each level is one -Si call.
aur_dep_closure() {
  local frontier="$*" seen=" $* " next dep depth=0
  printf '%s\n' "$@"
  while [ -n "$frontier" ] && [ "$depth" -lt 6 ]; do
    next=""
    # shellcheck disable=SC2086
    for dep in $(env $AUR_ENV $ISAUR -Si $frontier 2>/dev/null \
                   | sed -nE 's/^(Depends On|Make Deps|Check Deps) *: *//p' \
                   | tr -s ' ' '\n' | sed -E 's/[<>=].*//' | grep -vx 'None' || true); do
      [ -n "$dep" ] || continue
      [[ "$seen" == *" $dep "* ]] && continue
      seen+="$dep "; next+="$dep "
      echo "$dep"
    done
    frontier="$next"; depth=$((depth + 1))
  done
}

# The installable package name(s) behind a pkgbase whose checksum failed.
#
# The helper's clone of the AUR repo carries a .SRCINFO, whose top-level
# `pkgname =` lines are every package the base builds. Of those, the ones that
# matter are the asked-for package itself or whatever it depends on; failing
# that (nothing in the dependency tree matched), the ones not yet installed.
# Without a clone to read, the pkgbase is the best guess - it is the right answer
# for every non-split package, which is nearly all of them.
pkgnames_for_base() {
  local base="$1" asked="$2" srcinfo="" d names needed n
  for d in "${XDG_CACHE_HOME:-$HOME/.cache}/yay/$base" \
           "${XDG_CACHE_HOME:-$HOME/.cache}/paru/clone/$base"; do
    [ -f "$d/.SRCINFO" ] && { srcinfo="$d/.SRCINFO"; break; }
  done
  if [ -z "$srcinfo" ]; then
    echo "$base"; return 0
  fi
  names=$(sed -nE 's/^pkgname = ([^[:space:]]+).*/\1/p' "$srcinfo")
  [ -n "$names" ] || { echo "$base"; return 0; }
  if grep -qx -- "$asked" <<< "$names"; then
    echo "$asked"; return 0
  fi
  needed=$(grep -Fx -f <(aur_dep_closure "$asked") <<< "$names" || true)
  if [ -n "$needed" ]; then
    echo "$needed"; return 0
  fi
  for n in $names; do
    pacman -Q "$n" &>/dev/null || echo "$n"
  done
}

# Current size of $LOG, for the offset above.
log_mark() {
  stat -c %s "$LOG" 2>/dev/null || echo 0
}

# Retry one package with --skipchecksums, but only if it is allowlisted.
# Returns 0 if the package is installed afterwards.
retry_without_checksums() {
  local asked="$1" mark="$2" base targets t allowed=false all_in

  log_shows_checksum_failure "$mark" || return 1

  # The pkgbase whose checksum failed - the one asked for, or a dependency the
  # helper was building for it. Fall back to the asked-for name if the log does
  # not say (it always should under AUR_ENV).
  base=$(checksum_failed_packages "$mark" | tail -1)
  [ -n "$base" ] || base="$asked"
  # ...and the installable names behind it, for -S/-Q and for the final
  # screen's advice. A split base's own name is often not installable.
  mapfile -t targets < <(pkgnames_for_base "$base" "$asked" | awk 'NF && !seen[$0]++')
  [ ${#targets[@]} -gt 0 ] || targets=("$base")

  if [ "${targets[*]}" != "$asked" ]; then
    echo -e "\n${NOTE} The checksum failure is in ${YELLOW}${base}${RESET} (installs as: ${YELLOW}${targets[*]}${RESET}), needed by ${YELLOW}${asked}${RESET}."
  fi

  # Either name may be the one on the allowlist: the source belongs to the base,
  # and the conf has always been written in package names.
  checksum_skip_allowed "$base" && allowed=true
  for t in "${targets[@]}"; do checksum_skip_allowed "$t" && allowed=true; done

  if [ "$allowed" != true ]; then
    echo -e "\n${WARN} ${YELLOW}${base}${RESET} failed its ${YELLOW}source checksum${RESET}, not its build."
    echo -e "${NOTE} The downloaded source does not match what the AUR PKGBUILD pins. Usually an"
    echo -e "${NOTE} upstream tarball that was regenerated - but verify before assuming that."
    echo -e "${NOTE} Check it, then either build it by hand:"
    echo -e "${NOTE}   ${MAGENTA}$(basename "${ISAUR:-yay}") -S ${targets[*]} --mflags --skipchecksums${RESET}"
    echo -e "${NOTE} or add ${MAGENTA}${base}${RESET} to ${MAGENTA}${CHECKSUM_SKIP_LIST}${RESET} to let re-runs do it."
    for t in "${targets[@]}"; do record_checksum_failure "$t"; done
    return 1
  fi

  echo -e "\n${WARN} ${YELLOW}${base}${RESET} failed its source checksum."
  echo -e "${NOTE} It is listed in ${MAGENTA}${CHECKSUM_SKIP_LIST}${RESET}, so rebuilding it with"
  echo -e "${NOTE} ${YELLOW}integrity verification disabled for this package${RESET}."
  {
    echo "=== checksum override: rebuilding $base (${targets[*]}) with --skipchecksums ==="
    echo "=== allowlisted in $CHECKSUM_SKIP_LIST ==="
  } >> "$LOG"

  (
    stdbuf -oL env $AUR_ENV $ISAUR -S --noconfirm --mflags --skipchecksums "${targets[@]}" 2>&1
  ) >> "$LOG" 2>&1 &
  local pid=$!
  show_progress "$pid" "${targets[*]} (--skipchecksums)"

  all_in=true
  for t in "${targets[@]}"; do $ISAUR -Q "$t" &>/dev/null || all_in=false; done
  if [ "$all_in" = true ]; then
    echo -e "${OK} ${YELLOW}${targets[*]}${RESET} installed with checksums skipped."
    # A dependency was the problem: now build what was actually asked for,
    # with verification ON - only the allowlisted package gets the override.
    if ! printf '%s\n' "${targets[@]}" | grep -qx -- "$asked"; then
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
  echo -e "${ERROR} ${YELLOW}${base}${RESET} still failed with checksums skipped - this is not just a stale checksum."
  for t in "${targets[@]}"; do record_checksum_failure "$t"; done
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


# Is <hook> in the HOOKS mkinitcpio will actually use?
#
# Sourced in a subshell, the way mkinitcpio itself reads its config (the main
# file, then /etc/mkinitcpio.conf.d/*.conf in order), rather than grepped. A
# regex on `^HOOKS=(...)` missed a multi-line array and `HOOKS+=(plymouth)` in a
# drop-in, so ucode.sh told people to add a microcode initrd line to an entry
# that already had the hook, and plymouth="auto" resolved to OFF on a system
# that had plymouth set up. Same approach nvidia.sh uses for MODULES.
mkinitcpio_has_hook() {
  local hook="$1"
  bash -c '[ -f /etc/mkinitcpio.conf ] && source /etc/mkinitcpio.conf
           for f in /etc/mkinitcpio.conf.d/*.conf; do [ -f "$f" ] && source "$f"; done
           printf "%s\n" "${HOOKS[@]}"' 2>/dev/null | grep -qx -- "$hook"
}

# Where is limine.conf? Prints the first one found and returns 0, or prints
# nothing and returns 1. The one search every script uses: install.sh (the
# limine="auto" detection, in a child shell because it does not source this
# file), limine.sh, 02-Final-Check.sh, ucode.sh and plymouth.sh.
#
# Each of those used to carry its own copy of a five-path list, and every copy
# missed <ESP>/EFI/<dir>/limine.conf. That is where archinstall (4.4) writes it
# - EFI/arch-limine/, or EFI/BOOT/ for the removable path - and where the Arch
# wiki recommends it: next to the EFI binary, the first place Limine looks. On
# such a machine limine="auto" resolved to OFF without a word, a forced
# limine="ON" had limine.sh report "Limine is not the bootloader here", and the
# final check then failed it and blocked the reboot.
#
# The old five paths still come first, in the same order, so a machine that was
# detected before resolves to the same file. Then exactly one directory level
# under each ESP's EFI/, with EFI/BOOT/ (the removable fallback) last: where
# both exist, the firmware's boot entry points at the named one. A glob, not a
# find, and evaluated by root in one sudo call - the ESP is routinely mounted
# root-only (CachyOS: fmask=0077), and an unprivileged test or glob sees nothing.
find_limine_conf() {
  sudo sh -c '
    for c in /boot/limine.conf /efi/limine.conf /boot/efi/limine.conf \
             /boot/limine/limine.conf /efi/limine/limine.conf; do
      [ -f "$c" ] && { echo "$c"; exit 0; }
    done
    for esp in /boot /efi /boot/efi; do
      for c in "$esp"/EFI/*/limine.conf; do
        case "$c" in */[Bb][Oo][Oo][Tt]/limine.conf) continue ;; esac
        [ -f "$c" ] && { echo "$c"; exit 0; }
      done
    done
    for esp in /boot /efi /boot/efi; do
      for c in "$esp"/EFI/[Bb][Oo][Oo][Tt]/limine.conf; do
        [ -f "$c" ] && { echo "$c"; exit 0; }
      done
    done
    exit 1' 2>/dev/null
}

# The mount point of the partition that holds limine.conf ($1). That partition's
# root is what Limine calls boot():/, so it is where theme.conf's
# `wallpaper: boot():/limine-wallpaper.png` has to land - not next to a conf in
# EFI/<dir>/ or limine/, where Limine never looks (and a missing wallpaper is
# skipped silently, so the menu just comes up bare).
#
# findmnt as root: the path is inside a root-only mount, and an unprivileged
# `findmnt -T` cannot stat it and simply fails. If findmnt gives nothing, step
# out of an EFI/<dir>/ or a limine/ directory instead. "EFI" is matched in
# capitals only: find_limine_conf always spells that component that way, and a
# case-blind match took the /efi mount point itself for it.
limine_partition_root() {
  local conf="$1" root d
  root=$(sudo findmnt -no TARGET -T "$conf" 2>/dev/null | head -1)
  if [ -z "$root" ]; then
    d=$(dirname "$conf")
    case "$d" in
      */EFI/*)  d="${d%/EFI/*}" ;;
      */limine) d=$(dirname "$d") ;;
    esac
    root="${d:-/}"
  fi
  echo "$root"
}

# Rebuild every initramfs. Returns non-zero on failure.
#
# CachyOS + Limine keeps its initramfs under /boot/<machine-id>/<kernel>/ and
# regenerates the hashed limine.conf entries through a mkinitcpio post hook
# (limine-mkinitcpio-hook), so a plain `mkinitcpio -P` is fine there too.
# limine-mkinitcpio is simply the distro's front door for the same rebuild, so
# prefer it where it exists.
#
# The generator is picked in the same order plymouth's own plymouth-update-initrd
# uses (limine-mkinitcpio, mkinitcpio, booster, dracut-rebuild), because
# plymouth.sh rebuilds through here now instead of `plymouth-set-default-theme
# -R` - which threw the rebuild's exit status away. Picked first and run once, so
# PIPESTATUS below is always the generator's own status.
rebuild_initramfs() {
  local log="${1:-$LOG}" gen=()
  printf "${INFO} Rebuilding ${YELLOW}Initramfs${RESET}...\n" 2>&1 | tee -a "$log"
  if command -v limine-mkinitcpio &>/dev/null; then
    gen=(limine-mkinitcpio)
  elif command -v mkinitcpio &>/dev/null; then
    gen=(mkinitcpio -P)
  elif [ -x /usr/lib/booster/regenerate_images ]; then
    gen=(/usr/lib/booster/regenerate_images)
  elif command -v dracut-rebuild &>/dev/null; then
    gen=(dracut-rebuild)
  fi
  if [ ${#gen[@]} -eq 0 ]; then
    echo "${ERROR} No initramfs generator found (limine-mkinitcpio, mkinitcpio, booster, dracut-rebuild) - rebuild it by hand." | tee -a "$log"
    echo "$(basename "$0")" >> "$INITRAMFS_FAILED_MANIFEST"
    return 1
  fi
  local out rc
  out=$(mktemp)
  sudo "${gen[@]}" 2>&1 | tee -a "$log" "$out"
  rc=${PIPESTATUS[0]}
  # limine-mkinitcpio exits 0 even when a kernel's image was NOT built or NOT
  # copied to the ESP, so its messages are the only trace:
  #  - limine-mkinitcpio-install prints "ERROR: mkinitcpio failed for kernel X,
  #    skipping." and swallows it (process_regular_kernel || return 0,
  #    process_kernel || true);
  #  - it then copies the image with limine-entry-tool --add-kernel and never
  #    checks the result. That tool catches its own I/O errors and prints them
  #    WITHOUT the ERROR: prefix - "Failed to copy: <src> -> <dst> (No space
  #    left on device)" on a full ESP - and still exits 0.
  # So any of those, at the start of a line once colour codes are stripped,
  # counts as a failure. mkinitcpio's own "==> ERROR:" lines are not matched -
  # mkinitcpio already reports those through its exit status.
  if [ "$rc" -eq 0 ] && [ "${gen[0]}" = limine-mkinitcpio ] \
     && sed 's/\x1b\[[0-9;]*m//g' "$out" \
        | grep -qE '^(ERROR: |Failed to (copy|write|move|create directory):|Command failed:)'; then
    rc=1
  fi
  rm -f "$out"
  if [ "$rc" -ne 0 ]; then
    echo "${ERROR} initramfs rebuild failed - check $log" | tee -a "$log"
    # Recorded, not just printed: callers run this as `|| true` so the rest of
    # their setup still happens, and 02-Final-Check.sh's modinfo and plymouth
    # theme checks pass whether or not the image was rebuilt. Without this
    # marker a failed rebuild (a full ESP, say) auto-rebooted into an image
    # missing the NVIDIA modules, the nouveau blacklist or the new splash.
    echo "$(basename "$0")" >> "$INITRAMFS_FAILED_MANIFEST"
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