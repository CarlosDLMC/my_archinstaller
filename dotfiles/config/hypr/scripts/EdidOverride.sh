#!/usr/bin/env bash
# The kernel parameter drm.edid_firmware=CONNECTOR:edid/FILE.bin makes the
# kernel ignore what the monitor on that port says about itself and use the
# saved file instead. It was once set by hand to run a Samsung LS24A600N at
# 2560x1440@75 over a ThinkPad's HDMI - and then every OTHER monitor on that
# port got the Samsung's modes and showed "out of range". The installer never
# sets it; this finds a leftover one.
#
#   EdidOverride.sh check    at login: a warning if the parameter is set
#   EdidOverride.sh remove   in a terminal: take it out (sudo, with backups)
#
# remove edits the systemd-boot entries in /boot/loader/entries (the only
# boot loader this setup installs), empties the mkinitcpio FILES= line that
# carried the .bin into the initramfs, and rebuilds the initramfs. The .bin
# itself stays in /usr/lib/firmware/edid/ - on its own it does nothing.

iDIR="$HOME/.config/hypr/notify/images"
param=$(grep -o 'drm\.edid_firmware=[^ ]*' /proc/cmdline)

case $1 in
  check)
    [[ -z $param ]] && exit 0
    notify-send -u critical -i "$iDIR/error.png" "Подменённый EDID монитора" \
      "Ядро запущено с $param: другие мониторы на этом порту могут показывать «out of range». Убрать: в терминале ~/.config/hypr/scripts/EdidOverride.sh remove, затем перезагрузка."
    ;;
  remove)
    stamp=bak-edid-$(date +%Y%m%d-%H%M%S)
    found=0
    for e in $(sudo find /boot/loader/entries -maxdepth 1 -name '*.conf'); do
      sudo grep -q 'drm\.edid_firmware=' "$e" || continue
      sudo cp "$e" "$e.$stamp"
      sudo sed -i -E 's/ ?drm\.edid_firmware=[^ ]*//' "$e"
      echo "removed from $e (backup $e.$stamp)"
      found=1
    done
    if grep -qE '^FILES=\(.*firmware/edid/' /etc/mkinitcpio.conf; then
      sudo cp /etc/mkinitcpio.conf "/etc/mkinitcpio.conf.$stamp"
      sudo sed -i -E '/^FILES=\(/ s#[^ ()]*firmware/edid/[^ ()]*##g; /^FILES=\(/ s/\( +/(/; /^FILES=\(/ s/ +\)/)/' /etc/mkinitcpio.conf
      echo "removed from /etc/mkinitcpio.conf FILES= (backup /etc/mkinitcpio.conf.$stamp)"
      found=1
    fi
    if (( found )); then
      sudo mkinitcpio -P && echo "Done. Reboot for it to take effect."
    else
      echo "No EDID override found in the boot entries or mkinitcpio.conf."
      [[ -n $param ]] && echo "The running kernel still has $param: set by another boot loader?"
    fi
    ;;
  *) echo "usage: $0 check|remove" >&2; exit 2 ;;
esac
