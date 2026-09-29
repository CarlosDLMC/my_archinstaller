#!/bin/bash
# Plymouth boot splash - the repo logo instead of the distro's.
#
# CachyOS ships plymouth with its "cachyos" theme, which keeps the motherboard's
# firmware logo (ACPI BGRT) as the background and stamps a CachyOS watermark at
# the bottom. This installs a theme that paints black and shows the repo's own
# boot logo from icons/ instead, with the stock spinner and the LUKS password
# prompt underneath. Disable "Boot Logo Display" in the BIOS and
# the vendor logo is gone for good, without touching the firmware.
#
# Only the theme is shipped. The spinner frames and the dialog artwork
# (entry.png, lock.png, keyboard.png...) are copied at install time from
# plymouth's own "spinner" theme, which every plymouth package carries, so the
# repo does not have to vendor GPL artwork and stays in step with the installed
# plymouth version.
#
# The shipped preset says plymouth="ON", so this runs on every machine, not only
# where a distro already set plymouth up (CachyOS - which is all "auto" covers).
# A theme on its own is never drawn: the initramfs has to start plymouth, and the
# kernel has to be given `splash`. Where either is missing, this script wires it
# (see "Boot wiring" below): the plymouth hook through a drop-in in
# /etc/mkinitcpio.conf.d, and `splash` on the kernel command line of whichever
# bootloader is there - systemd-boot, GRUB, Limine, or /etc/kernel/cmdline for
# UKIs. That makes this the second script that edits a bootloader config, after
# limine.sh. Each edit adds that one word and nothing else, is checked before it
# is written, and keeps the original as <file>.pre-plymouth.

THEME="soviet"
SRC_DIR="assets/plymouth/$THEME"
# The picture lives with the other logos in icons/, next to LOGO.JPG, so the
# firmware logo and the boot splash come from one place. Plymouth draws the
# watermark at its native pixel size - only the anchor in soviet.plymouth is a
# fraction of the screen - so there is one cut per panel height and the right
# one is installed as watermark.png, the name the two-step module reads. All
# three are downscales of icons/aisaka.icon (1920x1920), cut so the bottom
# edge clears the password prompt by ~35 px at that height.
WATERMARK_1080="icons/gopnik-watermark-1080p.png"   # 468x620
WATERMARK_1440="icons/gopnik-watermark-1440p.png"   # 649x860, the fallback
WATERMARK_2160="icons/gopnik-watermark-2160p.png"   # 1011x1340
DEST_DIR="/usr/share/plymouth/themes/$THEME"
SPINNER_DIR="/usr/share/plymouth/themes/spinner"

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "[ERROR] Failed to change directory to $PARENT_DIR"; exit 1; }

if ! source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_plymouth.log"

printf "\n%s - Installing the ${SKY_BLUE}Plymouth boot splash${RESET} theme \n" "${NOTE}"

install_package plymouth "$LOG"
if ! pacman -Qi plymouth &>/dev/null; then
  echo "${ERROR} plymouth did not install. Skipping the theme." | tee -a "$LOG"
  exit 1
fi

if [ ! -d "$SPINNER_DIR" ]; then
  echo "${ERROR} $SPINNER_DIR is missing - this plymouth build has no spinner theme to borrow artwork from." | tee -a "$LOG"
  exit 1
fi

# Which cut fits this machine. The preferred (first) mode of every connected
# DRM connector is the panel's native resolution, and it is readable from
# sysfs with no compositor running - this script runs in a TTY as often as not,
# so hyprctl/wlr-randr are no help. The *smallest* connected panel decides:
# plymouth paints the same image on every display, so a cut sized for the big
# screen of a mixed pair would land on the password prompt on the small one.
# Sets WATERMARK and SCREEN_H. It assigns rather than echoes: $(...) would run
# it in a subshell and SCREEN_H would never come back.
pick_watermark() {
  local modes conn h smallest=0
  for modes in /sys/class/drm/card*-*/modes; do
    [ -r "$modes" ] || continue
    conn="${modes%/modes}"
    [ "$(cat "$conn/status" 2>/dev/null)" = "connected" ] || continue
    h=$(head -1 "$modes" | cut -d x -f2 | tr -cd '0-9')
    [ -n "$h" ] || continue
    if [ "$smallest" -eq 0 ] || [ "$h" -lt "$smallest" ]; then smallest=$h; fi
  done
  SCREEN_H="$smallest"
  if   [ "$smallest" -ge 2160 ]; then WATERMARK="$WATERMARK_2160"
  elif [ "$smallest" -ge 1440 ]; then WATERMARK="$WATERMARK_1440"
  elif [ "$smallest" -gt 0 ];    then WATERMARK="$WATERMARK_1080"
  else                                WATERMARK="$WATERMARK_1440"
  fi
}

