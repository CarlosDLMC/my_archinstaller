#!/usr/bin/env bash
# Active network status for the bar's network card.
#
# Ported from Omarchy's omarchy-network-status (omacom/omarchy, MIT, DHH):
# the route-based interface detection, the /sys byte counters and the iw link
# parsing are his. Added here: the DNS servers in force, and packet loss
# alongside the latency sample.
#
# Prints tab-separated key/value lines; NetworkPanel.qml parses them. One line
# per fact, missing facts simply absent - so a key that cannot be determined
# leaves its row showing a dash rather than a wrong number.
#
# Only ever run while the card is open. The pings alone take up to a second.

set -uo pipefail

INTERNET_PROBE=1.1.1.1

route_json=$(ip -j route get "$INTERNET_PROBE" 2>/dev/null)
[[ -z $route_json ]] && { printf 'state\tdisconnected\n'; exit 0; }

iface=$(jq -r '.[0].dev // ""' <<<"$route_json" 2>/dev/null)
gw=$(jq -r '.[0].gateway // ""' <<<"$route_json" 2>/dev/null)
src=$(jq -r '.[0].prefsrc // ""' <<<"$route_json" 2>/dev/null)

[[ -z $iface ]] && { printf 'state\tdisconnected\n'; exit 0; }

prefix=$(ip -j addr show "$iface" 2>/dev/null \
  | jq -r '.[0].addr_info[]? | select(.family == "inet") | .prefixlen // ""' 2>/dev/null | head -n 1)

printf 'state\tconnected\n'
printf 'iface\t%s\n' "$iface"
printf 'ip\t%s\n' "$src"
printf 'prefix\t%s\n' "$prefix"
printf 'gateway\t%s\n' "$gw"

# DNS actually in force for this link. resolvectl knows about per-link servers
# (this machine runs systemd-resolved); nmcli is the fallback when it does not.
dns=""
if command -v resolvectl >/dev/null 2>&1; then
  dns=$(resolvectl dns "$iface" 2>/dev/null | sed 's/^.*): //' | tr -s ' ' | sed 's/^ *//;s/ *$//')
fi
if [[ -z $dns ]] && command -v nmcli >/dev/null 2>&1; then
  dns=$(nmcli -g IP4.DNS device show "$iface" 2>/dev/null | paste -sd' ' -)
fi
[[ -n $dns ]] && printf 'dns\t%s\n' "$dns"

# Byte counters. Rates are worked out in QML from two consecutive samples -
# the kernel only exposes the totals.
[[ -r /sys/class/net/$iface/statistics/rx_bytes ]] \
  && printf 'rx_bytes\t%s\n' "$(cat "/sys/class/net/$iface/statistics/rx_bytes")"
[[ -r /sys/class/net/$iface/statistics/tx_bytes ]] \
  && printf 'tx_bytes\t%s\n' "$(cat "/sys/class/net/$iface/statistics/tx_bytes")"

if [[ -d /sys/class/net/$iface/wireless ]]; then
  printf 'type\twifi\n'
elif [[ -d /sys/class/net/$iface/tun_flags || $iface == wg* || -n $(ip -d link show "$iface" 2>/dev/null | grep -o 'wireguard') ]]; then
  printf 'type\tvpn\n'
else
  printf 'type\tethernet\n'
  # Only physical links answer these; a tunnel returns EINVAL, which used to
  # print a cat error and an empty value rather than simply omitting the row.
  speed=$(cat "/sys/class/net/$iface/speed" 2>/dev/null) && [[ -n $speed ]] \
    && printf 'speed\t%s\n' "$speed"
  duplex=$(cat "/sys/class/net/$iface/duplex" 2>/dev/null) && [[ -n $duplex ]] \
    && printf 'duplex\t%s\n' "$duplex"
fi

