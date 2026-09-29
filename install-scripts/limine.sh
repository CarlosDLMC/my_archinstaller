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
#   - if config enrollment is on (ENABLE_ENROLL_LIMINE_CONFIG=yes in any of the
#     files limine-entry-tool reads), Limine refuses a config whose hash it has not
#     enrolled, so `limine-enroll-config` is run afterwards - and if those files
#     disagree, nothing is written at all.
# limine-entry-tool only rewrites the OS entries under its machine-id heading, so the
# block survives kernel updates the same way `timeout:` and `default_entry:` do.
# Re-running is idempotent: an existing block is replaced, not duplicated.
#
# Undo it with `install-scripts/limine.sh --revert`. That takes the block out of
# the CURRENT limine.conf and puts the old `timeout:` line back (recorded inside
# the block when it was first written), under the same entry comparison and
# enrollment handling. It used to say "revert with sudo cp limine.conf.pre-theme
# limine.conf" - but that backup is the first-ever copy, and on CachyOS every
# kernel_path/module_path carries a BLAKE2 hash (ENABLE_VERIFICATION=yes in
# /etc/limine-entry-tool.conf). After the next kernel or initramfs update those
# hashes are stale, and Limine panics on every entry of the restored file
# (hash_mismatch_panic defaults to yes). The backup is still kept, as a record.

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "[ERROR] Failed to change directory to $PARENT_DIR"; exit 1; }

if ! source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

MODE=apply
case "${1:-}" in
  "")       ;;
  --revert) MODE=revert ;;
  *)        echo "Usage: $0 [--revert]"; exit 1 ;;
esac

LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_limine.log"
THEME="assets/limine/theme.conf"
WALL="assets/limine/limine-wallpaper.png"
MARK_START='# --- my_archinstaller Limine theme'
MARK_END='# --- end theme ---'
# The `timeout:` line from before the theme, kept as a comment inside the block
# (Limine skips comments) so --revert knows what to put back: the whole original
# line, "(no timeout line)" if there was none, or "(unknown)".
TIMEOUT_MARK='# limine.sh --revert restores:'

if [ "$MODE" = revert ]; then
  printf "\n%s - Removing the ${SKY_BLUE}Limine boot menu${RESET} theme \n" "${NOTE}"
else
  printf "\n%s - Theming the ${SKY_BLUE}Limine boot menu${RESET} \n" "${NOTE}"
fi

# Find limine.conf on whatever the ESP is mounted as - find_limine_conf in
# Global_functions.sh, the same search install.sh and the final check use. Every
# /boot access goes through sudo: the ESP is routinely mounted root-only
# (CachyOS: fmask=0077).
CONF="$(find_limine_conf || true)"
if [ -z "$CONF" ]; then
  echo "${NOTE} No limine.conf found - Limine is not the bootloader here. Nothing to do." | tee -a "$LOG"
  exit 0
fi
# theme.conf names the wallpaper as boot():/limine-wallpaper.png - the ROOT of the
# partition limine.conf is on. For /boot/limine.conf that is the conf's own
# directory, but for the limine/ and EFI/<dir>/ layouts the conf sits one or two
# levels down, and a wallpaper copied next to it is a file Limine never looks at
# (it skips a missing wallpaper silently, so the menu just came up bare). So it is
# the mount point of the partition holding the conf - see limine_partition_root.
ESP_DIR="$(limine_partition_root "$CONF")"
if [ "$MODE" = apply ]; then
  [ -f "$THEME" ] && [ -f "$WALL" ] || { echo "${ERROR} $THEME or $WALL missing from the repo." | tee -a "$LOG"; exit 1; }
fi
echo "${INFO} Limine config: $CONF" | tee -a "$LOG"

if [ "$MODE" = apply ]; then
  # 1. Backup, once. `cp -n` keeps the very first pre-theme copy on re-runs. A
  #    record of the original, not a restore point: see --revert at the top.
  sudo cp -n "$CONF" "$CONF.pre-theme"
  echo "${OK} Backup kept at $CONF.pre-theme (a record only - undo with --revert, not by copying it back)" | tee -a "$LOG"

  # 2. Wallpaper at the partition root. theme.conf references it as boot():/limine-wallpaper.png,
  #    i.e. relative to the partition Limine booted from, so the mount point does not matter.
  sudo cp "$WALL" "$ESP_DIR/limine-wallpaper.png"
  echo "${OK} Wallpaper copied to $ESP_DIR/limine-wallpaper.png ($(stat -c %s "$WALL") bytes)" | tee -a "$LOG"
