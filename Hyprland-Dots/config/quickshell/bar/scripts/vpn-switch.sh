#!/bin/sh
# vpn-switch.sh <from> <to>: the bar's server switch, without a gap in the
# killswitch.
#
# `wg-quick down <from>` takes the old tunnel's killswitch rule out (PostDown),
# and until <to>'s PostUp put its own in, nothing was blocked: whatever sent in
# that moment - a torrent client, messengers reconnecting - went out in the
# clear from the LAN address. A guard that names no interface holds the gap:
# everything not marked as WireGuard's own (FwMark 51820) and not local is
# rejected, DNS excepted so a hostname endpoint still resolves. It comes out
# again when the switch is over, whether <to> came up or not.
tag=wireguard-killswitch-switch

guard() { # -I or -D. Inserted in this order, the DNS exceptions end up above the REJECT.
    sudo iptables "$1" OUTPUT -m mark ! --mark 51820 -m addrtype ! --dst-type LOCAL -m comment --comment "$tag" -j REJECT
    for spec in "udp 53" "tcp 53" "tcp 853"; do
        set -- "$1" $spec
        sudo iptables "$1" OUTPUT -p "$2" --dport "$3" -m comment --comment "$tag" -j ACCEPT
    done
}

from=$1 to=$2
guard -I 2>/dev/null
sudo wg-quick down "$from"
sudo wg-quick up "$to"
rc=$?
guard -D 2>/dev/null
if [ "$rc" -ne 0 ]; then
    notify-send -u critical "VPN" "Could not connect $to - no tunnel is up now. Pick a server again, or run vpn-recover." 2>/dev/null
fi
exit "$rc"
