#!/usr/bin/env bash
# Emit a Wi-Fi join QR code for the current network, as a 0/1 matrix.
#
# Ported from Omarchy's omarchy-network-qr (omacom/omarchy, MIT, DHH): the
# nmcli secret lookup, the WIFI: payload escaping, the WEP special case and
# collapsing qrencode's two-character ASCII cells into one 0/1 value per
# module so the card can draw it with plain QML rectangles.
#
# Output:
#   meta <TAB> <interface> <TAB> <security> <TAB> <ssid>
#   then one line of 0/1 per QR row.
# On failure: a single line  error <TAB> <message>

set -uo pipefail

fail() { printf 'error\t%s\n' "$1"; exit 0; }

command -v qrencode >/dev/null 2>&1 \
  || fail "qrencode is not installed - sudo pacman -S qrencode"

interface="${1:-}"
if [[ -z $interface ]]; then
  route_device=$(ip route get 1.1.1.1 2>/dev/null \
    | awk '{ for (i=1;i<=NF;i++) if ($i=="dev") { print $(i+1); exit } }')
  if [[ -n $route_device && -d /sys/class/net/$route_device/wireless ]]; then
    interface=$route_device
  else
    # nmcli localises state names, so pin the locale; the prefix match also
    # accepts states like "connected (externally)".
    interface=$(LC_ALL=C nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null \
      | awk -F: '$2 == "wifi" && $3 ~ /^connected/ { print $1; exit }')
  fi
fi
[[ -n $interface ]] || fail "No active Wi-Fi connection"

uuid=$(nmcli --get-values GENERAL.CON-UUID device show "$interface" 2>/dev/null | head -n 1)
[[ -n $uuid && $uuid != "--" ]] || fail "No active Wi-Fi connection"

mapfile -t fields < <(nmcli --show-secrets --escape no --get-values \
  802-11-wireless.ssid,802-11-wireless-security.key-mgmt,802-11-wireless-security.psk,802-11-wireless.hidden,802-11-wireless-security.wep-key0 \
  connection show uuid "$uuid" 2>/dev/null)

ssid=${fields[0]:-}
key_management=${fields[1]:-}
password=${fields[2]:-}
hidden=${fields[3]:-no}
wep_key=${fields[4]:-}

[[ -n $ssid ]] || fail "Could not read the Wi-Fi name"
[[ $key_management != *eap* && $key_management != *ieee8021x* ]] \
  || fail "Enterprise Wi-Fi cannot be shared by password QR"

escape_wifi_qr() {
  local v=$1
  v=${v//\\/\\\\}; v=${v//;/\;}; v=${v//,/\\,}; v=${v//:/\\:}
  printf '%s' "$v"
}

if [[ -n $key_management && $key_management != "none" ]]; then
  [[ -n $password ]] || fail "Could not read the Wi-Fi password"
  security=WPA
elif [[ -n $wep_key ]]; then
  # NetworkManager models WEP as key-mgmt "none" plus a wep-key; encoding that
  # as an open network yields a QR that silently fails to join.
  password=$wep_key
  security=WEP
else
  password=""
  security=nopass
fi

payload="WIFI:T:$security;S:$(escape_wifi_qr "$ssid");P:$(escape_wifi_qr "$password");"
[[ $hidden == "yes" ]] && payload+="H:true;"
payload+=";"

printf 'meta\t%s\t%s\t%s\n' "$interface" "$security" "$ssid"

# Margin 4 is the spec quiet zone. ASCII output uses two characters per
# module, so collapse each pair into one cell.
ascii=$(printf '%s' "$payload" | qrencode --type ASCII --margin 4 --output - 2>/dev/null) \
  || fail "qrencode failed"
while IFS= read -r line; do
  row=
  for ((c = 0; c < ${#line}; c += 2)); do
    [[ ${line:c:2} == *#* ]] && row+=1 || row+=0
  done
  printf '%s\n' "$row"
done <<<"$ascii"
