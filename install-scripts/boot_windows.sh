#!/bin/bash
# Reboot into Windows without a password: the root helper behind the power menu's W

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "Failed to change directory to $PARENT_DIR"; exit 1; }

if ! source "$SCRIPT_DIR/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_boot_windows.log"

# What this is for
#
# The bar's power menu (PowerOsd, key W) reboots into Windows once: it sets the
# firmware's one-shot BootNext to the Windows Boot Manager entry and reboots.
# Rebooting needs no privileges (logind allows the active session), but BootNext
# is a UEFI variable and only root may write those. Through pkexec that meant a
# password prompt on every W.
#
# So, like battery_charge_limit.sh: a root-owned helper that does exactly one
# thing and takes no input, and a sudoers rule for that helper alone. Granting
# efibootmgr itself without a password would let any process running as the
# user rewrite or delete boot entries; this helper can only point BootNext at
# Windows Boot Manager, which is harmless.
#
# BIOS machines (no /sys/firmware/efi) get nothing. A UEFI machine without
# Windows gets the helper anyway - Windows may be installed later - and the
# menu hides W until an entry exists.

HELPER="/usr/local/bin/boot-windows-next"
RULE_FILE="/etc/sudoers.d/boot-windows-next"

printf "\n${NOTE} Setting up ${SKY_BLUE}reboot into Windows${RESET} for the power menu...\n" | tee -a "$LOG"

if [ ! -d /sys/firmware/efi ]; then
  printf "${OK} Not a UEFI boot - there is no BootNext to set. Nothing to do.\n" | tee -a "$LOG"
  printf "\n%.0s" {1..2}
  exit 0
fi

install_package efibootmgr "$LOG"

TMP_HELPER="$(mktemp)"
TMP_RULE="$(mktemp)"
trap 'rm -f "$TMP_HELPER" "$TMP_RULE"' EXIT

cat > "$TMP_HELPER" <<'HELPEREOF'
#!/bin/bash
# Installed by my_archinstaller (install-scripts/boot_windows.sh).
#
# Points the firmware's one-shot BootNext at the Windows Boot Manager entry, so
# the next reboot - and only the next one - starts Windows. Takes no arguments
# and does nothing else; the quickshell power menu runs it through sudo and then
# reboots with `systemctl reboot`.
#
# Exit 2 when there is no Windows Boot Manager entry.
set -u
[ "$#" -eq 0 ] || { echo "usage: boot-windows-next" >&2; exit 64; }
entry=$(efibootmgr 2>/dev/null \
  | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\}[[:space:]]\{1,\}Windows Boot Manager.*/\1/p' \
  | head -n 1)
[ -n "$entry" ] || { echo "boot-windows-next: no Windows Boot Manager entry" >&2; exit 2; }
exec efibootmgr --bootnext "$entry" >/dev/null
HELPEREOF

sudo install -o root -g root -m 0755 "$TMP_HELPER" "$HELPER" 2>&1 | tee -a "$LOG"
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
  printf "${ERROR} Could not install $HELPER - W in the power menu will ask for a password\n" | tee -a "$LOG"
  exit 1
fi
printf "${OK} Installed $HELPER\n" | tee -a "$LOG"

# The rule: this helper, with no arguments (the trailing ""), nothing else.
# Validated with visudo first - a malformed file in sudoers.d makes EVERY sudo
# refuse to run.
RULE_USER="${USER:-$(id -un)}"
echo "$RULE_USER ALL=(root) NOPASSWD: $HELPER \"\"" > "$TMP_RULE"
if sudo visudo -c -f "$TMP_RULE" >/dev/null 2>&1; then
  sudo install -m 0440 -o root -g root "$TMP_RULE" "$RULE_FILE" 2>&1 | tee -a "$LOG"
  if [ "${PIPESTATUS[0]}" -eq 0 ]; then
    printf "${OK} sudoers rule for $HELPER installed\n" | tee -a "$LOG"
  else
    printf "${ERROR} Could not install $RULE_FILE - W in the power menu will ask for a password\n" | tee -a "$LOG"
  fi
else
  printf "${ERROR} Generated sudoers rule failed validation - NOT installing it\n" | tee -a "$LOG"
fi

printf "\n%.0s" {1..2}