fi

# Enrollment on but the enroll tool missing would leave a config Limine refuses at
# boot - decide that BEFORE touching the file. The same goes for --revert: taking
# the block out changes the file's hash just as much as putting it in.
#
# Only /etc/default/limine decides. limine-entry-tool does read
# /etc/limine-entry-tool.conf and /etc/limine-entry-tool.d/ for its other
# settings, but load_config (/usr/lib/limine/limine-common-functions) blanks
# ENABLE_ENROLL_LIMINE_CONFIG after them ("Do not use ENABLE_ENROLL_LIMINE_CONFIG
# in any random configs") and only then loads /etc/default/limine. An earlier
# version read all three and refused when they disagreed, which blocked the
# theme (and the reboot) over a value the tool itself ignores.
ENROLL=no
_enroll=""
if [ -f /etc/default/limine ]; then
  _enroll=$(sed -nE 's/^\s*ENABLE_ENROLL_LIMINE_CONFIG\s*=\s*"?([A-Za-z]+)"?.*/\1/p' /etc/default/limine 2>/dev/null | tail -1 | tr '[:upper:]' '[:lower:]')
fi
if [ -n "$_enroll" ]; then
  echo "${INFO} /etc/default/limine: ENABLE_ENROLL_LIMINE_CONFIG=$_enroll" | tee -a "$LOG"
fi
if [ "$_enroll" = yes ]; then
  if command -v limine-enroll-config &>/dev/null; then
    ENROLL=yes
  else
    echo "${ERROR} ENABLE_ENROLL_LIMINE_CONFIG=yes but limine-enroll-config is not installed - not editing $CONF." | tee -a "$LOG"
    exit 1
  fi
fi

# 3. Rewrite. apply: theme block on top (replacing an existing one), `timeout: no`,
#    rest untouched. revert: block out, the recorded timeout line back, rest untouched.
TMP="$(mktemp)"
sudo cat "$CONF" > "$TMP.orig"
# The pre-theme backup is read for one thing only: the timeout line of a file
# themed by a version of this script that did not record it in the block yet.
# Its entries (and their hashes) are never used.
: > "$TMP.pre"
if sudo test -f "$CONF.pre-theme"; then sudo cat "$CONF.pre-theme" > "$TMP.pre"; fi
# `|| _py=$?`, not `_py=$?` on the next line: Global_functions.sh sets -e, so a
# failing python3 (not installed yet, say) would end the script right here with
# nothing printed.
_py=0
_result=$(python3 - "$MODE" "$TMP.orig" "$THEME" "$TMP" "$MARK_START" "$MARK_END" "$TIMEOUT_MARK" "$TMP.pre" <<'EOF'
import re, sys
mode, orig, theme, out, ms, me, tm, pre = sys.argv[1:9]
cur = open(orig, newline='').read()
nl = '\r\n' if '\r\n' in cur else '\n'
cur = cur.replace('\r\n', '\n')

def timeout_line(text):
    for l in text.split('\n'):
        if l.startswith('timeout:'):
            return l.rstrip()
    return None

# Anything above an existing block is kept, not just what follows it: a
# default_entry: or remember_last_entry: that a tool or you put at the very top
# used to vanish on a re-run, and the entry comparison below starts at the
# first "/" line, so it could not notice.
old_block = ''
if ms in cur and me in cur:
    a = cur.index(ms); b = cur.index(me) + len(me) + 1
    old_block = cur[a:b]
    before = cur[:a].rstrip('\n')
    rest = ((before + '\n') if before else '') + cur[b:].lstrip('\n')
else:
    rest = cur

# The timeout line from before the theme went in. A re-run finds `timeout: no`
# in the file (this script put it there), so it must carry the recorded value
# forward rather than record its own work as the original.
m = re.search('^' + re.escape(tm) + r' *(.*?)[ \t]*$', old_block, re.M)
if m:
    saved = m.group(1)
elif old_block:
    # Themed by a version that did not record it. The pre-theme backup's timeout
    # line is still right even where its entries are stale - unless the backup
    # was itself taken from a themed file.
    p = open(pre, newline='').read().replace('\r\n', '\n')
    if p and ms not in p:
        saved = timeout_line(p) or '(no timeout line)'
    else:
        saved = '(unknown)'
else:
    saved = timeout_line(rest) or '(no timeout line)'

lines = rest.split('\n')
idx = next((i for i, l in enumerate(lines) if l.startswith('timeout:')), None)
if mode == 'apply':
    block = open(theme).read().rstrip('\n')
    block = block.replace(me, tm + ' ' + saved + '\n' + me, 1) + '\n\n'
    if idx is not None:
        lines[idx] = 'timeout: no'
    else:
        lines.insert(0, 'timeout: no')
    new = block + '\n'.join(lines)
    status = 'applied'
else:
    if not old_block:
        print('noblock'); sys.exit(0)
    cur_t = lines[idx].rstrip() if idx is not None else None
    # Only undo what this script did: a timeout that is no longer `no` was
    # changed by hand after the theme went in, and that is kept.
    if cur_t is not None and cur_t != 'timeout: no':
        status = 'kept:' + cur_t
    elif saved == '(no timeout line)':
        if idx is not None:
            del lines[idx]
        status = 'removed'
    elif saved.startswith('timeout:'):
        if idx is not None:
            lines[idx] = saved
        else:
            lines.insert(0, saved)
        status = 'restored:' + saved
    else:
        status = 'unknown'
    new = '\n'.join(lines)
open(out, 'w', newline='').write(new.replace('\n', nl))
print(status)
EOF
) || _py=$?
rm -f "$TMP.pre"
if [ "$_py" -ne 0 ] || [ -z "$_result" ]; then
  echo "${ERROR} Could not rewrite $CONF (python3 failed) - nothing was changed." | tee -a "$LOG"
  rm -f "$TMP" "$TMP.orig"; exit 1
