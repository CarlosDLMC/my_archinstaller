#!/bin/bash
# vim's h/j/k/l as the arrow keys, on a held Caps Lock (keyd).
#
# Hold Caps Lock and h/j/k/l are Left/Down/Up/Right - everywhere: mango's
# arrow binds (SUPER+Caps+h is SUPER+Left), the bar's cards and dialogs, rofi,
# the browser, the terminal, even the TTY. keyd works on physical keys before
# the keyboard layout is applied, so it is the same in EN, ES and RU. Tapped on
# its own, Caps Lock still toggles Caps Lock, and no existing bind changes
# (SUPER+H stays the cheat sheet).
#
# keyd grabs the keyboards and types through its own "keyd virtual keyboard",
# an input device like any other to mango: it joins the keyboard group, so it
# gets the layouts and follows every layout switch.
#
# An existing /etc/keyd/default.conf that differs is kept as a stamped backup.
# The config is checked with `keyd check` before keyd (re)starts, so a broken
# one cannot take the keyboard away. If keyd ever misbehaves:
# Backspace+Escape+Enter together stops it. Re-running changes nothing.
## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "[ERROR] Failed to change directory to $PARENT_DIR"; exit 1; }
if ! source "$SCRIPT_DIR/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_keyd.log"

CONF=/etc/keyd/default.conf

printf "\n%s - Putting ${SKY_BLUE}h/j/k/l arrows${RESET} on a held Caps Lock (keyd) \n" "${NOTE}"

install_package keyd "$LOG"
if ! pacman -Qi keyd &>/dev/null; then
  echo "${ERROR} keyd is not installed - skipping its config." | tee -a "$LOG"
  exit 1
fi

new=$(mktemp) || exit 1
trap 'rm -f "$new"' EXIT
cat >"$new" <<'EOF'
# keyd: a navigation layer on Caps Lock (my_archinstaller, install-scripts/keyd.sh).
#
# Hold Caps Lock and h/j/k/l are the arrow keys - everywhere, in every layout
# (keyd works on physical keys, so it is the same in EN, ES and RU), and with
# any modifier: SUPER+Caps+h is SUPER+Left. Tapped alone, Caps Lock still
# toggles Caps Lock.
#
# Locked out by a bad config? Backspace+Escape+Enter together stops keyd.

[ids]
*

[main]
capslock = overload(nav, capslock)

[nav]
h = left
j = down
k = up
l = right
EOF

if ! keyd check "$new" >>"$LOG" 2>&1; then
  echo "${ERROR} keyd rejected the config - leaving keyd as it was." | tee -a "$LOG"
  exit 1
fi

if [ -f "$CONF" ] && cmp -s "$new" "$CONF"; then
  echo "${INFO} $CONF is already in place." | tee -a "$LOG"
else
  if [ -f "$CONF" ]; then
    _bak="$CONF.bak-$(date +%Y%m%d-%H%M%S)"
    sudo cp -p "$CONF" "$_bak" && echo "${NOTE} Kept your previous keyd config as $_bak" | tee -a "$LOG"
  fi
  sudo install -D -m 644 "$new" "$CONF" || { echo "${ERROR} Could not write $CONF" | tee -a "$LOG"; exit 1; }
  echo "${OK} Wrote $CONF" | tee -a "$LOG"
fi

# Disable-while-typing. libinput turns the touchpad off while you type only for
# a keyboard it takes to be built in, and keyd's virtual keyboard - which all
# typing comes through now - reports itself as USB. Without this, on a laptop a
# palm on the touchpad moved the pointer (and with tap-to-click, clicked)
# mid-sentence. The quirk is the one keyd's README gives (its FAQ), added to
# libinput's one local overrides file after whatever is already there. libinput
# reads it when a device appears: from the next login. Harmless without a
# touchpad.
QUIRKS=/etc/libinput/local-overrides.quirks
if [ -f "$QUIRKS" ] && grep -qx 'MatchName=keyd\*keyboard' "$QUIRKS"; then
  echo "${INFO} The keyd keyboard is already marked built-in in $QUIRKS." | tee -a "$LOG"
else
  _sep=""
  if [ -s "$QUIRKS" ]; then _sep=$'\n'; fi
  if sudo mkdir -p /etc/libinput \
     && printf '%s# keyd'"'"'s virtual keyboard is the built-in one (my_archinstaller, install-scripts/keyd.sh)\n[keyd virtual keyboard]\nMatchUdevType=keyboard\nMatchName=keyd*keyboard\nAttrKeyboardIntegration=internal\n' "$_sep" \
        | sudo tee -a "$QUIRKS" >/dev/null; then
    echo "${OK} Marked the keyd keyboard built-in for libinput: the touchpad stays off while you type." | tee -a "$LOG"
  else
    echo "${WARN} Could not write $QUIRKS - the touchpad will not pause while you type (see keyd's README, FAQ)." | tee -a "$LOG"
  fi
fi

# Enabled for every boot, and (re)started now so the new config is live -
# restart, not reload, because a reload is ignored while keyd is not running.
if sudo systemctl enable keyd.service >>"$LOG" 2>&1 \
   && sudo systemctl restart keyd.service >>"$LOG" 2>&1 \
   && systemctl is-active --quiet keyd.service; then
  echo "${OK} keyd is running: hold Caps Lock for h/j/k/l arrows." | tee -a "$LOG"
else
  echo "${WARN} keyd is configured but did not start - it should at the next boot (see $LOG)." | tee -a "$LOG"
fi
