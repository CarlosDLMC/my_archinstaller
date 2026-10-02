#!/bin/bash
# Enable essential systemd services #

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Change the working directory to the parent directory of the script
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "[ERROR] Failed to change directory to $PARENT_DIR"; exit 1; }

# Source the global functions script
if ! source "$SCRIPT_DIR/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

# Set the name of the log file to include the current date and time
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_services.log"

printf "\n${INFO} Enabling essential ${SKY_BLUE}system services${RESET}...\n" | tee -a "$LOG"

# Enable NetworkManager - and make it the ONLY thing managing the network.
#
# A plain Arch installed with archinstall's "Copy ISO network configuration" (a
# common pick; all the README asks for is "an Internet connection") comes up
# with iwd + systemd-networkd + systemd-resolved enabled, and a hand-rolled
# install may use dhcpcd. This used to enable NM on top and leave the others
# enabled too: after the reboot NM's default Wi-Fi backend, wpa_supplicant,
# fought iwd for wlan0, NM and networkd both ran DHCP on the same link, and
# Wi-Fi was flaky or gone - while the final check, which only asked whether NM
# was enabled, passed. CachyOS runs NM alone, so there none of this triggers and
# NM is enabled and started exactly as before.
#
# iwd is kept, under NM, in the same layout archinstall's own "NetworkManager
# (iwd backend)" choice writes: wifi.backend=iwd, and iwd.service disabled
# because NM starts iwd itself over D-Bus (the Arch wiki says not to enable it).
# That is what keeps the saved Wi-Fi working: its passphrase is in
# /var/lib/iwd/*.psk and NM has no profile for it, but with the iwd backend NM
# mirrors iwd's known networks and iwd autoconnects to them as before.
#
# Everything is disabled WITHOUT --now, and NM is only enabled, not started,
# while another manager is still running: started now, NM would take over the
# links networkd/iwd are holding in the middle of the install. The handover
# happens at the reboot. systemd-resolved is left alone - it is handled below.
#
# netctl, connman, the wiki's per-interface wpa_supplicant@wlan0, and dhcpcd
# with the wiki's 10-wpa_supplicant hook linked in are NOT handed over: they
# keep the Wi-Fi password in their own files, and NM has no importer for any of
# them. The first version of this block disabled the DHCP client under a
# wpa_supplicant@wlan0 + dhcpcd laptop and left the supplicant enabled - the
# reboot joined the Wi-Fi with no address, and NM could not take the card
# either (its own wpa_supplicant fails with "ctrl_iface exists"). With one of
# those enabled nothing is changed at all, and NM is NOT enabled either: the
# second version still enabled it, and a netctl-auto@wlan0 laptop was left to
# reboot into NM and netctl both claiming wlan0. Left off, NM trips the final
# check's "NetworkManager.service is not enabled", which stops the preset's
# auto-reboot, and a reboot by hand comes back on the setup that works now. The
# warning gives the commands to move over by hand.
#
# A networkd link with a static address (archinstall's "Manual configuration")
# is converted into a NetworkManager profile, and then networkd goes like any
# other. It used to be left enabled with a warning while NM was enabled anyway:
# after a reboot by hand NM's automatic wired DHCP profile and networkd's static
# address both claimed the link. A .network file that uses anything the
# conversion cannot carry over exactly is treated like netctl above instead -
# nothing changes and NM is not enabled.
printf "\n${NOTE} Enabling ${SKY_BLUE}NetworkManager${RESET}...\n" | tee -a "$LOG"
if ! systemctl cat NetworkManager.service &>/dev/null; then
  # Disabling the others without NM would boot the new machine with no network
  # at all, so nothing is touched.
  echo "${WARN} NetworkManager.service does not exist (networkmanager not installed?). Leaving the current network setup alone." | tee -a "$LOG"