pick_watermark
if [ "$SCREEN_H" -eq 0 ]; then
  echo "${WARN} No connected DRM connector reported a mode - falling back to $(basename "$WATERMARK"). If the logo overlaps the password prompt, copy another icons/gopnik-watermark-*.png over $DEST_DIR/watermark.png by hand." | tee -a "$LOG"
elif [ "$SCREEN_H" -lt 1000 ]; then
  echo "${WARN} The smallest connected panel is only ${SCREEN_H} px tall - even the 620 px cut will crowd the password prompt. Re-render it shorter from icons/aisaka.icon if that bothers you." | tee -a "$LOG"
else
  echo "${NOTE} Smallest connected panel is ${SCREEN_H} px - using ${SKY_BLUE}$(basename "$WATERMARK")${RESET}." | tee -a "$LOG"
fi
# A 4K panel small enough to be HiDPI (plymouth's own guess: roughly >192 dpi)
# makes plymouth double everything, which halves the logical screen and makes
# the 1080p cut the right one. Override plymouth's guess on the kernel command
# line with plymouth.force-scale=1 if the 4K cut comes out twice the size.

# Theme files: ours on top of the spinner theme's frames and dialog artwork.
# -n on the spinner copy so our watermark.png is never replaced by theirs.
# Each copy's status is checked through PIPESTATUS: `cmd | tee` reports tee's,
# so a missing watermark used to pass silently, the theme was still selected,
# and the splash booted with no logo while the final check (which only reads the
# theme name) passed.
sudo mkdir -p "$DEST_DIR"
sudo cp "$SRC_DIR/$THEME.plymouth" "$DEST_DIR/" 2>&1 | tee -a "$LOG"
_cp_theme=${PIPESTATUS[0]}
sudo cp "$WATERMARK" "$DEST_DIR/watermark.png" 2>&1 | tee -a "$LOG"
_cp_mark=${PIPESTATUS[0]}
if [ "$_cp_theme" -ne 0 ] || [ "$_cp_mark" -ne 0 ]; then
  echo "${ERROR} Could not copy the theme files into $DEST_DIR - leaving the current splash theme selected. See $LOG" | tee -a "$LOG"
  record_package_failure "plymouth-theme-$THEME"
  exit 1
fi
# The theme files are in place: take back a failure an earlier run recorded
# (not a pacman package, so the final check cannot re-verify it itself).
clear_package_failure "plymouth-theme-$THEME"
sudo find "$SPINNER_DIR" -maxdepth 1 -name '*.png' ! -name 'watermark.png' \
  -exec cp -n {} "$DEST_DIR/" \; 2>&1 | tee -a "$LOG"
