#!/bin/bash
# bios-logo/mod-bios-logo.sh - put LOGO.JPG into a motherboard's UEFI firmware image.
#
# Vendor-independent core. Works on any AMI Aptio V image (ASUS, Gigabyte, MSI, ASRock
# all ship it): the boot splash is an FFS file - almost always the EDK2 "Logo" file,
# GUID 7BB28B99-61BB-11D5-9A5D-0090273FC14D - holding a raw section with one bitmap.
# This script finds it, builds a same-format replacement from the repo logo that fits
# the volume's free space, replaces it with UEFIReplace, and verifies that nothing
# else in the image changed. The vendor-specific parts (where to download the file,
# what to name it, how to flash it) are in README.md and boards.conf.
#
#   mod-bios-logo.sh detect
#       Board, vendor, current BIOS version, the logo the firmware reports (BGRT),
#       and the boards.conf match if any.
#   mod-bios-logo.sh build --image <stock firmware file> [--name <OUT>] [--logo <img>]
#                          [--height <px>] [--colors <n>] [--out <dir>]
#       Produce <dir>/<OUT> (default: name from boards.conf, else the input name with
#       "-logo" appended) plus a verification report. Never flashes anything.
#   mod-bios-logo.sh usb --device /dev/sdX --file <modded firmware file>
#       Wipe the stick to one FAT32 partition on MBR with no label, copy the file to
#       the root, verify the checksum, unmount. Asks for confirmation; shows what is
#       on the stick first.
#
# Tools: uefitool 0.28 (AUR, provides `uefireplace`), UEFIExtract NE (downloaded from
# GitHub into ~/.cache/bios-logo if missing), ImageMagick, python3, curl, dosfstools.

set -eu

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HERE="$REPO_DIR/bios-logo"
LOGO_DEFAULT="$REPO_DIR/icons/LOGO.JPG"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/bios-logo"
EDK2_LOGO_GUID="7BB28B99-61BB-11D5-9A5D-0090273FC14D"

