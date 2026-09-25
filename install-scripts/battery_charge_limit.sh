#!/bin/bash
# Battery charge limit: the root helper and the unit that reapplies it

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "Failed to change directory to $PARENT_DIR"; exit 1; }

if ! source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_battery_charge_limit.log"

# What this is for
#
# A lithium cell wears out two ways. Cycling it is the one everybody counts,
# and it is the one a laptop that lives on mains barely does - the charger
# bypasses a full pack and runs the machine off the adapter, so the cycle
# counter hardly moves. The other is calendar ageing: held at 100%, a cell sits
# at ~4.2V per cell and its electrolyte oxidises at that potential whether or
# not any current is flowing, faster the warmer it is. Inside a laptop that is
# plugged in permanently, that is the dominant wear by a wide margin.
#
# The T480 this was written on shows it plainly: the internal pack has 239
# cycles and 44% of its design capacity left, while the removable one has 566
# cycles and 82%. Cycling is not what killed the first one.
#
# The fix is a charge threshold: stop charging at 60-80% and the cell spends
# its life at a voltage where that reaction is far slower. Most ThinkPads and
# many ASUS laptops expose it through the kernel as
# /sys/class/power_supply/BAT*/charge_control_end_threshold.
#
# Three things have to exist for the bar's battery card to offer it:
#
#   1. a root-owned helper, because those sysfs files are root-writable only
#      and a QML Process has no tty to prompt on;
#   2. somewhere to record the choice, because a sysfs write does not survive
#      a reboot;
#   3. a unit that reapplies it at boot and after resume, because some
#      firmware resets the threshold on wake.
#
# This installs all three. Machines with no thresholds (desktops, and laptops
# whose vendor never wired them up) get nothing and the card hides the control.

HELPER="/usr/local/bin/battery-charge-limit"
CONF="/etc/battery-charge-limit.conf"
UNIT="/etc/systemd/system/battery-charge-limit.service"

printf "\n${NOTE} Setting up the ${SKY_BLUE}battery charge limit${RESET}...\n" | tee -a "$LOG"

# ---------------------------------------------------------------------------
# Does this machine have thresholds at all?
# ---------------------------------------------------------------------------
has_threshold=false
for bat in /sys/class/power_supply/BAT*; do
  [ -e "$bat/charge_control_end_threshold" ] && has_threshold=true && break
done

if [ "$has_threshold" != "true" ]; then
  if ls -d /sys/class/power_supply/BAT* >/dev/null 2>&1; then
    printf "${NOTE} This machine has a battery but no charge_control_end_threshold.\n" | tee -a "$LOG"
    printf "${NOTE} The vendor did not expose one - the bar will hide the limit control.\n" | tee -a "$LOG"
  else
    printf "${OK} No battery on this machine. Nothing to limit.\n" | tee -a "$LOG"
  fi
  printf "\n%.0s" {1..2}
  exit 0
fi

# ---------------------------------------------------------------------------
# The helper
# ---------------------------------------------------------------------------
TMP_HELPER="$(mktemp)"
TMP_UNIT="$(mktemp)"
trap 'rm -f "$TMP_HELPER" "$TMP_UNIT"' EXIT

cat > "$TMP_HELPER" <<'HELPEREOF'
#!/bin/bash
# Installed by my_archinstaller (install-scripts/battery_charge_limit.sh).
#
# Sets the charge threshold on every system battery and remembers it.
#
#   battery-charge-limit get        print the limit each pack is set to
#   battery-charge-limit set <N>    set every pack to N% and persist it
#   battery-charge-limit apply      re-apply the persisted value
#
# `set` is what the quickshell bar's battery card calls, through sudo.
# `apply` is what battery-charge-limit.service calls at boot and after resume.

set -u

CONF="/etc/battery-charge-limit.conf"

batteries() {
  for bat in /sys/class/power_supply/BAT*; do
    [ -e "$bat/charge_control_end_threshold" ] || continue
    # A Bluetooth mouse is also type=Battery under power_supply; scope tells
    # the machine's own packs from a peripheral's.
    [ "$(cat "$bat/scope" 2>/dev/null || echo System)" = "System" ] || continue
    echo "$bat"
  done
}