sudo chmod 644 "$DEST_DIR"/* 2>&1 | tee -a "$LOG"

# Set the theme (/etc/plymouth/plymouthd.conf), then regenerate every initramfs
# so the image that boots carries it. This is the slow step.
#
# Two steps, not `plymouth-set-default-theme -R`. -R runs plymouth-update-initrd
# and then ends in an unconditional `exit 0`, so a rebuild that failed (a full
# ESP, a hook error) still printed OK here, nothing reached
# INITRAMFS_FAILED_MANIFEST, the final check - which only reads the theme name -
# passed, and the preset rebooted into the old image with the distro splash.
# rebuild_initramfs (Global_functions.sh) picks the generator the same way
# plymouth-update-initrd does (limine-mkinitcpio on CachyOS+Limine, whose hook
# also refreshes the hashed boot entries; else mkinitcpio -P) and records a
# failure for the final check.
echo "${NOTE} Setting ${SKY_BLUE}$THEME${RESET} as the default theme..." | tee -a "$LOG"
if sudo plymouth-set-default-theme "$THEME" >> "$LOG" 2>&1; then
  echo "${OK} plymouth theme is now $(plymouth-set-default-theme)." | tee -a "$LOG"
else
  echo "${ERROR} plymouth-set-default-theme failed - see $LOG" | tee -a "$LOG"
  exit 1
fi

# ---------------------------------------------------------------- boot wiring
# Both parts come before the initramfs rebuild further down, because that
# rebuild is what carries them: the hook goes into the image, and
# limine-mkinitcpio (Limine's entry tool) and mkinitcpio's UKIs take the new
# command line from it. Everything is idempotent - a re-run finds the hook and
# the word in place and changes nothing.
PLY_TMP="$(mktemp -d)"
trap 'rm -rf "$PLY_TMP"' EXIT
_wiring_failed=false

# 1. The plymouth hook.
#
# A drop-in rather than a sed on /etc/mkinitcpio.conf. mkinitcpio joins the main
# file and every drop-in into one file and sources it as bash, so the drop-in
# can put plymouth into whatever HOOKS the files before it set - a multi-line
# array, or a HOOKS= in another drop-in, included. The place is the Arch wiki's:
# right after systemd (or udev), which also keeps it ahead of encrypt and
# sd-encrypt, so the LUKS prompt is drawn by the splash. "zz-" sorts last in
# mkinitcpio's own order (LC_ALL=C.UTF-8 sort -V) and in a shell glob, the way
# mkinitcpio_has_hook reads the drop-ins, so no other drop-in can undo it.
echo "${NOTE} Making sure the initramfs starts ${SKY_BLUE}plymouth${RESET}..." | tee -a "$LOG"
PLY_DROPIN="/etc/mkinitcpio.conf.d/zz-my_archinstaller-plymouth.conf"
PLY_HOOK_SNIPPET=$(cat <<'HOOK'
# Installed by my_archinstaller (install-scripts/plymouth.sh).
#
# Puts the plymouth hook right after systemd (or udev) in the HOOKS set before
# this point, which keeps it ahead of encrypt/sd-encrypt. It changes nothing
# when plymouth is already there. mkinitcpio sources its configuration as bash.
if [[ " ${HOOKS[*]} " != *" plymouth "* ]]; then
    read -ra _mai_in <<< "${HOOKS[*]}"
    _mai_out=()
    for _mai_h in "${_mai_in[@]}"; do
        _mai_out+=("$_mai_h")
        if [[ ( $_mai_h == systemd || $_mai_h == udev ) && " ${_mai_out[*]} " != *" plymouth "* ]]; then
            _mai_out+=(plymouth)
        fi
    done
    HOOKS=("${_mai_out[@]}")
    unset _mai_in _mai_out _mai_h
fi
HOOK
)
# The HOOKS a config file used on its own (mkinitcpio -c) ends up with.
conf_has_plymouth() {
  bash -c 'source "$1" 2>/dev/null; printf "%s\n" "${HOOKS[@]}"' _ "$1" 2>/dev/null | grep -qx plymouth
}
if command -v mkinitcpio &>/dev/null; then
  if mkinitcpio_has_hook plymouth; then
    echo "${OK} plymouth is already in the mkinitcpio HOOKS." | tee -a "$LOG"
  elif sudo mkdir -p "${PLY_DROPIN%/*}" \
       && printf '%s\n' "$PLY_HOOK_SNIPPET" | sudo tee "$PLY_DROPIN" >/dev/null \
       && mkinitcpio_has_hook plymouth; then
    echo "${OK} Added the plymouth hook with $PLY_DROPIN (right after systemd/udev)." | tee -a "$LOG"
  else
    # A drop-in that did not take would only mislead the next reader.
    sudo rm -f "$PLY_DROPIN" 2>>"$LOG" || true
    echo "${ERROR} Could not put plymouth into the mkinitcpio HOOKS (neither systemd nor udev is in them?). Add it after systemd or udev in /etc/mkinitcpio.conf by hand." | tee -a "$LOG"
    _wiring_failed=true
  fi

  # A preset that names a config file (ALL_config=, default_config=, ...) runs
  # mkinitcpio with -c, and -c skips the drop-ins - the case nvidia.sh handles
  # for MODULES. The same snippet goes at the end of each such file instead,
  # between markers so a re-run finds it.
  PLY_MARK="# --- my_archinstaller plymouth hook"
  custom_confs=$(sed -nE 's/^\s*[A-Za-z_]*config=["\x27]?([^"\x27 ]+)["\x27]?.*/\1/p' /etc/mkinitcpio.d/*.preset 2>/dev/null | sort -u)
  for _conf in $custom_confs; do
    if conf_has_plymouth "$_conf"; then
      echo "${OK} plymouth is already in the HOOKS of $_conf." | tee -a "$LOG"
    elif ! grep -qF "$PLY_MARK" "$_conf" 2>/dev/null \
         && sudo cp -n -- "$_conf" "$_conf.pre-plymouth" \
         && printf '\n%s (install-scripts/plymouth.sh) ---\n%s\n%s end ---\n' "$PLY_MARK" "$PLY_HOOK_SNIPPET" "$PLY_MARK" \
            | sudo tee -a "$_conf" >/dev/null \
         && conf_has_plymouth "$_conf"; then
      echo "${OK} Added the plymouth hook to $_conf (a preset uses it with -c, so drop-ins do not apply)." | tee -a "$LOG"
    else
      echo "${ERROR} Could not put plymouth into the HOOKS of $_conf - add it after systemd or udev there by hand." | tee -a "$LOG"
      _wiring_failed=true
    fi
  done