say()  { printf '\e[34m[INFO]\e[0m %s\n' "$*"; }
ok()   { printf '\e[32m[OK]\e[0m %s\n' "$*"; }
warn() { printf '\e[33m[WARN]\e[0m %s\n' "$*"; }
die()  { printf '\e[31m[ERROR]\e[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- board registry
board_name()   { cat /sys/class/dmi/id/board_name 2>/dev/null || true; }
board_vendor() { cat /sys/class/dmi/id/board_vendor 2>/dev/null || true; }
# registry_field <board_name> <field#>   (1 name, 2 vendor, 3 CAP name, 4 url, 5 spec, 6 status)
registry_field() {
  grep -v '^\s*#' "$HERE/boards.conf" | grep -v '^\s*$' | awk -F'|' -v b="$1" -v f="$2" '$1==b {print $f; exit}'
}

# ---------------------------------------------------------------- tools
ensure_tools() {
  for t in magick python3 curl unzip; do command -v "$t" >/dev/null || die "$t is missing (pacman -S imagemagick python unzip curl)"; done
  if ! command -v uefireplace >/dev/null; then
    local helper; helper=$(command -v yay || command -v paru || true)
    [ -n "$helper" ] || die "uefireplace missing and no AUR helper: install the 'uefitool' AUR package (0.28, old engine)"
    say "Installing uefitool (AUR) for uefireplace..."
    "$helper" -S --noconfirm --needed uefitool
  fi
  if ! command -v uefiextract >/dev/null && [ ! -x "$CACHE/uefiextract" ]; then
    say "Fetching UEFIExtract NE from GitHub releases..."
    mkdir -p "$CACHE"
    local url
    url=$(curl -fsSL https://api.github.com/repos/LongSoft/UEFITool/releases/latest \
      | python3 -c 'import json,sys,re
for a in json.load(sys.stdin)["assets"]:
    if re.match(r"UEFIExtract_NE_.*x64_linux\.zip$", a["name"]): print(a["browser_download_url"]); break')
    [ -n "$url" ] || die "could not find a UEFIExtract NE linux asset on GitHub"
    curl -fsSL -o "$CACHE/uefiextract.zip" "$url"
    unzip -o -q "$CACHE/uefiextract.zip" -d "$CACHE"
    chmod +x "$CACHE/uefiextract"
  fi
  UEFIEXTRACT=$(command -v uefiextract || echo "$CACHE/uefiextract")
  ok "tools: $(command -v uefireplace), $UEFIEXTRACT, $(command -v magick)"
}

# ---------------------------------------------------------------- detect
cmd_detect() {
  local name vendor ver date
  name=$(board_name); vendor=$(board_vendor)
  ver=$(cat /sys/class/dmi/id/bios_version 2>/dev/null); date=$(cat /sys/class/dmi/id/bios_date 2>/dev/null)
  echo "Board:        $vendor $name"
  echo "BIOS:         $ver ($date)"
  if [ -r /sys/firmware/acpi/bgrt/image ]; then
    echo "BGRT logo:    $(file -b - < /sys/firmware/acpi/bgrt/image | cut -d, -f1-3)  (what the firmware shows now; it may be scaled from the stored image)"
  else
    echo "BGRT logo:    not exposed (no firmware logo shown, or Boot Logo Display disabled)"
  fi
  if [ -n "$(registry_field "$name" 3)" ]; then
    echo "boards.conf:  known board"
    echo "  flash file: $(registry_field "$name" 3)"
    echo "  download:   $(registry_field "$name" 4)"
    echo "  logo spec:  $(registry_field "$name" 5)"
    echo "  status:     $(registry_field "$name" 6)"
  else
    echo "boards.conf:  no entry - read README.md 'New board' and add one once the flash worked"
  fi
}

# ---------------------------------------------------------------- build
cmd_build() {
  local image="" name="" logo="$LOGO_DEFAULT" height="" colors="128" out=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --image)  image="$2"; shift 2 ;;
      --name)   name="$2"; shift 2 ;;
      --logo)   logo="$2"; shift 2 ;;
      --height) height="$2"; shift 2 ;;
      --colors) colors="$2"; shift 2 ;;
      --out)    out="$2"; shift 2 ;;
      *) die "unknown option $1" ;;
    esac
  done
  [ -f "$image" ] || die "--image <stock firmware file> is required (the .CAP / .ROM / .Fxx you downloaded, unzipped)"
  [ -f "$logo" ]  || die "logo not found: $logo"
  ensure_tools

  local bname; bname=$(board_name)
  [ -n "$name" ] || name=$(registry_field "$bname" 3)
  [ -n "$name" ] || name="$(basename "${image%.*}")-logo.${image##*.}"
  [ -n "$out" ]  || out="$HOME/Downloads/bios-mod-$(echo "${bname:-unknown-board}" | tr ' /' '--')"
  mkdir -p "$out/stock" "$out/modded"
  WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
  cp "$image" "$WORK/stock.bin"

  # 1. Parse the image
  say "Parsing $(basename "$image") ($(stat -c %s "$image") bytes)..."
  "$UEFIEXTRACT" "$WORK/stock.bin" report >/dev/null 2>&1 || die "UEFIExtract could not parse this image. Not an AMI/EDK2 volume? Some vendors wrap firmware in an installer; extract the raw image first."
  local report="$WORK/stock.bin.report.txt"

  # 2. Find the logo file: standard GUID first, then anything named like a logo
  local fline
  fline=$(grep -i "$EDK2_LOGO_GUID" "$report" | grep -E '^ ?File' | head -1 || true)
  [ -n "$fline" ] || fline=$(grep -E '^ ?File' "$report" | grep -iE '\| *(Logo|Splash|BootLogo|OemLogo)[A-Za-z0-9_.]*\s*$' | head -1 || true)
  [ -n "$fline" ] || die "no Logo file found in the report. Open $(basename "$image") in the uefitool GUI, search (Ctrl+F, Text) for 'logo' or the BMP/JPEG magic, and pass the file's GUID by editing EDK2_LOGO_GUID in this script."
  local guid; guid=$(echo "$fline" | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1)
  local fsize_hex; fsize_hex=$(echo "$fline" | awk -F'|' '{gsub(/ /,"",$4); print $4}')
  say "Logo file: GUID $guid, $(( 16#$fsize_hex )) bytes on flash  ($(echo "$fline" | awk -F'|' '{print $NF}' | xargs))"

  # 3. Its raw section: type, compression, and the bitmap inside
  local lineno; lineno=$(grep -n -F "$fline" "$report" | head -1 | cut -d: -f1)
  local block; block=$(tail -n +"$((lineno+1))" "$report" | awk '/^ ?File|^ ?Free space|^ ?Volume/ {exit} {print}')
  local compressed="no"; [[ "$block" == *"GUID defined"* || "$block" == *Compressed* ]] && compressed="yes"
  # Free space of THIS volume only: stop at the next Volume line, otherwise a fully
  # packed volume would borrow the next volume's free space and the size check lies.
  local free_hex; free_hex=$(tail -n +"$((lineno+1))" "$report" | awk -F'|' '/^ ?Volume/{exit} /^ ?Free space/{gsub(/ /,"",$4); print $4; exit}')
  # The enclosing volume (last Volume line above the file with a real base): the
  # modified bytes must all fall inside it.
  local vol_base_hex vol_size_hex
  read -r vol_base_hex vol_size_hex < <(head -n "$lineno" "$report" | awk -F'|' '/^ ?Volume/ {gsub(/ /,"",$3); gsub(/ /,"",$4); if ($3!="N/A") {b=$3; s=$4}} END{print b, s}')
  [ -n "$vol_base_hex" ] || die "could not determine the volume that holds the logo file"
  local free=$(( 16#${free_hex:-0} )); local budget=$(( free + 16#$fsize_hex ))
  say "Section is $( [ $compressed = yes ] && echo 'compressed (LZMA/Tiano) - the replacement must compress small' || echo 'uncompressed - the replacement must be no larger than the original')."
  say "Room in the volume: $free bytes free + $(( 16#$fsize_hex )) currently used = budget $budget bytes"

  rm -rf "$WORK/orig"; "$UEFIEXTRACT" "$WORK/stock.bin" "$guid" -t 19 -m body -o "$WORK/orig" >/dev/null 2>&1 || true
  local orig; orig=$(find "$WORK/orig" -type f -size +1k 2>/dev/null | xargs -r ls -S | head -1)
  [ -n "$orig" ] || die "could not extract a raw section (type 0x19) from the Logo file"
  local kind w h bpp
  read -r kind w h bpp < <(python3 - "$orig" <<'EOF'
import struct,sys
d=open(sys.argv[1],'rb').read()
if d[:2]==b'BM':
    w,h=struct.unpack_from('<ii',d,18); bpp,=struct.unpack_from('<H',d,28); print("BMP",w,abs(h),bpp)
elif d[:3]==b'\xff\xd8\xff':
    i=2; found=False
    while i+9<=len(d):
        m,l=struct.unpack_from('>HH',d,i)
        if m in (0xFFC0,0xFFC1,0xFFC2): h,w=struct.unpack_from('>HH',d,i+5); print("JPEG",w,h,24); found=True; break
        i+=2+l
    if not found: print("UNKNOWN",0,0,0)
elif d[:8]==b'\x89PNG\r\n\x1a\n':
    w,h=struct.unpack_from('>II',d,16); print("PNG",w,h,24)
else: print("UNKNOWN",0,0,0)
EOF
)
  [ "$kind" != UNKNOWN ] || die "the raw section is not BMP/JPEG/PNG - inspect $orig by hand"
  cp "$orig" "$out/stock/original-logo.${kind,,}"
  say "Stored logo: $kind ${w}x${h} ${bpp}-bit, $(stat -c %s "$orig") bytes  (saved as stock/original-logo.${kind,,})"

  # 4. Build a same-format replacement that fits
  [ -n "$height" ] || height=$(( h * 8 / 10 ))
  local new="$WORK/new.${kind,,}"
  build_image() {  # $1 = colours ("full" for none)
    local q=(); [ "$1" != full ] && q=(-dither None -colors "$1")
    case "$kind" in
      BMP)
        local depth=(-type TrueColor); [ "$bpp" = 8 ] && depth=(-type Palette -colors 256 -depth 8)
        magick "$logo" -resize "x$height" -background black -gravity center -extent "${w}x${h}" "${q[@]}" "${depth[@]}" \
               -define bmp:format=bmp3 -compress none "BMP3:$new" ;;
      JPEG) magick "$logo" -resize "x$height" -background black -gravity center -extent "${w}x${h}" -quality 85 "JPEG:$new" ;;
      PNG)  magick "$logo" -resize "x$height" -background black -gravity center -extent "${w}x${h}" "${q[@]}" "PNG24:$new" ;;
    esac
  }
  measure() {  # predicted on-flash size
    if [ $compressed = yes ]; then python3 -c 'import lzma,sys; print(len(lzma.compress(open(sys.argv[1],"rb").read(),format=lzma.FORMAT_ALONE,preset=9)))' "$new"
    else stat -c %s "$new"; fi
  }
  local size
  for c in "$colors" 64 32 16; do
    build_image "$c"; size=$(measure)
    say "candidate with $c colours -> ~$size bytes on flash (limit $(( budget * 8 / 10 )))"
    [ "$size" -le $(( budget * 8 / 10 )) ] && break
  done
  [ "$size" -le $(( budget * 8 / 10 )) ] || die "even the 16-colour version does not fit; lower --height or crop the logo"
  if [ $compressed = no ] && [ "$(stat -c %s "$new")" -gt "$(stat -c %s "$orig")" ]; then
    die "uncompressed section and the new image ($(stat -c %s "$new")) is larger than the original ($(stat -c %s "$orig")) - same dimensions and depth should give the same size; check the depth"
  fi
  cp "$new" "$out/modded/new-logo.${kind,,}"
  magick "$new" "$out/modded/new-logo-preview.png"

  # 5. Replace
  say "Replacing the raw section with UEFIReplace..."
  if ! uefireplace "$WORK/stock.bin" "$guid" 19 "$new" -o "$WORK/modded.bin" > "$WORK/replace.log" 2>&1; then
    die "UEFIReplace failed: $(grep -vE 'parseSection: GUID defined section' "$WORK/replace.log" | tail -3 | tr '\n' ' ')"
  fi
  grep -vE 'parseSection: GUID defined section (with unknown processing method|can not be processed)' "$WORK/replace.log" || true
  [ -f "$WORK/modded.bin" ] || die "UEFIReplace produced no output"

  # 6. Verify
  say "Verifying..."
  "$UEFIEXTRACT" "$WORK/modded.bin" report >/dev/null 2>&1 || die "the modified image does not parse any more - do NOT flash it"
  rm -rf "$WORK/check"; "$UEFIEXTRACT" "$WORK/modded.bin" "$guid" -t 19 -m body -o "$WORK/check" >/dev/null 2>&1 || true
  local back; back=$(find "$WORK/check" -type f -size +1k | xargs -r ls -S | head -1)
  cmp -s "$back" "$new" || die "the logo read back from the modified image differs from what was inserted"
  # Every check here is fatal. A build that fails any of them is not delivered.
  python3 - "$WORK/stock.bin" "$WORK/modded.bin" "$report" "$WORK/modded.bin.report.txt" "$vol_base_hex" "$vol_size_hex" <<'EOF' || die "verification failed - do NOT flash"
