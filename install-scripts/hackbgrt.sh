#!/bin/bash
# HackBGRT - the repo logo on Windows' boot screen too, on a Limine dual boot.
#
# Windows does not draw a logo of its own choosing at boot: it redraws the
# firmware's (the ACPI BGRT image), but only when the firmware says it is still
# on screen. Started through Limine, it is not - Limine's menu was drawn over it -
# so Windows falls back to its own logo. HackBGRT (github.com/Metabolix/HackBGRT,
# MIT) is a small EFI program that runs right before Windows' boot manager and
# hands it a BGRT with our picture. Windows then draws that, pixel for pixel, at
# the offsets given, with its spinner underneath.
#
# What this does, on a machine whose limine.conf has a Windows entry:
#   - downloads the HackBGRT release pinned below and checks its sha256;
#   - renders splash.bmp: the Plymouth watermark (icons/gopnik-watermark-*.png,
#     the cut plymouth.sh would pick for this panel) at the place the soviet
#     Plymouth theme draws it - centred, 5 % from the top - on a black image the
#     size of the panel. Full screen on purpose, so HackBGRT's own positioning
#     has nothing to round;
#   - copies loader.efi (HackBGRT's bootx64.efi), config.txt and splash.bmp to
#     EFI/HackBGRT/ on the partition Windows' boot manager is on (boot=MS finds
#     \EFI\Microsoft\Boot\bootmgfw.efi on its own partition);
#   - points the Windows entry's path at EFI/HackBGRT/loader.efi, keeping
#     limine.conf as limine.conf.pre-hackbgrt. Windows' own files are not touched,
#     and the firmware boot menu's "Windows Boot Manager" still starts Windows
#     without it.
#
# config.txt sets the panel's resolution explicitly. "Current" (-1x-1) is wrong
# behind Limine: Limine leaves the screen in a lower mode for its menu, and
# HackBGRT crops the picture to the mode it finds - on the 2560x1440 desktop
# that left a corner of it, with no recognisable part of the girl in it.
#
# Not with Secure Boot on: HackBGRT then needs shim and a key enrolled by hand
# at the next boot (its shim.md), which no script can do. Re-running replaces
# the files and finds the entry already pointing at HackBGRT.

HACKBGRT_VERSION="2.6.0"
HACKBGRT_URL="https://github.com/Metabolix/HackBGRT/releases/download/v${HACKBGRT_VERSION}/HackBGRT-${HACKBGRT_VERSION}.zip"
HACKBGRT_SHA256="6204911d777ac03e514b90126568ef6faa1d477779b31c536b142dba92f4a2c0"
WATERMARK_1080="icons/gopnik-watermark-1080p.png"   # 468x620
WATERMARK_1440="icons/gopnik-watermark-1440p.png"   # 649x860, the fallback
WATERMARK_2160="icons/gopnik-watermark-2160p.png"   # 1011x1340

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "[ERROR] Failed to change directory to $PARENT_DIR"; exit 1; }

if ! source "$SCRIPT_DIR/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_hackbgrt.log"

printf "\n%s - Putting the repo logo on ${SKY_BLUE}Windows' boot screen${RESET} (HackBGRT) \n" "${NOTE}"

HB_TMP="$(mktemp -d)"
HB_MNT=""
cleanup() {
  if [ -n "$HB_MNT" ]; then sudo umount "$HB_MNT" 2>/dev/null || true; rmdir "$HB_MNT" 2>/dev/null || true; fi
  rm -rf "$HB_TMP"
}
trap cleanup EXIT

fail() {
  echo "${ERROR} $1" | tee -a "$LOG"
  record_package_failure "hackbgrt"
  exit 1
}

# 1. Preconditions: Limine with a Windows entry, Secure Boot off.
CONF=$(find_limine_conf) || { echo "${NOTE} No limine.conf here - HackBGRT is only wired through Limine. Nothing to do." | tee -a "$LOG"; exit 0; }
# Secure Boot: the 5th byte of the SecureBoot variable (the first 4 are its attributes).
_sb=$(od -An -t u1 -j4 -N1 /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c 2>/dev/null | tr -d ' ' || true)
if [ "$_sb" = 1 ]; then
  echo "${WARN} Secure Boot is on. HackBGRT then has to go through shim with a key enrolled by hand at boot (see its shim.md) - not done by this script. Skipping." | tee -a "$LOG"
  exit 0
fi