elif command -v dracut &>/dev/null; then
  echo "${NOTE} dracut builds the initramfs here, and it adds plymouth by itself once the package is installed." | tee -a "$LOG"
else
  echo "${ERROR} Neither mkinitcpio nor dracut builds the initramfs here, so nothing can start plymouth at boot." | tee -a "$LOG"
  _wiring_failed=true
fi

# 2. `splash` on the kernel command line.
#
# Every place a command line comes from gets it - one machine can have several
# (loader entries next to a UKI's /etc/kernel/cmdline). splash_py writes an
# edited copy, a separate check confirms that the only difference is "splash" on
# the lines that lacked it, and only then does the copy replace the file, whose
# original is kept once as <file>.pre-plymouth. `quiet` is left alone: hiding
# the kernel's messages is a choice about debugging, not about the splash.
echo "${NOTE} Making sure the kernel command line asks for the ${SKY_BLUE}splash${RESET}..." | tee -a "$LOG"
SPLASH_PY=$(cat <<'PY'
import re, sys

# "splash" as a word of the command line (plymouth also accepts splash=<x>).
def has_splash(value):
    return re.search(r'(?:^|\s)splash(?:=\S*)?(?=\s|$)', value) is not None

# The same word in a whole config line, where a quote, "=" or ":" can border it
# as well as whitespace (GRUB_CMDLINE_LINUX_DEFAULT="quiet splash").
def splash_in_line(line):
    return re.search(r'(?:^|[\s"\'=:])splash(?:=\S*)?(?=[\s"\']|$)', line) is not None

def load(path):
    text = open(path, newline='').read()
    nl = '\r\n' if '\r\n' in text else '\n'
    return text.replace('\r\n', '\n'), nl

def appended(value):
    return value.rstrip() + ' splash' if value.strip() else 'splash'

# systemd-boot Type #1 entry. Only entries that boot a Linux kernel: an "efi"
# entry (Windows, a firmware tool) does not take kernel options.
def edit_entry(lines):
    if not any(re.match(r'\s*linux\s', l) for l in lines):
        return 'skip'
    opts = [i for i, l in enumerate(lines) if re.match(r'\s*options(\s|$)', l)]
    if not opts:
        return 'nooptions'
    if any(has_splash(re.sub(r'^\s*options', '', lines[i], count=1)) for i in opts):
        return 'present'
    # systemd-boot joins all options lines, so the last one is as good as any.
    lines[opts[-1]] = lines[opts[-1]].rstrip() + ' splash'
    return 'added'

# limine.conf written by hand or by archinstall (not by limine-entry-tool). An
# entry starts at a line whose first character is "/"; only the ones with
# protocol: linux take a kernel command line (an efi entry's cmdline goes to
# the EFI program).
def edit_limine(lines):
    starts = [i for i, l in enumerate(lines) if re.match(r'\s*/', l)]
    seen = changed = False
    for n, s in enumerate(starts):
        body = range(s + 1, starts[n + 1] if n + 1 < len(starts) else len(lines))
        if not any(re.match(r'\s*protocol\s*:\s*linux\s*$', lines[i], re.I) for i in body):
            continue
        for i in body:
            m = re.match(r'^(\s*(?:kernel_cmdline|cmdline)\s*:)(.*)$', lines[i])
            if not m:
                continue
            seen = True
            if has_splash(m.group(2)):
                continue
            lines[i] = lines[i].rstrip() + ' splash' if m.group(2).strip() else m.group(1) + ' splash'
            changed = True
    return 'added' if changed else ('present' if seen else 'none')

# /etc/default/grub, which grub-mkconfig sources: the last assignment wins.
# GRUB_CMDLINE_LINUX_DEFAULT is the normal entries' line; the recovery entries
# are left without the splash.
def edit_grub(lines):
    idx = [i for i, l in enumerate(lines) if re.match(r'\s*GRUB_CMDLINE_LINUX_DEFAULT=', l)]
    if not idx:
        # Unset is empty, so setting it to just the word changes nothing else.
        at = len(lines) - 1 if lines and lines[-1] == '' else len(lines)
        lines.insert(at, 'GRUB_CMDLINE_LINUX_DEFAULT="splash"')
        return 'added'
    i = idx[-1]
    m = re.match(r'^(\s*GRUB_CMDLINE_LINUX_DEFAULT=)(?:"([^"]*)"|\'([^\']*)\'|([^\s"\'#]*))(\s*(?:#.*)?)$', lines[i])
    if not m:
        return 'unparsed'
    if m.group(2) is not None:
        quote, value = '"', m.group(2)
    elif m.group(3) is not None:
        quote, value = "'", m.group(3)
    elif m.group(4) == '':
        quote, value = '', ''
    else:
        return 'unparsed'   # an unquoted word: quoting it is more than adding one
    if has_splash(value):
        return 'present'
    lines[i] = m.group(1) + quote + appended(value) + quote + m.group(5)
    return 'added'

# /etc/kernel/cmdline: the whole file is the command line.
def edit_kcmdline(text):
    if has_splash(' '.join(text.split())):
        return 'present', text
    body = text.rstrip('\n')
    tail = text[len(body):] or '\n'
    return 'added', appended(body) + tail

# limine-entry-tool: KERNEL_CMDLINE[default] across its config files, in the
# order it reads them - `=` replaces, `+=` appends. <text> is /etc/default/limine
# (empty when missing), which it reads last.
def kernel_cmdline(text):
    for l in text.split('\n'):
        m = re.match(r'^\s*KERNEL_CMDLINE\[default\]\s*(\+?=)(.*)$', l)
        if m:
            v = m.group(2).strip()
            if len(v) >= 2 and v[0] == v[-1] and v[0] in '"\'':
                v = v[1:-1]
            yield m.group(1), v

def edit_limine_tool(text, earlier):
    eff, defined = '', False
    for t in earlier + [text]:
        for op, v in kernel_cmdline(t):
            defined = True
            eff = v if op == '=' else (eff + ' ' + v).strip()
    if has_splash(eff):
        return 'present', text
    if not defined:
        return 'undefined', text
    body = text if text == '' or text.endswith('\n') else text + '\n'
    return 'added', body + 'KERNEL_CMDLINE[default]+="splash"\n'

# The edited file may differ from the original only by "splash" added to lines
# that did not have it, or by one line that sets a missing variable to it.
def only_splash_added(old, new):
    o, n = old.split('\n'), new.split('\n')
    if len(n) == len(o) + 1:
        extra = ('splash', 'GRUB_CMDLINE_LINUX_DEFAULT="splash"', 'KERNEL_CMDLINE[default]+="splash"')
        return any(n[j] in extra and n[:j] + n[j + 1:] == o for j in range(len(n)))
    if len(n) != len(o):
        return False
    changed = 0
    for a, b in zip(o, n):
        if a == b:
            continue
        undone = set()
        for word in (' splash', 'splash'):
            k = b.find(word)
            while k != -1:
                undone.add((b[:k] + b[k + len(word):]).rstrip())
                k = b.find(word, k + 1)
        if a.rstrip() not in undone or not splash_in_line(b):
            return False
        changed += 1
    return changed > 0

if sys.argv[1] == 'edit':
    mode, src, dst = sys.argv[2:5]
    text, nl = load(src)
    if mode == 'kcmdline':
        status, out = edit_kcmdline(text)
    elif mode == 'limine-tool':
        status, out = edit_limine_tool(text, [load(p)[0] for p in sys.argv[5:]])
    else:
        lines = text.split('\n')
        status = {'entry': edit_entry, 'limine': edit_limine, 'grub': edit_grub}[mode](lines)
        out = '\n'.join(lines)
    if status == 'added':
        with open(dst, 'w', newline='') as f:
            f.write(out.replace('\n', nl))
    print(status)
elif sys.argv[1] == 'check':
    sys.exit(0 if only_splash_added(load(sys.argv[2])[0], load(sys.argv[3])[0]) else 1)
PY
)