import sys
a=open(sys.argv[1],'rb').read(); b=open(sys.argv[2],'rb').read()
vbase=int(sys.argv[5],16); vsize=int(sys.argv[6],16)
def fail(msg): print(f"\033[31m[ERROR]\033[0m {msg}"); sys.exit(1)
if len(a)!=len(b): fail(f"length changed: {len(a)} -> {len(b)}")
first=next((i for i in range(len(a)) if a[i]!=b[i]),None); last=next((i for i in range(len(a)-1,-1,-1) if a[i]!=b[i]),None)
if first is None: fail("output is identical to the input - nothing was replaced")
if a[:0x800]!=b[:0x800]: fail("the first 2 KiB (capsule header) changed")
if first < vbase or last >= vbase+vsize: fail(f"bytes changed outside the logo's volume: {first:#x}-{last:#x} vs volume {vbase:#x}-{vbase+vsize:#x}")
ra=open(sys.argv[3]).read().splitlines(); rb=open(sys.argv[4]).read().splitlines()
if len(ra)!=len(rb): fail(f"tree changed: {len(ra)} vs {len(rb)} items")
names=lambda L:[ '|'.join(x.split('|')[i] for i in (0,1) if i<len(x.split('|'))) for x in L]
if names(ra)!=names(rb): fail("item types changed")
print(f"\033[32m[OK]\033[0m same length ({len(a)} bytes); differences confined to {first:#x}-{last:#x} ({last-first+1} bytes) inside volume {vbase:#x}-{vbase+vsize:#x}; header identical; parse tree identical ({len(ra)} items)")
EOF

  # 7. Deliver
  cp "$WORK/modded.bin" "$out/modded/$name"
  cp "$image" "$out/stock/$name"
  (cd "$out" && sha256sum "modded/$name" "stock/$name" > SHA256SUMS)
  cat > "$out/README.txt" <<EOF