# The Windows entries: a path/image_path line ending in Microsoft's boot manager,
# or in HackBGRT's loader from an earlier run. Prints "<line no>\t<prefix>\t<tail>".
HB_PY=$(cat <<'PY'
import re, sys
mode, path = sys.argv[1], sys.argv[2]
raw = open(path, newline='').read()
nl = '\r\n' if '\r\n' in raw else '\n'
lines = raw.replace('\r\n', '\n').split('\n')
PAT = re.compile(r'^(\s*(?:image_path|path)\s*:\s*)(\S+?\):)(/EFI/(?:Microsoft/Boot/bootmgfw|HackBGRT/loader)\.efi)(\s*)$', re.I)
hits = [(i, PAT.match(l)) for i, l in enumerate(lines)]
hits = [(i, m) for i, m in hits if m]
if mode == 'list':
    for i, m in hits:
        print(f'{i}\t{m.group(2)}\t{m.group(3)}')
elif mode == 'point':
    out = sys.argv[3]
    for i, m in hits:
        lines[i] = m.group(1) + m.group(2) + '/EFI/HackBGRT/loader.efi' + m.group(4)
    open(out, 'w', newline='').write(nl.join(lines))
PY
)
sudo cat -- "$CONF" > "$HB_TMP/limine.conf" 2>>"$LOG" || fail "Could not read $CONF."
mapfile -t _entries < <(python3 -c "$HB_PY" list "$HB_TMP/limine.conf" 2>>"$LOG")
if [ ${#_entries[@]} -eq 0 ]; then
  echo "${NOTE} $CONF has no Windows entry (a path to \\EFI\\Microsoft\\Boot\\bootmgfw.efi) - nothing to do." | tee -a "$LOG"
  exit 0
fi
# 2. The partition the entry boots from: guid(<partition or filesystem GUID>):,
#    fslabel(<label>):, boot(): (the partition limine.conf is on) or boot(<n>):
#    (partition n of that drive). hdd()/odd() number drives the way the
#    firmware does, which Linux cannot see - not resolved, and install.sh's
#    "auto" does not pick those entries either.
resolve_part() { # <prefix>, e.g. "guid(673C...):"
  local _p="$1" _guid _n _disk _part=""
  case "$_p" in
    guid\(*\):|uuid\(*\):)
      _guid=$(sed -E 's/^[a-z]+\(([^)]*)\):$/\1/' <<< "$_p" | tr '[:upper:]' '[:lower:]')
      _part=$(lsblk -rno PATH,PARTUUID | awk -v g="$_guid" 'tolower($2) == g { print $1; exit }')
      [ -n "$_part" ] || _part=$(lsblk -rno PATH,UUID | awk -v g="$_guid" 'tolower($2) == g { print $1; exit }')
      ;;
    fslabel\(*\):)
      _part=$(sudo findfs "LABEL=$(sed -E 's/^fslabel\((.*)\):$/\1/' <<< "$_p")" 2>/dev/null)
      ;;
    boot\(\):)
      _part=$(sudo findmnt -no SOURCE -T "$(dirname "$CONF")" 2>/dev/null)
      ;;
    boot\([0-9]*\):)
      _n=$(sed -E 's/^boot\(([0-9]+)\):$/\1/' <<< "$_p")
      _disk=$(lsblk -no PKNAME "$(sudo findmnt -no SOURCE -T "$(dirname "$CONF")" 2>/dev/null)" 2>/dev/null | head -1)
      [ -n "$_disk" ] && _part=$(lsblk -rno PATH,PARTN "/dev/$_disk" 2>/dev/null | awk -v n="$_n" '$2 == n { print $1; exit }')
      ;;
  esac
  [ -n "$_part" ] && readlink -f -- "$_part"
  return 0
}
# Every entry has to be on the same partition - compared as partitions, not as
# text: an entry limine-entry-tool added (boot():) and one the installer wrote
# (guid(...):) can name the same one.
_prefixes=$(printf '%s\n' "${_entries[@]}" | cut -f2 | sort -u)
WIN_PART=""
while IFS= read -r _p; do
  _part=$(resolve_part "$_p")
  [ -n "$_part" ] && [ -b "$_part" ] || fail "Could not find the partition behind '$_p' in $CONF."
  [ -z "$WIN_PART" ] || [ "$_part" = "$WIN_PART" ] \
    || fail "$CONF has Windows entries on more than one partition ($WIN_PART, $_part) - not guessing which to change."
  WIN_PART=$_part
done <<< "$_prefixes"
_prefix=$(paste -sd' ' <<< "$_prefixes")
echo "${INFO} Windows' boot manager is on $WIN_PART ($_prefix)." | tee -a "$LOG"