write_one() {
  local bat="$1" limit="$2" start=""

  # Order matters. thinkpad_acpi rejects a start threshold that is not below
  # the end one, so raising the limit has to clear start first and lowering it
  # has to set end first. Clearing start to 0 - which the driver reads as
  # "default" - is valid from any state, so it always goes first.
  if [ -w "$bat/charge_control_start_threshold" ]; then
    echo 0 > "$bat/charge_control_start_threshold" 2>/dev/null || true
  fi

  echo "$limit" > "$bat/charge_control_end_threshold" || return 1

  # A start threshold a few points below the end one stops the pack
  # re-topping every time it self-discharges a fraction of a percent. Some
  # drivers (ASUS) expose only the end threshold; that is fine, skip it.
  if [ "$limit" -lt 100 ] && [ -w "$bat/charge_control_start_threshold" ]; then
    start=$(( limit - 5 ))
    [ "$start" -lt 0 ] && start=0
    echo "$start" > "$bat/charge_control_start_threshold" 2>/dev/null || true
  fi
}

cmd_get() {
  local found=false
  for bat in $(batteries); do
    found=true
    printf '%s\t%s\t%s\n' \
      "$(basename "$bat")" \
      "$(cat "$bat/charge_control_end_threshold" 2>/dev/null || echo '?')" \
      "$(cat "$bat/charge_control_start_threshold" 2>/dev/null || echo '-')"
  done
  [ "$found" = "true" ] || return 1
}

cmd_set() {
  local limit="$1"

  case "$limit" in
    ''|*[!0-9]*) echo "battery-charge-limit: not a number: $limit" >&2; exit 2 ;;
  esac
  if [ "$limit" -lt 40 ] || [ "$limit" -gt 100 ]; then
    # Below 40 is not a useful limit, it is a machine that cannot survive an
    # unplug. The ceiling is the hardware's.
    echo "battery-charge-limit: limit must be between 40 and 100" >&2
    exit 2
  fi

  local any=false
  for bat in $(batteries); do
    if write_one "$bat" "$limit"; then
      any=true
    else
      echo "battery-charge-limit: $(basename "$bat") refused $limit%" >&2
    fi
  done

  if [ "$any" != "true" ]; then
    echo "battery-charge-limit: no battery accepted a threshold" >&2
    exit 1
  fi

  # Persist only what at least one pack took. Recording a value the hardware
  # rejected would have the unit re-apply the same failure at every boot.
  printf '# Written by battery-charge-limit. The quickshell bar edits this.\nLIMIT=%s\n' \
    "$limit" > "$CONF"
}

cmd_apply() {
  [ -r "$CONF" ] || exit 0

  local limit
  limit=$(sed -n 's/^LIMIT=\([0-9]\+\)$/\1/p' "$CONF" | tail -1)
  [ -n "$limit" ] || exit 0

  # At boot this can run before the battery driver has registered its packs.
  # Wait a few seconds rather than leaving the machine on whatever threshold
  # the firmware came up with.
  local tries=0
  while [ -z "$(batteries)" ] && [ "$tries" -lt 10 ]; do
    sleep 1
    tries=$(( tries + 1 ))
  done

  for bat in $(batteries); do
    write_one "$bat" "$limit" || true
  done
}

case "${1:-}" in
  get)   cmd_get ;;
  set)   [ $# -eq 2 ] || { echo "usage: battery-charge-limit set <40-100>" >&2; exit 2; }
         cmd_set "$2" ;;
  apply) cmd_apply ;;
  *)     echo "usage: battery-charge-limit {get|set <40-100>|apply}" >&2; exit 2 ;;
esac
HELPEREOF

if ! bash -n "$TMP_HELPER"; then
  printf "${ERROR} The generated helper does not parse - NOT installing it.\n" | tee -a "$LOG"
  exit 1
fi

# root:root 0755. It must not be writable by the user: the bar calls it through
# passwordless sudo, so a user-writable helper at a sudo-reachable path would be
# a way to run anything as root.
sudo install -o root -g root -m 0755 "$TMP_HELPER" "$HELPER" 2>&1 | tee -a "$LOG"
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
  printf "${ERROR} Failed to install $HELPER\n" | tee -a "$LOG"
  exit 1
fi
printf "${OK} Installed ${SKY_BLUE}$HELPER${RESET}\n" | tee -a "$LOG"