Built $(date +%F) by bios-logo/mod-bios-logo.sh on ${bname:-unknown board}
modded/$name  - firmware with the repo logo (Logo file $guid, ${kind} ${w}x${h} ${bpp}-bit)
stock/$name   - untouched vendor file = the recovery file. Same name on purpose: the
                flasher wants exactly this name, and a stick can only hold one of them.
Flash and recovery procedure: bios-logo/README.md in the repo.
EOF
  echo
  ok "modified firmware: $out/modded/$name"
  ok "recovery copy:     $out/stock/$name"
  ok "preview:           $out/modded/new-logo-preview.png"
  echo "Next: bios-logo/mod-bios-logo.sh usb --device /dev/sdX --file \"$out/modded/$name\""
}

# ---------------------------------------------------------------- usb
cmd_usb() {
  local dev="" file=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --device) dev="$2"; shift 2 ;;
      --file)   file="$2"; shift 2 ;;
      *) die "unknown option $1" ;;
    esac
  done
  [ -b "$dev" ] || die "--device /dev/sdX is required"
  [ -f "$file" ] || die "--file <modded firmware> is required"
  dev=$(readlink -f "$dev")   # /dev/disk/by-*/... symlinks resolve to the real node
  [ "$(lsblk -dno TYPE "$dev")" = disk ] || die "$dev is not a whole disk (lsblk TYPE=$(lsblk -dno TYPE "$dev")) - give /dev/sdX, not a partition"
  [ "$(lsblk -dno TRAN "$dev")" = usb ] || die "$dev is not a USB device - refusing"
  # Never the disk the system runs from, even if it is a USB SSD.
  if lsblk -no MOUNTPOINTS "$dev" | grep -qE '^(/|/boot|/boot/efi|/efi|/home|/var|/usr|\[SWAP\])$'; then
    die "$dev holds a system mount point - refusing"
  fi
  if lsblk -no TYPE "$dev" | grep -qE 'crypt|lvm|raid'; then
    die "$dev has LUKS/LVM/RAID members - refusing"
  fi
  command -v mkfs.vfat >/dev/null || die "mkfs.vfat missing (pacman -S dosfstools)"

  echo "This will ERASE $dev:"; lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS "$dev"
  for m in $(lsblk -no MOUNTPOINTS "$dev" | grep . ); do echo "--- $m:"; ls -la "$m" | head -10; done
  read -r -p "Type WIPE to continue: " ans; [ "$ans" = WIPE ] || die "aborted"

  sudo umount "$dev"?* 2>/dev/null || true
  sudo wipefs -a "$dev" >/dev/null
  printf 'label: dos\ntype=0c, bootable\n' | sudo sfdisk -q "$dev"
  sudo partprobe "$dev"; sleep 1
  local part; part=$(lsblk -lno NAME "$dev" | sed -n 2p); part="/dev/$part"
  sudo mkfs.vfat -F 32 "$part" >/dev/null              # no -n: FlashBack/Q-Flash want a blank label
  local m; m=$(mktemp -d); sudo mount "$part" "$m"
  trap 'sudo umount "$m" 2>/dev/null; rmdir "$m" 2>/dev/null' EXIT   # a failure below must not leave the stick mounted in /tmp
  sudo cp "$file" "$m/$(basename "$file")"; sync
  local a b; a=$(sha256sum "$file" | cut -c1-64); b=$(sudo sha256sum "$m/$(basename "$file")" | cut -c1-64)
  sudo umount "$m"; rmdir "$m"; sync
  [ "$a" = "$b" ] || die "checksum mismatch after copy - do not use this stick"
  ok "$dev: one FAT32 partition, no label, $(basename "$file") at the root, sha256 verified. Safe to remove."
  echo "Flash procedure for this vendor: bios-logo/README.md"
}

case "${1:-}" in
  detect) shift; cmd_detect "$@" ;;
  build)  shift; cmd_build "$@" ;;
  usb)    shift; cmd_usb "$@" ;;
  *) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
