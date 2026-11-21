#!/bin/sh
# vpn-ctl.sh list | active | up <name> | down <name>
#
# The tunnels of the bar's VPN card, whatever they are made of. A name is one
# of three kinds, told apart by where its config is:
#
#   /etc/wireguard/<name>.conf           WireGuard        wg-quick up|down
#   /etc/amnezia/amneziawg/<name>.conf   AmneziaWG        awg-quick@<name>.service
#   /etc/sing-box/<name>.json            sing-box tunnel  sing-box@<name>.service
#
# A sing-box config counts only when it makes a tunnel interface named like
# the file (a TUN inbound with "interface_name": "<name>"); one that is only a
# local proxy is not a tunnel. The two services are used instead of the bare
# commands because stopping them takes the killswitch out in every state,
# also after a crash.
#
# `active` needs no root: the first interface that is WireGuard or a TUN
# device, which is what all three kinds come up as.

WG=/etc/wireguard
AWG=/etc/amnezia/amneziawg
SB=/etc/sing-box

is_singbox_tunnel() {
    sudo grep -qs "\"interface_name\"[[:space:]]*:[[:space:]]*\"$1\"" "$SB/$1.json"
}

kind() {
    if sudo test -f "$WG/$1.conf"; then echo wg
    elif sudo test -f "$AWG/$1.conf"; then echo awg
    elif is_singbox_tunnel "$1"; then echo sing-box
    else return 1
    fi
}

case "$1" in
list)
    {
        sudo find "$WG" "$AWG" -maxdepth 1 -name '*.conf' -exec basename {} .conf \; 2>/dev/null
        for f in "$SB"/*.json; do
            [ -e "$f" ] || continue
            name=$(basename "$f" .json)
            is_singbox_tunnel "$name" && echo "$name"
        done
    } | sort -u
    ;;
active)
    for d in /sys/class/net/*; do
        name=${d##*/}
        if grep -qs '^DEVTYPE=wireguard$' "$d/uevent"; then
            echo "$name"; exit 0
        fi
        # tun_flags: bit 0 is a TUN device; a TAP one (a virtual machine's
        # network card) has bit 1 instead.
        flags=$(cat "$d/tun_flags" 2>/dev/null) || continue
        if [ $((flags & 1)) -eq 1 ]; then
            echo "$name"; exit 0
        fi
    done
    ;;
up)
    name=$2
    case "$(kind "$name")" in
    wg) exec sudo wg-quick up "$name" ;;
    awg)
        sudo systemctl reset-failed "awg-quick@$name" 2>/dev/null
        exec sudo systemctl start "awg-quick@$name"
        ;;
    sing-box)
        sudo systemctl reset-failed "sing-box@$name" 2>/dev/null
        sudo systemctl start "sing-box@$name" || exit 1
        # The service counts as started the moment the program runs; the
        # tunnel is up when its interface is there.
        n=0
        until [ -e "/sys/class/net/$name" ]; do
            n=$((n + 1))
            if [ "$n" -gt 50 ]; then
                sudo systemctl stop "sing-box@$name"
                exit 1
            fi
            sleep 0.2
        done
        ;;
    *) echo "vpn-ctl: no tunnel named $name" >&2; exit 1 ;;
    esac
    ;;
down)
    name=$2
    case "$(kind "$name")" in
    wg) exec sudo wg-quick down "$name" ;;
    awg)
        sudo systemctl stop "awg-quick@$name"
        # Brought up with a bare `awg-quick up`, the service knows nothing of it.
        if [ -e "/sys/class/net/$name" ]; then
            exec sudo awg-quick down "$name"
        fi
        ;;
    sing-box) exec sudo systemctl stop "sing-box@$name" ;;
    *) echo "vpn-ctl: no tunnel named $name" >&2; exit 1 ;;
    esac
    ;;
*)
    echo "Usage: vpn-ctl.sh list | active | up <name> | down <name>" >&2
    exit 1
    ;;
esac