# ensure_splash <mode> <file> [earlier limine-entry-tool configs...]
# Sets _sp to present, added or skip, or to the reason it could not: none,
# nooptions, unparsed, undefined, error or failed. <file> is read and written
# through sudo - the ESP is routinely mounted root-only. Always returns 0: this
# runs under Global_functions.sh's set -e.
ensure_splash() {
  local mode="$1" file="$2" existed=false st
  shift 2
  _sp=failed
  _sp_created=false
  : > "$PLY_TMP/old"
  rm -f "$PLY_TMP/new"
  if sudo test -e "$file"; then
    existed=true
    if ! sudo cat -- "$file" > "$PLY_TMP/old" 2>>"$LOG"; then
      return 0
    fi
  elif [ "$mode" != limine-tool ]; then
    # Only /etc/default/limine may be created; everything else must exist.
    return 0
  fi
  st=$(python3 -c "$SPLASH_PY" edit "$mode" "$PLY_TMP/old" "$PLY_TMP/new" "$@" 2>>"$LOG") || st=error
  if [ "$st" != added ]; then
    _sp="${st:-error}"
    return 0
  fi
  if ! python3 -c "$SPLASH_PY" check "$PLY_TMP/old" "$PLY_TMP/new" 2>>"$LOG"; then
    echo "${ERROR} The edit of $file would change more than adding 'splash' - not writing it." | tee -a "$LOG"
    return 0
  fi
  if [ "$existed" = true ] && ! sudo cp -n -- "$file" "$file.pre-plymouth" 2>>"$LOG"; then
    echo "${ERROR} Could not back up $file - not editing it." | tee -a "$LOG"
    return 0
  fi
  if sudo cp -- "$PLY_TMP/new" "$file" 2>>"$LOG" && sudo cmp -s -- "$PLY_TMP/new" "$file"; then
    _sp=added
    if [ "$existed" = false ]; then _sp_created=true; fi
  elif [ "$existed" = true ]; then
    sudo cp -- "$PLY_TMP/old" "$file" 2>>"$LOG" || true
  else
    sudo rm -f -- "$file" 2>>"$LOG" || true
  fi
  return 0
}