# The wireless link is reported on its own, NOT off the default route. This
# machine routinely has WireGuard up, and then the route interface is the
# tunnel - so keying the radio details off it (as the original did) silently
# dropped SSID, signal and bitrate for exactly as long as the VPN was
# connected. The radio is still the radio whatever is routed over it.
wifi_iface=""
for d in /sys/class/net/*/wireless; do
  [[ -e $d ]] || continue
  wifi_iface=$(basename "$(dirname "$d")")
  break
done

if [[ -n $wifi_iface ]]; then
  printf 'wifi_iface\t%s\n' "$wifi_iface"

  # nmcli, not iw. The original read the radio through `iw`, which is not a
  # dependency of this repo and is not installed here - so that path produced
  # nothing at all and the card would have shown an empty Wi-Fi section. nmcli
  # is already required by this widget for scanning and connecting, and its
  # one call carries SSID, signal, rate and frequency together.
  #
  # The trade is that nmcli reports signal as a percentage where iw gives dBm,
  # so dBm is filled in from iw only when it happens to be available.
  IFS=$'\n' read -r -d '' -a wifi_rows < <(
    nmcli -t -f IN-USE,SSID,SIGNAL,RATE,FREQ dev wifi list ifname "$wifi_iface" --rescan no 2>/dev/null \
      | grep '^\*' && printf '\0'
  )
  if [[ ${#wifi_rows[@]} -gt 0 ]]; then
    # -t escapes a literal colon inside an SSID as '\:', so unescape after
    # splitting rather than splitting on every colon in the name.
    IFS=':' read -r _inuse ssid signal rate freq <<<"${wifi_rows[0]//\\:/$'\x01'}"
    ssid=${ssid//$'\x01'/:}
    [[ -n $ssid ]] && printf 'ssid\t%s\n' "$ssid"
    [[ -n $signal ]] && printf 'signal_pct\t%s\n' "$signal"
    [[ -n $rate ]] && printf 'bitrate\t%s\n' "$rate"
    [[ -n $freq ]] && printf 'freq\t%s\n' "${freq% MHz}"
  fi

  if command -v iw >/dev/null 2>&1; then
    dbm=$(iw dev "$wifi_iface" link 2>/dev/null | awk '/signal:/ { print $2; exit }')
    [[ -n $dbm ]] && printf 'signal_dbm\t%s\n' "$dbm"
  fi
fi

# Latency and loss. Two probes at 0.3s spacing keeps the whole call near half a
# second; the router and the internet are pinged in parallel so one unreachable
# gateway cannot double the wait.
ping_sample() {
  local host=$1 out
  out=$(LC_ALL=C ping -n -c 2 -i 0.3 -W 1 "$host" 2>/dev/null) || true
  local rtt loss
  rtt=$(awk -F'time[=<]' '/time[=<]/ { split($2, p, " "); print p[1]; exit }' <<<"$out")
  loss=$(sed -n 's/.*, \([0-9.]*\)% packet loss.*/\1/p' <<<"$out" | head -n 1)
  printf '%s\t%s' "${rtt:-}" "${loss:-}"
}

if command -v ping >/dev/null 2>&1; then
  tmp=$(mktemp -d) || exit 0
  [[ -n $gw ]] && { ping_sample "$gw" >"$tmp/router" & router_pid=$!; }
  ping_sample "$INTERNET_PROBE" >"$tmp/inet" & inet_pid=$!

  if [[ -n ${router_pid:-} ]]; then
    wait "$router_pid"
    IFS=$'\t' read -r rtt loss <"$tmp/router"
    [[ -n $rtt ]] && printf 'router_ping_ms\t%s\n' "$rtt"
  fi
  wait "$inet_pid"
  IFS=$'\t' read -r rtt loss <"$tmp/inet"
  [[ -n $rtt ]] && printf 'internet_ping_ms\t%s\n' "$rtt"
  [[ -n $loss ]] && printf 'loss_pct\t%s\n' "$loss"
  rm -rf "$tmp"
fi