else
  # Per-interface and per-profile instances (dhcpcd@enp3s0, wpa_supplicant@wlan0,
  # netctl@home) never show in list-unit-files, only their template does. They
  # are found as loaded units, and as the .wants symlinks that enable them:
  # netctl-auto@wlan0 hangs off the Wi-Fi card's device unit, so it is not even
  # loaded while that card is missing.
  net_instances() {
    local _pat _link
    {
      systemctl list-units --all --plain --no-legend "$@" 2>/dev/null | cut -d' ' -f1
      for _pat in "$@"; do
        for _link in /etc/systemd/system/*.wants/$_pat /etc/systemd/system/*.requires/$_pat; do
          if [ -L "$_link" ]; then
            printf '%s\n' "${_link##*/}"
          fi
        done
      done
    } | sort -u
  }

  net_units=(systemd-networkd.service systemd-networkd.socket)
  dhcpcd_units=(dhcpcd.service)
  while read -r _unit; do
    if [ -n "$_unit" ]; then
      dhcpcd_units+=("$_unit")
    fi
  done < <(net_instances 'dhcpcd@*.service')

  # The ones that keep the Wi-Fi password where NM cannot import it (see above).
  # netctl.service restores whichever netctl profiles were up at shutdown.
  net_hold_units=(connman.service netctl.service)
  while read -r _unit; do
    if [ -n "$_unit" ]; then
      net_hold_units+=("$_unit")
    fi
  done < <(net_instances 'wpa_supplicant@*.service' 'wpa_supplicant-nl80211@*.service' 'wpa_supplicant-wired@*.service' \
             'netctl@*.service' 'netctl-auto@*.service' 'netctl-ifplugd@*.service')

  # dhcpcd is normally only a DHCP client, safe to hand over. The wiki's dhcpcd
  # Wi-Fi setup links /usr/share/dhcpcd/hooks/10-wpa_supplicant (shipped
  # inactive) into /usr/lib/dhcpcd/dhcpcd-hooks/, and then dhcpcd starts
  # wpa_supplicant on the card itself from
  # /etc/wpa_supplicant/wpa_supplicant*.conf: dhcpcd.service is the only unit
  # enabled, and disabling it (as the DHCP client it looks like) booted a
  # Wi-Fi-only laptop with no network and no profile NM could use.
  dhcpcd_wifi_hook="/usr/lib/dhcpcd/dhcpcd-hooks/10-wpa_supplicant"
  if [ -e "$dhcpcd_wifi_hook" ]; then
    net_hold_units+=("${dhcpcd_units[@]}")
  else
    net_units+=("${dhcpcd_units[@]}")
  fi

  other_net_enabled=()
  other_net_active=()
  for _unit in "${net_units[@]}" iwd.service; do
    if [ "$(systemctl is-enabled "$_unit" 2>/dev/null)" = enabled ]; then
      other_net_enabled+=("$_unit")
    fi
    if systemctl is-active --quiet "$_unit"; then
      other_net_active+=("$_unit")
    fi
  done
  net_hold_enabled=()
  for _unit in "${net_hold_units[@]}"; do
    if [ "$(systemctl is-enabled "$_unit" 2>/dev/null)" = enabled ]; then
      net_hold_enabled+=("$_unit")
    fi
    # Active counts too, so NM is not started next to a running netctl/connman.
    if systemctl is-active --quiet "$_unit"; then
      other_net_active+=("$_unit")
    fi
  done

  # Written before NM can start, so it never brings wpa_supplicant up against
  # iwd even for a moment. Skipped when netctl/connman/wpa_supplicant@/hooked
  # dhcpcd stays: connman drives iwd itself and needs iwd.service left enabled.
  iwd_under_nm="no"
  if [[ " ${other_net_enabled[*]} " == *" iwd.service "* ]] && [ ${#net_hold_enabled[@]} -eq 0 ]; then
    backend_conf="/etc/NetworkManager/conf.d/wifi_backend.conf"
    if ! NetworkManager --print-config 2>/dev/null | grep -qx 'wifi.backend=iwd'; then
      if [ -f "$backend_conf" ]; then
        sudo cp "$backend_conf" "$backend_conf".bak-"$(date +%Y%m%d-%H%M%S)"
      fi
      sudo mkdir -p /etc/NetworkManager/conf.d
      printf '# Installed by my_archinstaller (install-scripts/services.sh): iwd already held\n# this machine'"'"'s Wi-Fi, so NetworkManager drives iwd instead of wpa_supplicant.\n[device]\nwifi.backend=iwd\n' | sudo tee "$backend_conf" >/dev/null
    fi
    # Checked through NM's merged config, not the file: a later conf.d file can
    # still override it, and iwd must not be disabled under a wpa_supplicant NM.
    if NetworkManager --print-config 2>/dev/null | grep -qx 'wifi.backend=iwd'; then
      iwd_under_nm="yes"
      echo "${OK} NetworkManager will use iwd as its Wi-Fi backend - the Wi-Fi networks iwd saved keep working." | tee -a "$LOG"
    else
      echo "${WARN} Wrote $backend_conf but NetworkManager still does not report wifi.backend=iwd - another file in /etc/NetworkManager/conf.d overrides it." | tee -a "$LOG"
      echo "${WARN} iwd.service left enabled; fix the override and re-run, or wpa_supplicant and iwd will fight over the Wi-Fi card." | tee -a "$LOG"
    fi
  fi

  # archinstall's "Manual configuration" can give a link a static address in
  # networkd. NM would just run DHCP there, which on a network without a DHCP
  # server is no network at all - so the address is carried over into an NM
  # keyfile first. `nmcli --offline` builds the keyfile without a running NM and
  # rejects any value it would not accept. The python below decides whether the
  # .network file can be carried over EXACTLY: one [Match] Name= that is a
  # physical ethernet card present right now, Address= with a prefix, at most
  # one gateway per family, DNS= / Domains= as plain addresses and names, and
  # nothing else. Anything more (globs, MAC matches, extra routes, DHCP next to
  # the static address, a .netdev defining a bridge or VLAN) keeps networkd, and
  # then NM is not enabled at all - a half-converted network is the one outcome
  # worse than the warning.
  networkd_static=()
  while IFS= read -r _f; do
    if [ -n "$_f" ]; then
      networkd_static+=("$_f")
    fi
  done < <(grep -lsE '^[[:space:]]*Address[[:space:]]*=' /etc/systemd/network/*.network 2>/dev/null || true)
  networkd_static_left=()
  networkd_static_hint="nmcli connection add type ethernet ifname <if> ipv4.method manual ipv4.addresses <addr/prefix> ipv4.gateway <gw>"

  if [ ${#networkd_static[@]} -gt 0 ] && [ ${#net_hold_enabled[@]} -eq 0 ] \
     && [[ " ${other_net_enabled[*]} " == *" systemd-networkd."* ]]; then
    networkd_to_nm=$(cat <<'PY'
import ipaddress, os, sys

import fnmatch

path = sys.argv[1]
others = sys.argv[2:]
stem = os.path.basename(path)[:-len(".network")]

def fail(why):
    print(why, file=sys.stderr)
    sys.exit(2)

sections = []
try:
    with open(path) as f:
        lines = f.read().splitlines()
except OSError as e:
    fail(f"cannot read it ({e.strerror})")
for raw in lines:
    line = raw.strip()
    if not line or line[0] in "#;":
        continue
    if line.endswith("\\"):
        fail("it uses a line continuation")
    if line.startswith("[") and line.endswith("]"):
        sections.append((line[1:-1], []))
        continue
    if not sections or "=" not in line:
        fail(f"unexpected line: {line}")
    k, v = line.split("=", 1)
    k, v = k.strip(), v.strip()
    if not v:
        fail(f"{k}= with an empty value (a list reset)")
    sections[-1][1].append((k, v))

name = None
addrs, gws, dns, search = [], [], [], []
matches = 0
for sec, kvs in sections:
    if sec == "Match":
        matches += 1
        for k, v in kvs:
            if k != "Name":
                fail(f"[Match] {k}= (only a single Name= is converted)")
            if name is not None or any(c in v for c in "*?[]! \t"):
                fail(f"[Match] Name={v} is not one literal interface name")
            name = v
    elif sec == "Network":
        for k, v in kvs:
            if k == "Address":
                addrs.append(v)
            elif k == "Gateway":
                gws.append(v)
            elif k == "DNS":
                dns += v.split()
            elif k == "Domains":
                search += v.split()
            elif k == "DHCP":
                if v.lower() not in ("no", "false", "0", "off"):
                    fail(f"DHCP={v} next to a static address")
            else:
                fail(f"[Network] {k}=")
    elif sec == "Address":
        for k, v in kvs:
            if k != "Address":
                fail(f"[Address] {k}=")
            addrs.append(v)
    elif sec == "Route":
        rgw, dest = None, None
        for k, v in kvs:
            if k == "Gateway":
                rgw = v
            elif k == "Destination":
                dest = v
            else:
                fail(f"[Route] {k}=")
        if rgw is None or dest not in (None, "0.0.0.0/0", "::/0"):
            fail("a [Route] other than a plain default route")
        gws.append(rgw)
    else:
        fail(f"a [{sec}] section")
if matches != 1 or name is None:
    fail("it does not match exactly one interface by Name=")

# networkd applies only the FIRST .network file (in name order) whose [Match]
# fits a link. Another file that could match this interface - a glob, a MAC or
# Type= match, an empty [Match], the same Name= - means the link may not be
# running this file at all, so it is not converted.
for other in others:
    if os.path.basename(other) == os.path.basename(path):
        continue
    try:
        with open(other) as f:
            olines = f.read().splitlines()
    except OSError:
        fail(f"cannot read {other}")
    sec, onames, okeys = None, [], 0
    for raw in olines:
        line = raw.strip()
        if not line or line[0] in "#;":
            continue
        if line.startswith("[") and line.endswith("]"):
            sec = line[1:-1]
            continue
        if sec == "Match" and "=" in line:
            k, v = (x.strip() for x in line.split("=", 1))
            okeys += 1
            if k != "Name":
                fail(f"{other} matches by [Match] {k}=, which could also match {name}")
            onames += v.split()
    if okeys == 0:
        fail(f"{other} has no [Match] Name=, so it matches every link")
    for pat in onames:
        if pat.startswith("!") or fnmatch.fnmatchcase(name, pat):
            fail(f"{other} ([Match] Name={pat}) can also match {name}")

sysnet = f"/sys/class/net/{name}"
if not os.path.isdir(sysnet):
    fail(f"{name} is not present on this machine")
if not os.path.exists(f"{sysnet}/device"):
    fail(f"{name} is a virtual interface")
for d in ("wireless", "phy80211", "bridge", "bonding"):
    if os.path.exists(f"{sysnet}/{d}"):
        fail(f"{name} is not a plain ethernet link ({d})")
try:
    with open(f"{sysnet}/type") as t:
        if t.read().strip() != "1":
            fail(f"{name} is not an ethernet link")
except OSError:
    fail(f"cannot read {sysnet}/type")

v4a, v6a, v4g, v6g, v4d, v6d = [], [], [], [], [], []
for a in addrs:
    if "/" not in a:
        fail(f"Address={a} has no prefix length")
    try:
        i = ipaddress.ip_interface(a)
    except ValueError:
        fail(f"Address={a} is not an address")
    if i.ip.is_unspecified:
        fail(f"Address={a} asks networkd to pick from a pool")
    (v4a if i.version == 4 else v6a).append(str(i))
for g in gws:
    try:
        ip = ipaddress.ip_address(g)
    except ValueError:
        fail(f"Gateway={g} is not a plain address")
    (v4g if ip.version == 4 else v6g).append(str(ip))
for d in dns:
    try:
        ip = ipaddress.ip_address(d)
    except ValueError:
        fail(f"DNS={d} is not a plain address")
    (v4d if ip.version == 4 else v6d).append(str(ip))
for s in search:
    if s.startswith("~"):
        fail(f"Domains={s} is a routing-only domain")
if not (v4a or v6a):
    fail("it has no usable Address=")
if len(v4g) > 1 or len(v6g) > 1:
    fail("more than one gateway per address family")
if (v4g and not v4a) or (v6g and not v6a):
    fail("a gateway with no address of its family")

# Priority 100: a DHCP ethernet profile NM already has (an older run of this
# script enabled NM unconditionally) must not win the autoconnect tie-break.
args = ["type", "ethernet", "con-name", f"networkd-{stem}", "ifname", name,
        "connection.autoconnect-priority", "100"]
if v4a:
    args += ["ipv4.method", "manual", "ipv4.addresses", ",".join(v4a)]
    if v4g:
        args += ["ipv4.gateway", v4g[0]]
else:
    args += ["ipv4.method", "disabled"]
if v4d:
    args += ["ipv4.dns", ",".join(v4d)]
# "auto" even next to static IPv6 addresses: networkd keeps accepting router
# advertisements beside them (IPv6AcceptRA= defaults to on), and NM's "manual"
# would drop the SLAAC addresses and the RA default route. eui64 and privacy
# off are networkd's defaults too - NM's own (stable-privacy) would give the
# link different IPv6 addresses than it has today.
args += ["ipv6.method", "auto", "ipv6.addr-gen-mode", "eui64", "ipv6.ip6-privacy", "0"]
if v6a:
    args += ["ipv6.addresses", ",".join(v6a)]
    if v6g:
        args += ["ipv6.gateway", v6g[0]]
if v6d:
    args += ["ipv6.dns", ",".join(v6d)]
if search:
    args += ["ipv4.dns-search" if v4a else "ipv6.dns-search", ",".join(search)]
sys.stdout.write("\0".join(args) + "\0")
PY
)
    _nm_tmp=$(mktemp -d)
    _nm_profiles=()
    _nm_sources=()
    # Every .network networkd reads besides these, for the first-match check in
    # the python. /usr/lib's are left out: systemd's own there match container
    # and VM links by Kind=/Virtualization=, never a physical card.
    networkd_all=()
    for _f in /etc/systemd/network/*.network; do
      if [ -e "$_f" ]; then
        networkd_all+=("$_f")
      fi
    done
    if compgen -G '/etc/systemd/network/*.netdev' >/dev/null; then
      networkd_static_left=("${networkd_static[@]}")
      echo "${WARN} /etc/systemd/network also defines virtual devices (*.netdev), which a NetworkManager profile would not recreate - systemd-networkd stays." | tee -a "$LOG"
    # A drop-in can add a route, an address or DHCP that the python never sees.
    elif compgen -G '/etc/systemd/network/*.network.d/*.conf' >/dev/null \
         || compgen -G '/run/systemd/network/*.network' >/dev/null \
         || compgen -G '/run/systemd/network/*.network.d/*.conf' >/dev/null; then
      networkd_static_left=("${networkd_static[@]}")
      echo "${WARN} systemd-networkd also reads drop-ins (*.network.d/) or /run/systemd/network, which a conversion of the main files would miss - systemd-networkd stays." | tee -a "$LOG"
    else
      for _f in "${networkd_static[@]}"; do
        _stem="${_f##*/}"
        _stem="${_stem%.network}"
        if ! _why=$(python3 -c "$networkd_to_nm" "$_f" "${networkd_all[@]}" 2>&1 >"$_nm_tmp/$_stem.args"); then
          networkd_static_left+=("$_f")
          echo "${WARN} $_f cannot be carried over to NetworkManager exactly: ${_why:-python3 failed}" | tee -a "$LOG"
          continue
        fi
        mapfile -d '' -t _nm_args < "$_nm_tmp/$_stem.args"
        if ! nmcli --offline connection add "${_nm_args[@]}" >"$_nm_tmp/networkd-$_stem.nmconnection" 2>"$_nm_tmp/$_stem.err"; then
          networkd_static_left+=("$_f")
          echo "${WARN} nmcli could not build a profile from $_f: $(head -n 1 "$_nm_tmp/$_stem.err")" | tee -a "$LOG"
          continue
        fi
        _nm_profiles+=("networkd-$_stem")
        _nm_sources+=("$_f")
      done
    fi
    # All or nothing: with even one file left networkd stays enabled, and NM is
    # not enabled next to it (below), so nothing is installed.
    if [ ${#networkd_static_left[@]} -eq 0 ]; then
      _nm_written=()
      for _i in "${!_nm_profiles[@]}"; do
        _dst="/etc/NetworkManager/system-connections/${_nm_profiles[$_i]}.nmconnection"
        if sudo test -e "$_dst"; then
          echo "${OK} $_dst already exists - kept as it is." | tee -a "$LOG"
        # NM ignores a keyfile that is not root-owned and 600.
        elif sudo install -D -m 600 -o root -g root "$_nm_tmp/${_nm_profiles[$_i]}.nmconnection" "$_dst"; then
          _nm_written+=("$_dst")
          echo "${OK} Static address from ${_nm_sources[$_i]} carried over to NetworkManager: $_dst" | tee -a "$LOG"
        else
          networkd_static_left+=("${_nm_sources[$_i]}")
          echo "${WARN} Could not write $_dst - systemd-networkd stays." | tee -a "$LOG"
        fi
      done
      # Still all or nothing: take back what this run wrote, so a later "enable
      # NM and recreate the address" does not end up with two profiles.
      if [ ${#networkd_static_left[@]} -gt 0 ] && [ ${#_nm_written[@]} -gt 0 ]; then
        sudo rm -f "${_nm_written[@]}"
        echo "${WARN} Removed the profiles this run had already written: ${_nm_written[*]}" | tee -a "$LOG"
      fi
    fi
    rm -rf "$_nm_tmp"
  fi

  # Not enabled while one of the units that keep a Wi-Fi password stays (see
  # above), or networkd keeps a static address that could not be carried over.
  # An NM that was already enabled - by hand, or by an older run of this
  # script, which enabled it unconditionally - is not disabled either: which of
  # the two holds the working network is not knowable from here.
  net_keep=("${net_hold_enabled[@]}")
  if [ ${#networkd_static_left[@]} -gt 0 ]; then
    net_keep+=(systemd-networkd.service)
  fi
  if [ ${#net_keep[@]} -gt 0 ]; then
    if [ "$(systemctl is-enabled NetworkManager.service 2>/dev/null)" = enabled ]; then
      echo "${WARN} NetworkManager is already enabled next to ${net_keep[*]} - both will claim the network after the reboot (see the warning below)." | tee -a "$LOG"
    else
      echo "${WARN} NetworkManager NOT enabled: ${net_keep[*]} stays in charge of the network (see the warning below). The final check will stop the auto-reboot on this." | tee -a "$LOG"
    fi
  elif [ ${#other_net_active[@]} -gt 0 ] && ! systemctl is-active --quiet NetworkManager.service; then
    sudo systemctl enable NetworkManager.service 2>&1 | tee -a "$LOG"
    if [ "$(systemctl is-enabled NetworkManager.service 2>/dev/null)" = enabled ]; then
      echo "${OK} NetworkManager enabled. It takes over from ${other_net_active[*]} at the next boot - not started now, so this session keeps its connection." | tee -a "$LOG"
    else
      echo "${WARN} NetworkManager could not be enabled. Network connectivity may not work after the reboot." | tee -a "$LOG"
    fi
  else
    sudo systemctl enable --now NetworkManager.service 2>&1 | tee -a "$LOG"
    if systemctl is-active --quiet NetworkManager.service; then
      echo "${OK} NetworkManager is running." | tee -a "$LOG"
    else
      echo "${WARN} NetworkManager failed to start. Network connectivity may not work." | tee -a "$LOG"
    fi
  fi

  if [ ${#net_hold_enabled[@]} -gt 0 ]; then
    net_cred_dirs=()
    for _unit in "${net_hold_enabled[@]}"; do
      case "$_unit" in
        wpa_supplicant*|dhcpcd*) _dir="/etc/wpa_supplicant/" ;;
        netctl*)                 _dir="/etc/netctl/" ;;
        *)                       _dir="/var/lib/connman/" ;;
      esac
      if [[ " ${net_cred_dirs[*]} " != *" $_dir "* ]]; then
        net_cred_dirs+=("$_dir")
      fi
    done
    echo "${WARN} Network setup left as it is: ${net_hold_enabled[*]} keeps the Wi-Fi password in ${net_cred_dirs[*]}, which NetworkManager cannot import - disabling it would boot this machine with no Wi-Fi." | tee -a "$LOG"
    if [[ " ${net_hold_enabled[*]} " == *" dhcpcd"* ]]; then
      echo "${WARN} dhcpcd is more than a DHCP client here: $dhcpcd_wifi_hook is linked in, so dhcpcd starts wpa_supplicant on the Wi-Fi card itself." | tee -a "$LOG"
    fi
    # %q, so a netctl profile's escaped name (netctl@home\x2dwifi) survives a paste.
    echo "${WARN} To move to NetworkManager (the network drops for a moment): sudo systemctl disable --now$(printf ' %q' "${net_hold_enabled[@]}" "${other_net_enabled[@]}") && sudo systemctl enable --now NetworkManager.service - then for Wi-Fi: nmcli device wifi connect <SSID> password <password>" | tee -a "$LOG"
    if [ ${#networkd_static[@]} -gt 0 ] && [[ " ${other_net_enabled[*]} " == *" systemd-networkd."* ]]; then
      echo "${WARN} systemd-networkd also sets a static address in ${networkd_static[*]} - once NetworkManager runs, recreate it there: $networkd_static_hint" | tee -a "$LOG"
    fi
  # Only once NM is known to be enabled - otherwise this would leave nothing.
  elif [ ${#other_net_enabled[@]} -gt 0 ] && [ "$(systemctl is-enabled NetworkManager.service 2>/dev/null)" = enabled ]; then
    networkd_warned="no"
    for _unit in "${other_net_enabled[@]}"; do
      case "$_unit" in
        iwd.service)
          [ "$iwd_under_nm" = "yes" ] || continue
          ;;
        systemd-networkd.*)
          if [ ${#networkd_static_left[@]} -gt 0 ]; then
            if [ "$networkd_warned" = "no" ]; then
              echo "${WARN} systemd-networkd left enabled: a static address is set in ${networkd_static_left[*]}, and it could not be carried over (see above)." | tee -a "$LOG"
              echo "${WARN} Recreate it in NetworkManager ($networkd_static_hint), then: sudo systemctl disable systemd-networkd.service" | tee -a "$LOG"
              networkd_warned="yes"
            fi
            continue
          fi
          ;;
      esac
      sudo systemctl disable "$_unit" 2>&1 | tee -a "$LOG"
      if [ "$(systemctl is-enabled "$_unit" 2>/dev/null)" = enabled ]; then
        echo "${WARN} Could not disable $_unit - it and NetworkManager will both manage the network after the reboot." | tee -a "$LOG"
      else
        echo "${OK} $_unit disabled; NetworkManager manages the network from the next boot." | tee -a "$LOG"
      fi
    done
  # NM was not enabled above, because of a static address that stays in networkd.
  elif [ ${#networkd_static_left[@]} -gt 0 ]; then
    echo "${WARN} Network setup left as it is: systemd-networkd sets a static address in ${networkd_static_left[*]} that could not be carried over exactly (see above), and NetworkManager would only run DHCP there." | tee -a "$LOG"
    echo "${WARN} To move to NetworkManager (the network drops for a moment): sudo systemctl disable --now$(printf ' %q' "${other_net_enabled[@]}") && sudo systemctl enable --now NetworkManager.service - then recreate the address: $networkd_static_hint" | tee -a "$LOG"
  fi
fi

# systemd-resolved, because 01-hypr-pkgs.sh installs systemd-resolvconf.
#
# systemd-resolvconf replaces the classic resolvconf with a shim over
# resolvectl, and that shim only works while systemd-resolved is running. A
# stock archinstall + NetworkManager system has no resolvconf and no resolved,
# so NM writes /etc/resolv.conf itself and DNS works. Add the shim without the
# daemon and NM switches to the resolvconf path, which then fails: the link
# comes up, nothing resolves, and nothing says why. wg-quick has the same
# dependency for the DNS= line every WireGuard config here carries, so the
# bar's VPN selector was broken too. This machine only worked because resolved
# had been enabled by hand months before the installer existed.
printf "\n${NOTE} Enabling ${SKY_BLUE}systemd-resolved${RESET}...\n" | tee -a "$LOG"
if ! pacman -Qi systemd-resolvconf &>/dev/null; then
  echo "${INFO} systemd-resolvconf is not installed; leaving DNS to NetworkManager." | tee -a "$LOG"
else
  sudo systemctl enable --now systemd-resolved.service 2>&1 | tee -a "$LOG"
  if systemctl is-active --quiet systemd-resolved.service; then
    echo "${OK} systemd-resolved is running." | tee -a "$LOG"
    # Point /etc/resolv.conf at the stub so every resolver, not just NM, goes
    # through resolved. Kept as a backup rather than deleted if it is a real
    # file (NM or archinstall wrote it).
    stub="/run/systemd/resolve/stub-resolv.conf"
    if [ "$(readlink -f /etc/resolv.conf)" != "$stub" ]; then
      if [ -f /etc/resolv.conf ] && [ ! -L /etc/resolv.conf ]; then
        sudo cp /etc/resolv.conf /etc/resolv.conf.bak-"$(date +%Y%m%d-%H%M%S)"
      fi
      # Guarded: this runs under Global_functions.sh's set -e, and a resolv.conf
      # frozen with `chattr +i` (the wiki's way to keep NM off it) makes ln fail
      # even as root. Unguarded, that ended services.sh right here - no power
      # profile daemon, no nss-mdns, no avahi - and the final check still passed.
      if sudo ln -sf "$stub" /etc/resolv.conf; then
        echo "${OK} /etc/resolv.conf -> $stub" | tee -a "$LOG"
      else
        echo "${WARN} Could not replace /etc/resolv.conf (immutable? check: lsattr /etc/resolv.conf) - it is left as it is, so DNS does not go through systemd-resolved." | tee -a "$LOG"
      fi
    else
      echo "${OK} /etc/resolv.conf already points at the resolved stub." | tee -a "$LOG"
    fi
    # NM picks resolved up on its own when the service is active; a restart
    # makes it re-evaluate now instead of on the next connection change.
    sudo systemctl try-restart NetworkManager.service 2>&1 | tee -a "$LOG"
  else
    echo "${WARN} systemd-resolved failed to start. DNS may not work with systemd-resolvconf installed." | tee -a "$LOG"
  fi
fi

# Enable whichever daemon provides the power-profiles-daemon D-Bus API.
#
# The unit name is not fixed. power-profiles-daemon.service on Arch;
# tuned-ppd.service (plus tuned.service under it) on CachyOS, where
# tuned-cachy-ppd provides the same interface. Hardcoding the first meant that
# on CachyOS this enabled a unit that does not exist, printed a warning, and
# left the bar's power widget pointing at a daemon nobody had started.
ppd_unit=""
for unit in power-profiles-daemon.service tuned-ppd.service; do
  if systemctl cat "$unit" &>/dev/null; then
    ppd_unit="$unit"
    break
  fi
done

if [ -z "$ppd_unit" ]; then
  echo "${WARN} No power profile daemon unit found. The bar's power widget will be inert." | tee -a "$LOG"
else
  printf "\n${NOTE} Enabling ${SKY_BLUE}${ppd_unit}${RESET}...\n" | tee -a "$LOG"
  # tuned-ppd is only the translation layer; tuned itself does the work.
  if [ "$ppd_unit" == "tuned-ppd.service" ] && systemctl cat tuned.service &>/dev/null; then
    sudo systemctl enable --now tuned.service 2>&1 | tee -a "$LOG"
  fi
  sudo systemctl enable --now "$ppd_unit" 2>&1 | tee -a "$LOG"
  if systemctl is-active --quiet "$ppd_unit"; then
    echo "${OK} $ppd_unit is running." | tee -a "$LOG"
  else
    echo "${WARN} $ppd_unit failed to start. Power profile management may not work." | tee -a "$LOG"
  fi
fi

# Wire nss-mdns into /etc/nsswitch.conf.
#
# thunar.sh enables avahi-daemon, but enabling the daemon is only half of it:
# glibc never asks Avahi unless "mdns_minimal [NOTFOUND=return]" sits in the
# hosts: line, ahead of dns. Without it .local hostnames simply do not resolve
# and nothing reports an error - the name just fails to look up.
printf "\n${NOTE} Wiring ${SKY_BLUE}nss-mdns${RESET} into /etc/nsswitch.conf...\n" | tee -a "$LOG"
if ! pacman -Qi nss-mdns &>/dev/null; then
  echo "${WARN} nss-mdns is not installed. Skipping .local name resolution." | tee -a "$LOG"
elif grep -E '^hosts:' /etc/nsswitch.conf | grep -qE 'mdns_minimal.*\bresolve\b|mdns_minimal.*\bdns\b' && ! grep -E '^hosts:' /etc/nsswitch.conf | grep -qE '\bresolve\b.*mdns_minimal'; then
  echo "${OK} nsswitch.conf already resolves .local names." | tee -a "$LOG"
else
  # Every edit here is `|| true`: set -e is on, and an nsswitch.conf that cannot
  # be written (immutable, say) must not end the script. The grep below reports
  # whether the edit actually landed.
  sudo cp /etc/nsswitch.conf /etc/nsswitch.conf.bak-"$(date +%Y%m%d-%H%M%S)" || true
  # mdns_minimal must come BEFORE `resolve [!UNAVAIL=return]`, otherwise resolved
  # answers (or fails) every .local lookup first and the module is never consulted -
  # which is exactly where the old edit ("before dns") put it on a resolved system.
  # Remove any earlier insertion, then insert before resolve if present, else before dns.
  sudo sed -i -E '/^hosts:/ s/mdns_minimal \[NOTFOUND=return\] //g' /etc/nsswitch.conf || true
  if grep -E '^hosts:' /etc/nsswitch.conf | grep -qw resolve; then
    sudo sed -i -E '/^hosts:/ s/\bresolve\b/mdns_minimal [NOTFOUND=return] resolve/' /etc/nsswitch.conf || true
  else
    sudo sed -i -E '/^hosts:/ s/\bdns\b/mdns_minimal [NOTFOUND=return] dns/' /etc/nsswitch.conf || true
  fi
  if grep -E '^hosts:' /etc/nsswitch.conf | grep -q 'mdns_minimal'; then
    echo "${OK} .local name resolution enabled: $(grep -E '^hosts:' /etc/nsswitch.conf)" | tee -a "$LOG"
  else
    echo "${WARN} Could not edit nsswitch.conf. .local names will not resolve." | tee -a "$LOG"
  fi
fi

# avahi-daemon is enabled HERE, not only by thunar.sh. 01-hypr-pkgs.sh always
# installs avahi, and the block below hands mDNS to it - so with thunar="OFF" the
# daemon was installed but never started, resolved's responder was switched off,
# and nothing answered .local names or printer discovery at all.
if pacman -Qi avahi &>/dev/null && ! systemctl is-enabled avahi-daemon.service &>/dev/null; then
  sudo systemctl enable --now avahi-daemon.service 2>&1 | tee -a "$LOG"
  if systemctl is-enabled avahi-daemon.service &>/dev/null; then
    echo "${OK} avahi-daemon enabled (mDNS responder for .local names and printer discovery)." | tee -a "$LOG"
  else
    echo "${WARN} Could not enable avahi-daemon - .local names and printer discovery will not work." | tee -a "$LOG"
  fi
fi

# Two mDNS responders on one host make mDNS unreliable (avahi says so in the journal).
# When avahi owns mDNS (enabled just above), turn off systemd-resolved's responder.
# nss-mdns above answers .local via avahi. Keyed off the daemon being enabled, not
# the package being installed, so resolved never loses mDNS to a stopped avahi.
if systemctl is-enabled avahi-daemon.service &>/dev/null && systemctl is-enabled systemd-resolved.service &>/dev/null; then
  if [ ! -f /etc/systemd/resolved.conf.d/10-avahi-owns-mdns.conf ]; then
    sudo mkdir -p /etc/systemd/resolved.conf.d
    printf '# Installed by my_archinstaller (install-scripts/services.sh): avahi-daemon is the\n# mDNS responder on this machine; two responders make mDNS unreliable.\n[Resolve]\nMulticastDNS=no\n' | sudo tee /etc/systemd/resolved.conf.d/10-avahi-owns-mdns.conf >/dev/null
    sudo systemctl try-restart systemd-resolved.service 2>&1 | tee -a "$LOG"
    echo "${OK} systemd-resolved's mDNS responder disabled; avahi owns mDNS." | tee -a "$LOG"
  else
    echo "${OK} systemd-resolved mDNS already handed to avahi." | tee -a "$LOG"
  fi
fi

printf "\n%.0s" {1..2}