splash_sources=0
splash_bad=()
# report_splash <what> <status> [manual step]: prints the outcome and counts it.
report_splash() {
  local what="$1" st="$2" why
  case "$st" in
    skip) return 0 ;;
    present) echo "${OK} $what already has 'splash'." | tee -a "$LOG" ;;
    added)
      if [ "${_sp_created:-false}" = true ]; then
        echo "${OK} Created $what with 'splash' in it." | tee -a "$LOG"
      else
        echo "${OK} Added 'splash' to $what - the original is kept as $what.pre-plymouth." | tee -a "$LOG"
      fi
      ;;
    *)
      if [ -n "${3:-}" ]; then
        echo "${ERROR} Could not add 'splash' to $what. $3" | tee -a "$LOG"
      else
        case "$st" in
          nooptions) why="it boots Linux but has no options line" ;;
          unparsed)  why="its GRUB_CMDLINE_LINUX_DEFAULT line is not in a form this script edits" ;;
          none)      why="no Linux entry in it has a cmdline line" ;;
          *)         why="see $LOG" ;;
        esac
        echo "${ERROR} Could not add 'splash' to $what ($why). Add it to the kernel command line there by hand." | tee -a "$LOG"
      fi
      splash_bad+=("$what")
      ;;
  esac
  splash_sources=$((splash_sources + 1))
  return 0
}