_mp=$(findmnt -no TARGET "$WIN_PART" 2>/dev/null | head -1)
if [ -z "$_mp" ]; then
  HB_MNT=$(mktemp -d)
  sudo mount "$WIN_PART" "$HB_MNT" 2>>"$LOG" || { rmdir "$HB_MNT"; HB_MNT=""; fail "Could not mount $WIN_PART."; }
  _mp="$HB_MNT"
fi
_ms_boot=$(sudo find "$_mp" -maxdepth 4 -ipath "$_mp/efi/microsoft/boot/bootmgfw.efi" 2>/dev/null | head -1)
[ -n "$_ms_boot" ] || fail "$WIN_PART has no EFI/Microsoft/Boot/bootmgfw.efi - HackBGRT's boot=MS would have nothing to start. Not changing anything."
# The EFI directory as it is spelled there (FAT is case-insensitive, but keep it tidy).
_efi_dir=$(dirname "$(dirname "$(dirname "$_ms_boot")")")

# 3. HackBGRT itself, pinned and checked.
echo "${NOTE} Downloading HackBGRT ${HACKBGRT_VERSION}..." | tee -a "$LOG"
curl -fsSL --retry 3 -o "$HB_TMP/hackbgrt.zip" "$HACKBGRT_URL" 2>>"$LOG" || fail "Could not download $HACKBGRT_URL."
_sum=$(sha256sum "$HB_TMP/hackbgrt.zip" | cut -d' ' -f1)
[ "$_sum" = "$HACKBGRT_SHA256" ] || fail "HackBGRT download has sha256 $_sum, expected $HACKBGRT_SHA256 - not using it."
mkdir -p "$HB_TMP/x"
bsdtar -xf "$HB_TMP/hackbgrt.zip" -C "$HB_TMP/x" "HackBGRT-${HACKBGRT_VERSION}/efi-signed/bootx64.efi" 2>>"$LOG" \
  || fail "Could not extract bootx64.efi from the HackBGRT zip."
cp "$HB_TMP/x/HackBGRT-${HACKBGRT_VERSION}/efi-signed/bootx64.efi" "$HB_TMP/loader.efi"

# 4. The picture, for the panel. The preferred (first) mode of the smallest
#    connected panel, as plymouth.sh picks its cut - and the same cut.
W=0; H=0
for _modes in /sys/class/drm/card*-*/modes; do
  [ -r "$_modes" ] || continue
  [ "$(cat "${_modes%/modes}/status" 2>/dev/null)" = connected ] || continue
  _m=$(head -1 "$_modes")
  _w=$(cut -d x -f1 <<< "$_m" | tr -cd '0-9'); _h=$(cut -d x -f2 <<< "$_m" | tr -cd '0-9')
  [ -n "$_w" ] && [ -n "$_h" ] || continue
  if [ "$H" -eq 0 ] || [ "$_h" -lt "$H" ]; then W=$_w; H=$_h; fi
done
if [ "$H" -eq 0 ]; then
  W=2560; H=1440
  echo "${WARN} No connected panel reported a mode - assuming ${W}x${H}. Re-run this script from the installed system if the logo is misplaced." | tee -a "$LOG"
fi
if   [ "$H" -ge 2160 ]; then WM="$WATERMARK_2160"
elif [ "$H" -ge 1440 ]; then WM="$WATERMARK_1440"
else                         WM="$WATERMARK_1080"
fi
_dims=$(magick identify -format '%w %h' "$WM" 2>>"$LOG" || true)
read -r _ww _wh <<< "$_dims"
[ -n "$_wh" ] || fail "Could not read $WM."
# The soviet Plymouth theme's placement: WatermarkHorizontalAlignment=.5,
# WatermarkVerticalAlignment=.05, i.e. (screen - image) * alignment.
_x=$(( (W - _ww) / 2 )); _y=$(( (H - _wh) * 5 / 100 ))
magick -size "${W}x${H}" xc:black \( "$WM" -background black -flatten \) -geometry "+${_x}+${_y}" -composite \
       -type TrueColor -define bmp:format=bmp3 -compress none "BMP3:$HB_TMP/splash.bmp" 2>>"$LOG" \
  || fail "Could not render splash.bmp."
echo "${INFO} Panel ${W}x${H}: $(basename "$WM") at +${_x}+${_y}, as Plymouth draws it." | tee -a "$LOG"