# ---------------------------------------------------------------------------
# The sudoers rule
# ---------------------------------------------------------------------------
# The bar runs `sudo -n /usr/local/bin/battery-charge-limit set N` from a QML
# Process, which has no terminal to prompt on. With nopasswd_sudo="ON" the wheel
# rule covers it; with it OFF the picker failed silently. So, like the bluetooth
# toggle's rule, this installs a rule for exactly this one root-owned helper.
# Safe to grant because the helper is root:root 0755 (see above) and only takes
# get / set <40-100> / apply. Built in a temp file and validated with visudo
# first: a malformed file in sudoers.d makes EVERY sudo refuse to run.
BAT_USER="${USER:-$(id -un)}"
if [ -n "$BAT_USER" ]; then
  BAT_RULE="$(mktemp)"
  echo "$BAT_USER ALL=(root) NOPASSWD: $HELPER" > "$BAT_RULE"
  if sudo visudo -c -f "$BAT_RULE" >/dev/null 2>&1; then
    sudo install -m 0440 -o root -g root "$BAT_RULE" /etc/sudoers.d/battery-charge-limit 2>&1 | tee -a "$LOG"
    if [ "${PIPESTATUS[0]}" -eq 0 ]; then
      printf "${OK} sudoers rule for the bar's charge limit picker installed\n" | tee -a "$LOG"
    else
      printf "${ERROR} Could not install /etc/sudoers.d/battery-charge-limit - the bar's picker needs nopasswd_sudo\n" | tee -a "$LOG"
    fi
  else
    printf "${ERROR} Generated sudoers rule failed validation - NOT installing it\n" | tee -a "$LOG"
  fi
  rm -f "$BAT_RULE"
fi

# ---------------------------------------------------------------------------
# The unit
# ---------------------------------------------------------------------------
cat > "$TMP_UNIT" <<'UNITEOF'
# Installed by my_archinstaller (install-scripts/battery_charge_limit.sh).
#
# Re-applies the charge threshold recorded in /etc/battery-charge-limit.conf.
# A sysfs write does not survive a reboot, and some firmware clears the
# threshold on resume, so this runs at both.
[Unit]
Description=Apply the battery charge limit
After=multi-user.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
ConditionPathExists=/etc/battery-charge-limit.conf

[Service]
Type=oneshot
ExecStart=/usr/local/bin/battery-charge-limit apply

[Install]
WantedBy=multi-user.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
UNITEOF

sudo install -o root -g root -m 0644 "$TMP_UNIT" "$UNIT" 2>&1 | tee -a "$LOG"
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
  printf "${ERROR} Failed to install $UNIT\n" | tee -a "$LOG"
  exit 1
fi

sudo systemctl daemon-reload 2>&1 | tee -a "$LOG"

# `After=` plus `WantedBy=` on the sleep targets is the documented idiom for
# "run on resume": the target is stopped on wake and its wanted units run then.
sudo systemctl enable battery-charge-limit.service 2>&1 | tee -a "$LOG"
if [ "${PIPESTATUS[0]}" -eq 0 ]; then
  printf "${OK} Installed and enabled ${SKY_BLUE}battery-charge-limit.service${RESET}\n" | tee -a "$LOG"
else
  printf "${WARN} Could not enable battery-charge-limit.service - the limit will\n" | tee -a "$LOG"
  printf "${WARN} still apply, but it will be lost on reboot.\n" | tee -a "$LOG"
fi

# ---------------------------------------------------------------------------
# The default
# ---------------------------------------------------------------------------
# No limit is set for you. A machine that travels wants the full pack, and
# guessing wrong here means a laptop that dies in a meeting because an
# installer decided 60% on its behalf. The conf file is seeded with whatever
# the hardware is already doing, so the unit is a no-op until you pick
# something in the bar's battery card.
if [ ! -f "$CONF" ]; then
  current=$(cat /sys/class/power_supply/BAT*/charge_control_end_threshold 2>/dev/null | head -1)
  [ -n "$current" ] || current=100
  printf '# Written by battery-charge-limit. The quickshell bar edits this.\nLIMIT=%s\n' \
    "$current" | sudo tee "$CONF" >/dev/null
  printf "${OK} Recorded the current limit (${SKY_BLUE}${current}%%${RESET}). Change it from the bar's battery card.\n" | tee -a "$LOG"
else
  printf "${OK} $CONF already exists - leaving your limit alone.\n" | tee -a "$LOG"
fi

printf "${NOTE} Click the battery in the bar to pick 60%%, 80%% or Full.\n" | tee -a "$LOG"
printf "${NOTE} 60%% is the one to want on a machine that lives on mains.\n" | tee -a "$LOG"

printf "\n%.0s" {1..2}