# /etc/kernel/cmdline: what mkinitcpio builds a UKI's command line from, and
# kernel-install writes loader entries from. First, because limine-entry-tool
# below falls back to it.
if sudo test -f /etc/kernel/cmdline; then
  ensure_splash kcmdline /etc/kernel/cmdline
  report_splash /etc/kernel/cmdline "$_sp"
fi

# Limine.
_limine_tool_check=false
if _limine_conf=$(find_limine_conf); then
  if command -v limine-entry-tool &>/dev/null; then
    # limine-entry-tool (CachyOS, or limine-mkinitcpio-hook from the AUR) writes
    # the kernel entries from KERNEL_CMDLINE and rewrites them on every kernel
    # update, so the word goes there, not into limine.conf - as a `+=` line in
    # /etc/default/limine, the file its own docs recommend `+=` for. Only when
    # KERNEL_CMDLINE[default] is already set somewhere, though: a `+=` makes the
    # tool stop reading /etc/kernel/cmdline and /proc/cmdline, so on its own it
    # would leave a command line of just "splash", with no root= in it.
    _lt_earlier=()
    if [ -f /etc/limine-entry-tool.conf ]; then _lt_earlier+=(/etc/limine-entry-tool.conf); fi
    for _f in /etc/limine-entry-tool.d/*.conf; do
      if [ -f "$_f" ]; then _lt_earlier+=("$_f"); fi
    done
    ensure_splash limine-tool /etc/default/limine "${_lt_earlier[@]}"
    if [ "$_sp" = undefined ] && sudo test -f /etc/kernel/cmdline; then
      echo "${NOTE} limine-entry-tool takes the command line from /etc/kernel/cmdline here (above)." | tee -a "$LOG"
    elif [ "$_sp" = undefined ]; then
      report_splash "limine-entry-tool's KERNEL_CMDLINE" failed \
        "It takes the command line from /proc/cmdline here: copy that into KERNEL_CMDLINE[default] in /etc/default/limine with 'splash' added, then run: sudo limine-mkinitcpio"
    else
      report_splash /etc/default/limine "$_sp"
      if [ "$_sp" = added ]; then _limine_tool_check=true; fi
    fi
  else
    ensure_splash limine "$_limine_conf"
    report_splash "$_limine_conf" "$_sp"
  fi
fi

# systemd-boot: every entry that boots a Linux kernel, on the ESP or on an
# XBOOTLDR partition. archinstall writes them once and never again, so they are
# edited in place. Read on fd 3, so nothing in the loop can swallow the list.
_entry_dirs=" "
for _esp in /boot /efi /boot/efi; do
  _d="$_esp/loader/entries"
  if ! sudo test -d "$_d"; then continue; fi
  _real=$(sudo readlink -f -- "$_d" 2>/dev/null || echo "$_d")
  if [[ "$_entry_dirs" == *" $_real "* ]]; then continue; fi
  _entry_dirs+="$_real "
  while IFS= read -r -d '' _entry <&3; do
    ensure_splash entry "$_entry"
    report_splash "$_entry" "$_sp"
  done 3< <(sudo find "$_d" -maxdepth 1 -type f -name '*.conf' -print0 2>/dev/null)
done

# GRUB: GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub, then grub.cfg rebuilt
# from it - but only when this run changed the file, since grub-mkconfig would
# also apply anything else that is pending in it. grub-mkconfig writes
# grub.cfg.new and replaces grub.cfg only once that passes its syntax check.
if command -v grub-mkconfig &>/dev/null && [ -f /etc/default/grub ] && sudo test -f /boot/grub/grub.cfg; then
  ensure_splash grub /etc/default/grub
  _grub_cfg_splash() {
    sudo grep -qE '^[[:space:]]*linux[[:space:]].*[[:space:]]splash([=[:space:]]|$)' /boot/grub/grub.cfg
  }
  if [ "$_sp" = added ]; then
    cp "$PLY_TMP/old" "$PLY_TMP/grub.old"
    if ! sudo grub-mkconfig -o /boot/grub/grub.cfg >> "$LOG" 2>&1; then
      echo "${ERROR} grub-mkconfig failed - putting /etc/default/grub back; grub.cfg was left as it was." | tee -a "$LOG"
      sudo cp -- "$PLY_TMP/grub.old" /etc/default/grub 2>>"$LOG" || true
      _sp=failed
    elif ! _grub_cfg_splash; then
      echo "${ERROR} grub.cfg has no 'splash' after grub-mkconfig - does a file in /etc/default/grub.d set GRUB_CMDLINE_LINUX_DEFAULT?" | tee -a "$LOG"
      _sp=failed
    fi
    report_splash /etc/default/grub "$_sp"
  elif [ "$_sp" = present ] && ! _grub_cfg_splash; then
    report_splash /boot/grub/grub.cfg failed \
      "/etc/default/grub has it but grub.cfg is older - run: sudo grub-mkconfig -o /boot/grub/grub.cfg"
  else
    report_splash /etc/default/grub "$_sp"
  fi
fi

_splash_ok=true
if [ "$splash_sources" -eq 0 ]; then
  echo "${ERROR} Found no kernel command line to add 'splash' to (no /etc/kernel/cmdline, Limine config, systemd-boot entry or GRUB). Add it to your bootloader's entry by hand, or plymouth shows text instead of the logo." | tee -a "$LOG"
  _splash_ok=false
elif [ ${#splash_bad[@]} -gt 0 ]; then
  _splash_ok=false
fi
sudo sync 2>/dev/null || true

echo "${NOTE} Rebuilding the initramfs so the next boot carries the theme..." | tee -a "$LOG"
_rebuild_failed=false
if ! rebuild_initramfs "$LOG"; then
  _rebuild_failed=true
  echo "${ERROR} The theme is selected but the initramfs was not rebuilt, so the next boot still shows the old splash. Fix the error above, then rebuild (sudo limine-mkinitcpio on CachyOS+Limine, else sudo mkinitcpio -P)." | tee -a "$LOG"
fi

# limine-mkinitcpio has just rewritten the entries from KERNEL_CMDLINE: the word
# added there has to be in them now, or a per-kernel KERNEL_CMDLINE[<name>]
# overrides the default line.
if [ "$_limine_tool_check" = true ]; then
  if sudo grep -qE '^[[:space:]]*(kernel_)?cmdline:(.*[[:space:]])?splash(=[^[:space:]]*)?([[:space:]]|$)' "$_limine_conf"; then
    echo "${OK} The regenerated Limine entries in $_limine_conf carry 'splash'." | tee -a "$LOG"
  else
    echo "${ERROR} The Limine entries in $_limine_conf still have no 'splash' - check KERNEL_CMDLINE in /etc/default/limine (a per-kernel KERNEL_CMDLINE[<name>] replaces the default one)." | tee -a "$LOG"
    _splash_ok=false
  fi
fi

# Recorded for the final check, which cannot see any of this: "plymouth-splash"
# is not a pacman package, so only a later successful run takes it back out.
if [ "$_splash_ok" = true ]; then
  clear_package_failure "plymouth-splash"
else
  record_package_failure "plymouth-splash"
  _wiring_failed=true
fi

echo "${NOTE} To hide the motherboard's own logo as well, disable 'Boot Logo Display' in the BIOS." | tee -a "$LOG"
# /boot is root-only on CachyOS, so everything here goes through sudo -
# find_limine_conf included (the same search limine.sh uses, so this hint and
# that script agree on whether and where Limine is).
# Not when limine is in this run's selection: limine.sh runs right after this
# script and applies the theme, so the hint only told you to do what was about
# to happen anyway.
if [[ " ${INSTALL_SELECTED_OPTIONS:-} " != *" limine "* ]] \
   && _limine_conf=$(find_limine_conf) && ! sudo grep -q 'my_archinstaller Limine theme' "$_limine_conf" 2>/dev/null; then
  echo "${NOTE} Limine is installed and unthemed. The 'limine' preset option (install-scripts/limine.sh) applies the matching boot-menu theme; see README 'Limine boot menu theme'." | tee -a "$LOG"
fi

printf "\n%.0s" {1..1}

# Non-zero last, so the hints above are still printed. install.sh does not act
# on this status; the final check does, through INITRAMFS_FAILED_MANIFEST, the
# plymouth-splash entry recorded above and its own HOOKS check.
if [ "$_rebuild_failed" = true ] || [ "$_wiring_failed" = true ]; then
  exit 1
fi