cat > "$HB_TMP/config.txt" <<EOF
# HackBGRT for Windows, written by my_archinstaller (install-scripts/hackbgrt.sh).
# Limine's Windows entry starts \\EFI\\HackBGRT\\loader.efi, which swaps the boot
# logo Windows draws for splash.bmp and then starts Windows.
# splash.bmp is a full ${W}x${H} picture (the Plymouth watermark at its Plymouth
# size and place), so x/y only centre it.

# Boot loader path. MS = either backup or original Windows boot loader.
boot=MS

image= x=.5 y=.5 path=splash.bmp

# The panel's own mode, which splash.bmp is drawn for. Not -1x-1 ("current"):
# Limine leaves the screen in a lower mode for its menu, and HackBGRT then crops
# the picture to that mode - only a corner of it shows.
resolution=${W}x${H}

log=1
debug=0
EOF

# 5. Files onto the partition, checked.
_dest="$_efi_dir/HackBGRT"
sudo mkdir -p "$_dest" 2>>"$LOG" || fail "Could not create $_dest."
for _f in loader.efi config.txt splash.bmp; do
  sudo cp "$HB_TMP/$_f" "$_dest/$_f" 2>>"$LOG" && sudo cmp -s "$HB_TMP/$_f" "$_dest/$_f" \
    || fail "Could not write $_dest/$_f."
done
sudo sync
echo "${OK} HackBGRT ${HACKBGRT_VERSION}, its config and the splash are in $WIN_PART:/EFI/HackBGRT/." | tee -a "$LOG"

# 6. The Limine entry. Only the path lines of the Windows entries change.
python3 -c "$HB_PY" point "$HB_TMP/limine.conf" "$HB_TMP/limine.new" 2>>"$LOG" || fail "Could not rewrite the Windows entry."
if cmp -s "$HB_TMP/limine.conf" "$HB_TMP/limine.new"; then
  echo "${OK} The Windows entry in $CONF already starts HackBGRT." | tee -a "$LOG"
else
  # The entries not on HackBGRT yet - not all of them: with one converted by an
  # earlier run and a plain one added since (limine-entry-tool's
  # FIND_BOOTLOADERS can add a "Windows Boot Manager" entry), the count of all
  # entries never matched and a re-run stopped here instead of converting it.
  _to_point=$(printf '%s\n' "${_entries[@]}" | cut -f3 | grep -cvxF '/EFI/HackBGRT/loader.efi' || true)
  _changed=$(diff "$HB_TMP/limine.conf" "$HB_TMP/limine.new" | grep -c '^>' || true)
  [ "$_changed" -eq "$_to_point" ] || fail "The edit of $CONF would change $_changed lines, not the $_to_point Windows path line(s) still to point at HackBGRT - not writing it."
  # Enrolled config? Then the new hash has to be enrolled too (see limine.sh).
  _enroll=$(sed -nE 's/^\s*ENABLE_ENROLL_LIMINE_CONFIG\s*=\s*"?([A-Za-z]+)"?.*/\1/p' /etc/default/limine 2>/dev/null | tail -1 | tr '[:upper:]' '[:lower:]')
  if [ "$_enroll" = yes ] && ! command -v limine-enroll-config &>/dev/null; then
    fail "ENABLE_ENROLL_LIMINE_CONFIG=yes but limine-enroll-config is not installed - not editing $CONF."
  fi
  sudo cp -- "$CONF" "$CONF.pre-hackbgrt" 2>>"$LOG" && sudo cmp -s -- "$HB_TMP/limine.conf" "$CONF.pre-hackbgrt" \
    || fail "Could not back up $CONF."
  sudo cp -- "$HB_TMP/limine.new" "$CONF" 2>>"$LOG" && sudo cmp -s -- "$HB_TMP/limine.new" "$CONF" \
    || { sudo cp -- "$CONF.pre-hackbgrt" "$CONF" 2>>"$LOG"; fail "Could not write $CONF - put back."; }
  if [ "$_enroll" = yes ] && ! sudo limine-enroll-config >> "$LOG" 2>&1; then
    sudo cp -- "$CONF.pre-hackbgrt" "$CONF" 2>>"$LOG"
    fail "limine-enroll-config failed - $CONF was put back so the machine still boots."
  fi
  sudo sync
  echo "${OK} The Windows entry in $CONF now starts HackBGRT - the original is kept as $CONF.pre-hackbgrt." | tee -a "$LOG"
fi

clear_package_failure "hackbgrt"
echo "${NOTE} The firmware's own boot menu (Windows Boot Manager) still starts Windows without HackBGRT." | tee -a "$LOG"
printf "\n%.0s" {1..1}
