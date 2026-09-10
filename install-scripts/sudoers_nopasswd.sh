#!/bin/bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  #
# Passwordless sudo for the wheel group

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || exit 1

source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"

LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_sudoers.log"

# Why this exists
#
# This machine runs with `%wheel ALL=(ALL:ALL) NOPASSWD: ALL`, which Arch ships
# commented out. It is a deliberate choice, and several things in the dots
# depend on it - the bar's VPN widget shells out to `sudo find /etc/wireguard`,
# `sudo wg-quick up/down` and `sudo timedatectl set-timezone` from a QML
# Process, which has no terminal to prompt on. With stock sudoers those calls
# fail silently and the VPN dropdown just does nothing.
#
# Be aware of what it means: any process running as your user can become root
# without a prompt. That is the trade being made for not typing a password.
#
# This installs a drop-in under /etc/sudoers.d rather than editing
# /etc/sudoers, because it is idempotent on re-runs and because a bad edit to
# /etc/sudoers locks you out of sudo entirely. The file is validated with
# `visudo -c` BEFORE it is put in place, so a malformed rule can never land.

RULE_FILE="/etc/sudoers.d/10-wheel-nopasswd"

printf "\n${NOTE} Configuring ${SKY_BLUE}passwordless sudo${RESET} for the wheel group...\n"

# Make sure the user is actually in wheel, or the rule below does nothing.
if ! groups "$USER" | grep -qw wheel; then
  printf "${NOTE} Adding $USER to the wheel group...\n"
  if sudo usermod -aG wheel "$USER" 2>&1 | tee -a "$LOG"; then
    echo "${OK} $USER added to wheel (takes effect on next login)" | tee -a "$LOG"
  else
    echo "${ERROR} Could not add $USER to wheel - the rule below will not apply" | tee -a "$LOG"
  fi
fi

# Build in a temp file, validate, then install. visudo -c on the candidate file
# catches syntax errors while they are still harmless.
TMP_RULE="$(mktemp)"
trap 'rm -f "$TMP_RULE"' EXIT

cat > "$TMP_RULE" <<'RULE'
# Installed by my_archinstaller (install-scripts/sudoers_nopasswd.sh).
#
# Passwordless sudo for the wheel group. Required by the quickshell bar's VPN
# widget, which runs `sudo find /etc/wireguard`, `sudo wg-quick up|down` and
# `sudo timedatectl set-timezone` from a QML Process with no tty to prompt on.
#
# Removing this line means typing a password for every sudo, and the VPN
# dropdown in the bar silently stops working.
%wheel ALL=(ALL:ALL) NOPASSWD: ALL
RULE

if sudo visudo -c -f "$TMP_RULE" >/dev/null 2>&1; then
  echo "${OK} Rule syntax validated" | tee -a "$LOG"
else
  echo "${ERROR} Generated sudoers rule failed validation - NOT installing it" | tee -a "$LOG"
  sudo visudo -c -f "$TMP_RULE" 2>&1 | tee -a "$LOG"
  exit 1
fi

# 0440 root:root, which is what sudo requires of files in sudoers.d.
if sudo install -o root -g root -m 0440 "$TMP_RULE" "$RULE_FILE" 2>&1 | tee -a "$LOG"; then
  echo "${OK} Installed $RULE_FILE" | tee -a "$LOG"
else
  echo "${ERROR} Failed to install $RULE_FILE" | tee -a "$LOG"
  exit 1
fi

# Re-validate the whole sudoers tree now that the drop-in is in place. If this
# fails the file is actively dangerous, so pull it back out immediately.
if sudo visudo -c >/dev/null 2>&1; then
  echo "${OK} Full sudoers configuration is valid" | tee -a "$LOG"
else
  echo "${ERROR} sudoers is invalid after install - removing the rule" | tee -a "$LOG"
  sudo rm -f "$RULE_FILE"
  exit 1
fi

printf "\n%.0s" {1..2}