fi
if [ "$_result" = noblock ]; then
  echo "${NOTE} $CONF has no my_archinstaller theme block - nothing to revert." | tee -a "$LOG"
  rm -f "$TMP" "$TMP.orig"; exit 0
fi

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
if [ "$MODE" = apply ]; then
  echo "${OK} Theme block written, timeout set to 'no' (menu waits for a choice)." | tee -a "$LOG"
else
  echo "${OK} Theme block removed from $CONF." | tee -a "$LOG"
fi

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

if [ "$MODE" = revert ]; then
  case "$_result" in
    restored:*) echo "${OK} Countdown back: ${_result#restored:}" | tee -a "$LOG" ;;
    removed)    echo "${OK} 'timeout: no' removed - there was no timeout line before, so Limine's default countdown applies again." | tee -a "$LOG" ;;
    kept:*)     echo "${NOTE} Left ${_result#kept:} alone - it was changed by hand after the theme went in." | tee -a "$LOG" ;;
    *)          echo "${WARN} The timeout from before the theme is not known, so 'timeout: no' is still set. Edit it in $CONF by hand (Limine's default is 5)." | tee -a "$LOG" ;;
  esac
  # The wallpaper goes too, unless something outside the block still names it.
  if ! sudo grep -q 'limine-wallpaper\.png' "$CONF"; then
    sudo rm -f "$ESP_DIR/limine-wallpaper.png" && echo "${OK} Removed $ESP_DIR/limine-wallpaper.png" | tee -a "$LOG"
  fi
  echo "${OK} Limine menu theme reverted. Apply it again with: $SCRIPT_DIR/limine.sh" | tee -a "$LOG"
  printf "\n%.0s" {1..1}
  exit 0
fi

sudo grep -qE '^wallpaper: boot\(\):/limine-wallpaper.png' "$CONF" && sudo grep -qE '^timeout: no' "$CONF" \
  && echo "${OK} Limine menu themed. Revert any time with: $SCRIPT_DIR/limine.sh --revert" | tee -a "$LOG"

printf "\n%.0s" {1..1}
