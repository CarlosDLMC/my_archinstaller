#!/bin/bash
# Limine boot-menu theme + no auto-boot countdown.
#
# CachyOS installs Limine bare (the pretty menu on its live ISO is GRUB). This puts the
# wallpaper from assets/limine/ on the ESP and prepends the global options from
# assets/limine/theme.conf to limine.conf, then sets `timeout: no` so the menu waits
# for a choice instead of booting the default after a countdown.
#
# THIS IS THE ONE PLACE THE REPO WRITES TO A BOOTLOADER CONFIG, and it was added
# knowingly (2026-09-13) after the rest of the repo went out of its way not to. The
# blast radius is kept small:
#   - only when limine.conf already exists (preset "auto" = Limine detected);
#   - the file is backed up next to itself as limine.conf.pre-theme (kept, never
#     overwritten) before the first change;
#   - the edit is confined to a marked block at the top plus the one `timeout:` line;
#     the OS entries below are compared before and after and the change is rolled
#     back if they differ;
#   - an unknown key or a missing wallpaper only degrades the look - Limine ignores
#     the former and skips the latter - so a typo here cannot stop the boot;
#   - if config enrollment is on (ENABLE_ENROLL_LIMINE_CONFIG=yes in
#     /etc/default/limine), Limine refuses a config whose hash it has not enrolled,
#     so `limine-enroll-config` is run afterwards.
# limine-entry-tool only rewrites the OS entries under its machine-id heading, so the
# block survives kernel updates the same way `timeout:` and `default_entry:` do.
# Re-running is idempotent: an existing block is replaced, not duplicated.

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "${ERROR} Failed to change directory to $PARENT_DIR"; exit 1; }

if ! source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_limine.log"
THEME="assets/limine/theme.conf"
WALL="assets/limine/limine-wallpaper.png"
MARK_START='# --- my_archinstaller Limine theme'
MARK_END='# --- end theme ---'

printf "\n%s - Theming the ${SKY_BLUE}Limine boot menu${RESET} \n" "${NOTE}"

# Find limine.conf on whatever the ESP is mounted as. Every /boot access goes through
# sudo: the ESP is routinely mounted root-only (CachyOS: fmask=0077).
CONF=""
for c in /boot/limine.conf /efi/limine.conf /boot/efi/limine.conf /boot/limine/limine.conf /efi/limine/limine.conf; do
  if sudo test -f "$c"; then CONF="$c"; break; fi
done
if [ -z "$CONF" ]; then
  echo "${NOTE} No limine.conf found - Limine is not the bootloader here. Nothing to do." | tee -a "$LOG"
  exit 0
fi
ESP_DIR="$(dirname "$CONF")"
[ -f "$THEME" ] && [ -f "$WALL" ] || { echo "${ERROR} $THEME or $WALL missing from the repo." | tee -a "$LOG"; exit 1; }
echo "${INFO} Limine config: $CONF" | tee -a "$LOG"

# 1. Backup, once. `cp -n` keeps the very first pre-theme copy on re-runs.
sudo cp -n "$CONF" "$CONF.pre-theme"
echo "${OK} Backup kept at $CONF.pre-theme" | tee -a "$LOG"

# 2. Wallpaper next to the config. theme.conf references it as boot():/limine-wallpaper.png,
#    i.e. relative to the partition Limine booted from, so the mount point does not matter.
sudo cp "$WALL" "$ESP_DIR/limine-wallpaper.png"
echo "${OK} Wallpaper copied to $ESP_DIR/limine-wallpaper.png ($(stat -c %s "$WALL") bytes)" | tee -a "$LOG"

# Enrollment on but the enroll tool missing would leave a config Limine refuses at
# boot - decide that BEFORE touching the file.
ENROLL=no
if grep -qE '^\s*ENABLE_ENROLL_LIMINE_CONFIG\s*=\s*"?yes"?' /etc/default/limine 2>/dev/null; then
  if command -v limine-enroll-config &>/dev/null; then
    ENROLL=yes
  else
    echo "${ERROR} ENABLE_ENROLL_LIMINE_CONFIG=yes but limine-enroll-config is not installed - not editing $CONF." | tee -a "$LOG"
    exit 1
  fi
fi

# 3. Rewrite: theme block on top (replacing an existing one), `timeout: no`, rest untouched.
TMP="$(mktemp)"
sudo cat "$CONF" > "$TMP.orig"
python3 - "$TMP.orig" "$THEME" "$TMP" "$MARK_START" "$MARK_END" <<'EOF'
import sys
orig, theme, out, ms, me = sys.argv[1:6]
cur = open(orig, newline='').read(); block = open(theme).read().rstrip('\n') + '\n\n'
nl = '\r\n' if '\r\n' in cur else '\n'
cur = cur.replace('\r\n', '\n')
if ms in cur and me in cur:
    a = cur.index(ms); b = cur.index(me) + len(me) + 1
    rest = cur[b:].lstrip('\n')
else:
    rest = cur
lines = rest.split('\n'); seen = False
for i, l in enumerate(lines):
    if l.startswith('timeout:'):
        lines[i] = 'timeout: no'; seen = True; break
if not seen:
    lines.insert(0, 'timeout: no')
open(out, 'w', newline='').write((block + '\n'.join(lines)).replace('\n', nl))
EOF

# 4. Safety check: everything from the first OS entry ("/" at column 0) down must be identical.
entries() { awk '/^\//{f=1} f' "$1"; }
if ! diff -q <(entries "$TMP.orig") <(entries "$TMP") >/dev/null; then
  echo "${ERROR} The OS entries would change - refusing to write $CONF. Diff:" | tee -a "$LOG"
  diff <(entries "$TMP.orig") <(entries "$TMP") | head -20 | tee -a "$LOG"
  rm -f "$TMP" "$TMP.orig"; exit 1
fi
sudo cp "$TMP" "$CONF"; sudo sync
# $TMP.orig is THIS run's pre-image and stays until enrollment is settled: the
# .pre-theme file is the first-ever backup and may predate kernel updates.
rm -f "$TMP"
echo "${OK} Theme block written, timeout set to 'no' (menu waits for a choice)." | tee -a "$LOG"

# 5. Enrolled config? Then the new hash must be enrolled or Limine will refuse the file.
if [ "$ENROLL" = yes ]; then
  echo "${NOTE} Config enrollment is enabled - re-enrolling the new limine.conf hash..." | tee -a "$LOG"
  if sudo limine-enroll-config >> "$LOG" 2>&1; then
    echo "${OK} Config hash enrolled." | tee -a "$LOG"
  else
    echo "${ERROR} limine-enroll-config failed. Restoring the config from before this run so the machine still boots." | tee -a "$LOG"
    sudo cp "$TMP.orig" "$CONF"; sudo sync; rm -f "$TMP.orig"; exit 1
  fi
fi
rm -f "$TMP.orig"

sudo grep -qE '^wallpaper: boot\(\):/limine-wallpaper.png' "$CONF" && sudo grep -qE '^timeout: no' "$CONF" \
  && echo "${OK} Limine menu themed. Revert any time with: sudo cp $CONF.pre-theme $CONF" | tee -a "$LOG"

printf "\n%.0s" {1..1}
