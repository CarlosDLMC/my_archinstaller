#!/bin/sh
# vpn-switch.sh <from> <to>: the bar's server switch, without a gap in the
# killswitch.
#
# Taking <from> down takes its killswitch rule out (wg-quick's PostDown, or the
# stop of the tunnel's service - vpn-ctl.sh knows which), and until <to> has
# put its own in, nothing was blocked: whatever sent in
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
ctl="$(dirname "$(readlink -f "$0")")/vpn-ctl.sh"
"$ctl" down "$from"
"$ctl" up "$to"
rc=$?
guard -D 2>/dev/null
if [ "$rc" -ne 0 ]; then
    notify-send -u critical "ВПН" "Не удалось подключиться к $to: ни один туннель не поднят. Выберите сервер ещё раз или запустите vpn-recover." 2>/dev/null
fi
exit "$rc"
