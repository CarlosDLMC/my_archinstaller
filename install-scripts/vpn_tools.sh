#!/bin/bash
# WireGuard killswitch helpers: two root-owned commands in /usr/local/bin
#
#   add-wireguard-killswitch-to-configs
#       Rewrites every /etc/wireguard/*.conf to carry `FwMark = 51820` and a
#       PostUp/PostDown iptables pair that REJECTs all output not going through
#       the tunnel. Safe to re-run: it strips its own lines before adding them.
#       Run it as root once the configs have been copied over (see README, VPN
#       configs).
#
#   vpn-recover [name]
#       The way back when a tunnel died with the killswitch still in place and
#       nothing can reach the network: removes the stale REJECT rule, brings the
#       tunnel back up, and puts the rule back if that fails. Lists the configs
#       to pick from when called without a name; re-runs itself through sudo.
#
# The scripts themselves live in assets/vpn/. wg-quick comes from
# wireguard-tools (01-hypr-pkgs.sh). iptables is installed below, but only when
# nothing provides it yet: `iptables` (the nft backend) and `iptables-legacy`
# conflict, and --noconfirm cannot answer the "replace it?" prompt, so asking
# for `iptables` on a legacy machine would fail the transaction.

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "Failed to change directory to $PARENT_DIR"; exit 1; }

if ! source "$SCRIPT_DIR/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_vpn_tools.log"

printf "\n${NOTE} Installing the ${SKY_BLUE}WireGuard killswitch helpers${RESET}...\n" | tee -a "$LOG"

failed=0

# `pacman -T` is satisfied by either iptables or iptables-legacy (it "provides"
# iptables); `pacman -Q iptables` would miss the legacy one.
if pacman -T iptables >/dev/null 2>&1; then
  printf "${INFO} iptables is already provided ($(pacman -Qqs '^iptables' | paste -sd' ')). Skipping...\n" | tee -a "$LOG"
else
  install_package iptables
fi
if ! command -v iptables >/dev/null 2>&1; then
  printf "${ERROR} iptables is still missing - the killswitch will not work until it is installed.\n" | tee -a "$LOG"
  failed=1
fi

for tool in add-wireguard-killswitch-to-configs vpn-recover; do
  src="assets/vpn/$tool"
  if [ ! -f "$src" ]; then
    printf "${ERROR} Missing $src\n" | tee -a "$LOG"
    failed=1
    continue
  fi
  # root:root 0755: they run as root and edit /etc/wireguard and the firewall,
  # so they must not be writable by the user (sudo is passwordless here).
  sudo install -o root -g root -m 0755 "$src" "/usr/local/bin/$tool" 2>&1 | tee -a "$LOG"
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    printf "${ERROR} Failed to install /usr/local/bin/$tool\n" | tee -a "$LOG"
    failed=1
    continue
  fi
  printf "${OK} Installed ${SKY_BLUE}/usr/local/bin/$tool${RESET}\n" | tee -a "$LOG"
done

printf "${NOTE} After copying your configs to /etc/wireguard, run ${MAGENTA}sudo add-wireguard-killswitch-to-configs${RESET} once.\n" | tee -a "$LOG"
printf "${NOTE} If a tunnel drops and the network is blocked, run ${MAGENTA}vpn-recover${RESET}.\n" | tee -a "$LOG"

printf "\n%.0s" {1..2}
exit $failed
