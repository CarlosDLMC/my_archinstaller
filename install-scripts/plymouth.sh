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

# Installed kernels, one pkgbase each: a /usr/lib/modules/<kver>/ whose vmlinuz a
# package owns, as in nvidia.sh. Limine's entry tool names its entries after
# them, and this system's loader entries boot /vmlinuz-<pkgbase>.
installed_kernels() {
  local d
  for d in /usr/lib/modules/*/; do
    [ -f "$d/pkgbase" ] || continue
    pacman -Qqo "${d}vmlinuz" &>/dev/null || continue
    cat "$d/pkgbase"
  done | sort -u
  return 0
}
PLY_KERNELS="$(installed_kernels | paste -sd' ' -)"
PLY_MACHINE_ID="$(cat /etc/machine-id 2>/dev/null || true)"
export PLY_KERNELS PLY_MACHINE_ID

# 1. The plymouth hook.
#
# A drop-in rather than a sed on /etc/mkinitcpio.conf. mkinitcpio joins the main
# file and every drop-in into one file and sources it as bash, so the drop-in
# can put plymouth into whatever HOOKS the files before it set - a multi-line
# array, or a HOOKS= in another drop-in, included. The place is the Arch wiki's:
# right after systemd (or udev), which also keeps it ahead of encrypt and
# sd-encrypt, so the LUKS prompt is drawn by the splash.
#
# It starts with an empty line, because that joining is a plain `cat`: a file
# before it that ends without a newline would otherwise run its last line into
# the drop-in's first one, and the whole config - every mkinitcpio run from then
# on, kernel updates included - would stop parsing. It is installed 0644 whatever
# the umask, so the checks here, which read it as you, see what mkinitcpio sees.
# "zz-" sorts after the usual numbered names. No name is guaranteed to sort last
# (under mkinitcpio's `sort -V` a name starting with "_" comes later), so a
# drop-in that sorts after it and sets HOOKS again would undo it - which
# mkinitcpio_has_hook catches, because it reads the files in mkinitcpio's order.
echo "${NOTE} Making sure the initramfs starts ${SKY_BLUE}plymouth${RESET}..." | tee -a "$LOG"
PLY_DROPIN="/etc/mkinitcpio.conf.d/zz-my_archinstaller-plymouth.conf"
PLY_HOOK_SNIPPET=$(cat <<'HOOK'

# Installed by my_archinstaller (install-scripts/plymouth.sh).
#
# Puts the plymouth hook right after systemd (or udev) in the HOOKS set before
# this point, which keeps it ahead of encrypt/sd-encrypt. It changes nothing
# when plymouth is already there. mkinitcpio sources its configuration as bash.
# The empty first line is on purpose: mkinitcpio joins its config files with
# cat, and a file before this one that ends without a newline would otherwise
# run into it.
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
_hook_failed=false
if command -v mkinitcpio &>/dev/null; then
  if mkinitcpio_has_hook plymouth; then
    echo "${OK} plymouth is already in the mkinitcpio HOOKS." | tee -a "$LOG"
  elif printf '%s\n' "$PLY_HOOK_SNIPPET" > "$PLY_TMP/dropin" \
       && sudo install -D -m 0644 -o root -g root "$PLY_TMP/dropin" "$PLY_DROPIN" 2>>"$LOG" \
       && mkinitcpio_has_hook plymouth; then
    echo "${OK} Added the plymouth hook with $PLY_DROPIN (right after systemd/udev)." | tee -a "$LOG"
  else
    # A drop-in that did not take would only mislead the next reader.
    sudo rm -f "$PLY_DROPIN" 2>>"$LOG" || true
    echo "${ERROR} Could not put plymouth into the mkinitcpio HOOKS: they hold neither systemd nor udev, a drop-in that sorts after ${PLY_DROPIN##*/} sets HOOKS again, or the config does not parse. Add plymouth after systemd or udev by hand." | tee -a "$LOG"
    _hook_failed=true
  fi

  # A preset that names a config file (ALL_config=, default_config=, ...) runs
  # mkinitcpio with -c, and -c skips the drop-ins - the case nvidia.sh handles
  # for MODULES. The same snippet goes at the end of each such file instead,
  # between markers so a re-run finds it, and comes out again if it did not take.
  # Read through sudo: such a file can be root-only.
  PLY_MARK="# --- my_archinstaller plymouth hook"
  custom_confs=$(sed -nE 's/^\s*[A-Za-z_]*config=["\x27]?([^"\x27 ]+)["\x27]?.*/\1/p' /etc/mkinitcpio.d/*.preset 2>/dev/null | sort -u)
  for _conf in $custom_confs; do
    if mkinitcpio_has_hook plymouth "$_conf"; then
      echo "${OK} plymouth is already in the HOOKS of $_conf." | tee -a "$LOG"
      continue
    fi
    _appended=false
    if ! sudo grep -qF "$PLY_MARK" "$_conf" 2>/dev/null \
       && sudo cp -- "$_conf" "$_conf.pre-plymouth" 2>>"$LOG" \
       && printf '\n%s (install-scripts/plymouth.sh) ---\n%s\n%s end ---\n' "$PLY_MARK" "$PLY_HOOK_SNIPPET" "$PLY_MARK" \
          | sudo tee -a "$_conf" >/dev/null; then
      _appended=true
    fi
    if [ "$_appended" = true ] && mkinitcpio_has_hook plymouth "$_conf"; then
      echo "${OK} Added the plymouth hook to $_conf (a preset uses it with -c, so drop-ins do not apply)." | tee -a "$LOG"
    else
      if [ "$_appended" = true ]; then
        sudo cp -- "$_conf.pre-plymouth" "$_conf" 2>>"$LOG" || true
      fi
      echo "${ERROR} Could not put plymouth into the HOOKS of $_conf, which a preset uses with -c - add it after systemd or udev there by hand." | tee -a "$LOG"
      _hook_failed=true
    fi
  done
elif command -v dracut &>/dev/null; then
  echo "${NOTE} dracut builds the initramfs here, and it adds plymouth by itself once the package is installed." | tee -a "$LOG"
else
  echo "${ERROR} Neither mkinitcpio nor dracut builds the initramfs here, so nothing can start plymouth at boot." | tee -a "$LOG"
  _hook_failed=true
fi
# Recorded, because the final check's own HOOKS test reads only the default
# layout (/etc/mkinitcpio.conf and the drop-ins) and would pass the rest.
if [ "$_hook_failed" = true ]; then
  record_package_failure "plymouth-hook"
  _wiring_failed=true
else
  clear_package_failure "plymouth-hook"
fi

# 2. `splash` on the kernel command line.
#
# Every place a command line comes from gets it - one machine can have several
# (loader entries next to a UKI's /etc/kernel/cmdline) - and each edit adds that
# one word and nothing else. That is checked twice before a file is replaced:
# the edited copy may differ from the original only by the word, and the command
# line the boot tool actually computes from it has to come out as before plus
# "splash" - for Limine's entry tool by asking the tool itself, per kernel
# (limine-entry-tool --get-cmdline), for GRUB by sourcing the file the way
# grub-mkconfig does. Comparing text alone let edits through that looked like one
# word and left a command line of just "splash", with no root= in it.
#
# The original is kept as <file>.pre-plymouth, copied right before the edit and
# compared with what was read. `quiet` is left alone: hiding the kernel's
# messages is a choice about debugging, not about the splash. So is
# splash=verbose, plymouth's own "text, not the logo", which is kept as it is.
echo "${NOTE} Making sure the kernel command line asks for the ${SKY_BLUE}splash${RESET}..." | tee -a "$LOG"
SPLASH_PY=$(cat <<'PY'
import os, re, sys

def words(v):
    return v.split()

# "splash" as a word of a command line; plymouth also takes splash=<x>.
def has_splash(v):
    return any(w == 'splash' or w.startswith('splash=') for w in words(v))

def state(v):
    if 'splash=verbose' in words(v):
        return 'verbose'
    return 'present' if has_splash(v) else 'missing'

# The same word in a whole config line, where a quote, "=" or ":" can border it
# as well as whitespace (GRUB_CMDLINE_LINUX_DEFAULT="quiet splash").
def splash_in_line(line):
    return re.search(r'(?:^|[\s"\'=:])splash(?:=\S*)?(?=[\s"\']|$)', line) is not None

def comment(line):
    return re.match(r'\s*#', line) is not None

# The text with CRLF turned into LF, and the line ending to write it back with.
# A file that mixes the two is refused: writing it back either way changes
# lines the edit never meant to touch.
def load(path):
    raw = open(path, newline='').read()
    crlf = raw.count('\r\n')
    if crlf and crlf != raw.count('\n'):
        return None, None
    return raw.replace('\r\n', '\n'), ('\r\n' if crlf else '\n')

def lines_of(text):
    lines = text.split('\n')
    if lines and lines[-1] == '':
        lines.pop()
    return lines

# /etc/kernel/cmdline: its lines that are not comments, joined - what
# kernel-install (grep -v '^\s*#') and mkinitcpio's UKIs read. One with nothing
# in it is no command line at all: the tools fall back to /proc/cmdline, and
# "splash" on its own would replace that, so it is left alone.
def kc_value(text):
    return ' '.join(l.strip() for l in text.split('\n') if l.strip() and not comment(l))

def edit_kcmdline(text, var):
    value = kc_value(text)
    if not value:
        return 'blank', text
    s = state(value)
    if s != 'missing':
        return s, text
    lines = text.split('\n')
    i = max(j for j, l in enumerate(lines) if l.strip() and not comment(l))
    lines[i] = lines[i].rstrip() + ' splash'
    return 'added', '\n'.join(lines)

# systemd-boot Type #1 entry: every options line, joined. Only entries that boot
# one of this system's kernels - /vmlinuz-<pkgbase> of an installed kernel, or
# kernel-install's /<machine-id>/<version>/linux. Another system's entries on a
# shared ESP are its own business, and an "efi" entry (Windows, a firmware
# tool) takes no kernel options.
def entry_value(lines):
    return ' '.join(re.sub(r'^\s*options', '', l, count=1).strip()
                    for l in lines if re.match(r'\s*options(\s|$)', l))

def entry_is_ours(lines):
    paths = [l.split(None, 1)[1].strip() for l in lines if re.match(r'\s*linux\s+\S', l)]
    if not paths:
        return None
    kernels = os.environ.get('PLY_KERNELS', '').split()
    mid = os.environ.get('PLY_MACHINE_ID', '').strip()
    if not kernels and not mid:
        return True
    for p in paths:
        if p.rsplit('/', 1)[-1] in ['vmlinuz-' + k for k in kernels]:
            return True
        if mid and '/' + mid + '/' in p:
            return True
    return False

def edit_entry(text, var):
    lines = text.split('\n')
    ours = entry_is_ours(lines)
    if ours is None:
        return 'skip', text
    if not ours:
        return 'foreign', text
    opts = [i for i, l in enumerate(lines) if re.match(r'\s*options(\s|$)', l)]
    if not opts:
        return 'nooptions', text
    s = state(entry_value(lines))
    if s != 'missing':
        return s, text
    # systemd-boot joins all options lines, so the last one is as good as any.
    lines[opts[-1]] = lines[opts[-1]].rstrip() + ' splash'
    return 'added', '\n'.join(lines)

# limine.conf written by hand or by archinstall (not by limine-entry-tool). An
# entry starts at a line whose first character is "/"; only the ones with
# protocol: linux take a kernel command line - an efi entry (a UKI, Windows)
# gets its command line from elsewhere or not at all.
CMDLINE = re.compile(r'^(\s*(?:kernel_cmdline|cmdline)\s*:)(.*)$')

def limine_entries(lines):
    starts = [i for i, l in enumerate(lines) if re.match(r'\s*/', l)]
    out = []
    for n, s in enumerate(starts):
        body = list(range(s + 1, starts[n + 1] if n + 1 < len(starts) else len(lines)))
        if any(re.match(r'\s*protocol\s*:\s*linux\s*$', lines[i], re.I) for i in body):
            out.append((s, body, [i for i in body if CMDLINE.match(lines[i])]))
    return out

def limine_value(lines, cl):
    return ' '.join(CMDLINE.match(lines[i]).group(2).strip() for i in cl)

def edit_limine(text, var):
    lines = text.split('\n')
    entries = limine_entries(lines)
    if not entries:
        return 'skip', text
    entries = [e for e in entries if e[2]]
    if not entries:
        return 'none', text
    changed, states = False, []
    for s, body, cl in entries:
        st = state(limine_value(lines, cl))
        states.append(st)
        if st == 'missing':
            m = CMDLINE.match(lines[cl[-1]])
            lines[cl[-1]] = (lines[cl[-1]].rstrip() + ' splash') if m.group(2).strip() else (m.group(1) + ' splash')
            changed = True
    if changed:
        return 'added', '\n'.join(lines)
    return ('verbose' if 'verbose' in states else 'present'), text

# A shell variable in a file that is sourced: GRUB_CMDLINE_LINUX_DEFAULT in
# /etc/default/grub, LINUX_OPTIONS in /etc/sdboot-manage.conf. Only a plain
# `NAME="..."` line is edited. When the name appears in any other form (export,
# declare, +=, shared with other commands on a line), the file is not touched at
# all - a line added after it would silently replace the real value. An unset
# GRUB_CMDLINE_LINUX_DEFAULT is empty, so it may be set to just the word
# (may_add); LINUX_OPTIONS may not, since sdboot-manage builds the whole options
# line from it.
def edit_shellvar(text, var, may_add):
    lines = text.split('\n')
    name = re.escape(var)
    plain = re.compile(r'^(\s*' + name + r'=)(?:"([^"]*)"|\'([^\']*)\'|([^\s"\'#;&|\x60$]*))(\s*(?:#.*)?)$')
    idx = [i for i, l in enumerate(lines) if plain.match(l)]
    other = [i for i, l in enumerate(lines)
             if i not in idx and not comment(l) and re.search(r'\b' + name + r'\b', l)]
    if other:
        return 'unparsed', text
    if not idx:
        if not may_add:
            return 'undefined', text
        at = len(lines) - 1 if lines and lines[-1] == '' else len(lines)
        lines.insert(at, var + '="splash"')
        return 'added', '\n'.join(lines)
    m = plain.match(lines[idx[-1]])
    if m.group(2) is not None:
        quote, value = '"', m.group(2)
    elif m.group(3) is not None:
        quote, value = "'", m.group(3)
    elif m.group(4) == '':
        quote, value = '', ''
    else:
        return 'unparsed', text   # an unquoted word: quoting it is more than adding one
    s = state(value)
    if s != 'missing':
        return s, text
    value = value.rstrip() + ' splash' if value.strip() else 'splash'
    lines[idx[-1]] = m.group(1) + quote + value + quote + m.group(5)
    return 'added', '\n'.join(lines)

# Limine's entry tool: one more line. What the tool makes of it is asked of the
# tool itself afterwards, not worked out here.
LT_LINE = 'KERNEL_CMDLINE[default]+="splash"'

def edit_limine_tool(text, var):
    body = text if text == '' or text.endswith('\n') else text + '\n'
    return 'added', body + LT_LINE + '\n'

# The edited text may differ from the original only by "splash" added to lines
# that did not have it, or by one line that sets a missing variable to it. A
# missing final newline on either side does not count as a difference.
def only_splash_added(old, new):
    o, n = lines_of(old), lines_of(new)
    if len(n) == len(o) + 1:
        extra = ('GRUB_CMDLINE_LINUX_DEFAULT="splash"', LT_LINE)
        return any(n[j] in extra and n[:j] + n[j + 1:] == o for j in range(len(n)))
    if len(n) != len(o):
        return False
    changed = 0
    for a, b in zip(o, n):
        if a == b:
            continue
        undone = set()
        for w in (' splash', 'splash'):
            k = b.find(w)
            while k != -1:
                undone.add((b[:k] + b[k + len(w):]).rstrip())
                k = b.find(w, k + 1)
        if a.rstrip() not in undone or not splash_in_line(b):
            return False
        changed += 1
    return changed > 0

# The command lines the file gives the kernel, before and after: each one has to
# stay as it was, or gain exactly the one word it lacked.
def units(mode, text):
    lines = text.split('\n')
    if mode == 'kcmdline':
        return [kc_value(text)]
    if mode == 'entry':
        return [entry_value(lines)]
    return [limine_value(lines, cl) for s, body, cl in limine_entries(lines) if cl]

def semantic(mode, old, new):
    a, b = units(mode, old), units(mode, new)
    if len(a) != len(b):
        return False
    changed = 0
    for x, y in zip(a, b):
        if sorted(words(x)) == sorted(words(y)):
            continue
        if not has_splash(x) and sorted(words(y)) == sorted(words(x) + ['splash']):
            changed += 1
            continue
        return False
    return changed > 0

# After limine-mkinitcpio has rewritten the entries: every installed kernel's
# entry - found by limine-entry-tool's "kernel-id=" comment, or else by its
# "//<kernel>" heading - has to carry the word. Prints the kernels that do not.
def limine_verify(path, kernels):
    text, nl = load(path)
    if text is None:
        print(' '.join(kernels))
        return 1
    lines = text.split('\n')
    missing = []
    for k in kernels:
        found = ok = False
        for s, body, cl in limine_entries(lines):
            ids = [m.group(1) for i in body for m in [re.search(r'\bkernel-id=(\S+)', lines[i])] if m]
            if (ids and k in ids) or (not ids and lines[s].strip().lstrip('/').strip() == k):
                found = True
                ok = ok or (bool(cl) and has_splash(limine_value(lines, cl)))
        if found and not ok:
            missing.append(k)
    print(' '.join(missing))
    return 1 if missing else 0

cmd = sys.argv[1]
if cmd == 'edit':
    mode, src, dst = sys.argv[2:5]
    var = sys.argv[5] if len(sys.argv) > 5 else ''
    text, nl = load(src)
    if text is None:
        print('mixed')
        sys.exit(0)
    if mode in ('shellvar', 'shellvar-set'):
        status, out = edit_shellvar(text, var, mode == 'shellvar')
    else:
        status, out = {'kcmdline': edit_kcmdline, 'entry': edit_entry, 'limine': edit_limine,
                       'limine-tool': edit_limine_tool}[mode](text, var)
    if status == 'added':
        with open(dst, 'w', newline='') as f:
            f.write(out.replace('\n', nl))
    print(status)
elif cmd == 'check':
    a, x = load(sys.argv[2])
    b, x = load(sys.argv[3])
    sys.exit(0 if a is not None and b is not None and only_splash_added(a, b) else 1)
elif cmd == 'semantic':
    a, x = load(sys.argv[3])
    b, x = load(sys.argv[4])
    sys.exit(0 if a is not None and b is not None and semantic(sys.argv[2], a, b) else 1)
elif cmd == 'limine-verify':
    sys.exit(limine_verify(sys.argv[2], sys.argv[3:]))
PY
)

# Command lines compared word for word, order ignored.
cmdline_words() { tr -s ' \t\n' '\n' <<< "$1" | sed '/^$/d' | sort; }
cmdline_same() { [ "$(cmdline_words "$1")" = "$(cmdline_words "$2")" ]; }
# Is <after> exactly <before> plus one "splash"?
cmdline_plus_splash() { [ "$(cmdline_words "$2")" = "$(cmdline_words "$1 splash")" ]; }
cmdline_has_splash() { cmdline_words "$1" | grep -qE '^splash(=|$)'; }
cmdline_text_mode() { cmdline_words "$1" | grep -qx 'splash=verbose'; }

# The value of <var> once <file> and then <more files> are sourced in a clean
# shell - how grub-mkconfig reads /etc/default/grub and /etc/default/grub.d.
shellvar_value() {
  local var="$1"
  shift
  env -i PATH=/usr/bin:/bin V="$var" bash -c 'for f; do if [ -r "$f" ]; then . "$f"; fi; done >/dev/null 2>&1 </dev/null
                                            printf "%s" "${!V-}"' _ "$@" 2>/dev/null
  return 0
}

# Files this run edited or created, for the Limine safety net further down.
_edited=()
_created=()

# ensure_splash <mode> <file> [<var> [files sourced after it...]]
# Adds the word to <file> and sets _sp to added, or to present, verbose, skip,
# foreign, blank, undefined - or to why it could not: nooptions, unparsed, none,
# mixed, error, failed. <var> and the extra files are for the shellvar modes.
# <file> is read and written through sudo - the ESP is routinely mounted
# root-only. Always returns 0: this runs under Global_functions.sh's set -e.
ensure_splash() {
  local mode="$1" file="$2" var="" existed=false st before after
  shift 2
  case "$mode" in shellvar*) var="$1"; shift ;; esac
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
    return 0
  fi
  st=$(python3 -c "$SPLASH_PY" edit "$mode" "$PLY_TMP/old" "$PLY_TMP/new" "$var" 2>>"$LOG") || st=error
  if [ "$st" != added ]; then
    _sp="${st:-error}"
    return 0
  fi
  if ! python3 -c "$SPLASH_PY" check "$PLY_TMP/old" "$PLY_TMP/new" 2>>"$LOG"; then
    echo "${ERROR} The edit of $file would change more than adding 'splash' - not writing it." | tee -a "$LOG"
    return 0
  fi
  case "$mode" in
    kcmdline|entry|limine)
      if ! python3 -c "$SPLASH_PY" semantic "$mode" "$PLY_TMP/old" "$PLY_TMP/new" 2>>"$LOG"; then
        echo "${ERROR} Edited, $file would give the kernel more than 'splash' extra - not writing it." | tee -a "$LOG"
        return 0
      fi
      ;;
    shellvar*)
      before=$(shellvar_value "$var" "$PLY_TMP/old" "$@")
      after=$(shellvar_value "$var" "$PLY_TMP/new" "$@")
      if ! cmdline_plus_splash "$before" "$after"; then
        echo "${ERROR} Sourced the way its tool reads it, the edited $file would set $var to \"$after\" rather than \"$before\" plus 'splash' (does another file set it too?) - not writing it." | tee -a "$LOG"
        return 0
      fi
      ;;
  esac
  if [ "$existed" = true ]; then
    if ! sudo cp -- "$file" "$file.pre-plymouth" 2>>"$LOG" || ! sudo cmp -s -- "$PLY_TMP/old" "$file.pre-plymouth"; then
      echo "${ERROR} Could not back up $file to $file.pre-plymouth - not editing it." | tee -a "$LOG"
      return 0
    fi
  fi
  if sudo cp -- "$PLY_TMP/new" "$file" 2>>"$LOG" && sudo cmp -s -- "$PLY_TMP/new" "$file"; then
    _sp=added
    if [ "$existed" = true ]; then _edited+=("$file"); else _created+=("$file"); _sp_created=true; fi
  elif [ "$existed" = true ]; then
    sudo cp -- "$PLY_TMP/old" "$file" 2>>"$LOG" || true
  else
    sudo rm -f -- "$file" 2>>"$LOG" || true
  fi
  return 0
}

# Put a file this run changed back the way it was (or remove one it created).
undo_splash_edit() {
  local f
  for f in "$@"; do
    if [[ " ${_created[*]} " == *" $f "* ]]; then
      sudo rm -f -- "$f" 2>>"$LOG" || true
    elif [[ " ${_edited[*]} " == *" $f "* ]]; then
      sudo cp -- "$f.pre-plymouth" "$f" 2>>"$LOG" || true
    fi
  done
  return 0
}

splash_sources=0
_splash_ok=true
# report_splash <what> <status> [what to do by hand]: prints the outcome and
# counts it. A failure clears _splash_ok, which the final check hears about.
report_splash() {
  local what="$1" st="$2" why
  case "$st" in
    skip) return 0 ;;
    foreign)
      echo "${NOTE} $what boots a kernel that is not installed here (another system on this ESP?) - left alone." | tee -a "$LOG"
      return 0 ;;
    blank)
      echo "${NOTE} $what holds no command line (empty, or only comments) - left alone: 'splash' on its own would replace the one the tools fall back to." | tee -a "$LOG"
      return 0 ;;
    undefined)
      echo "${NOTE} $what does not set its options line, so the entries it writes do not come from there - left alone." | tee -a "$LOG"
      return 0 ;;
    present) echo "${OK} $what already has 'splash'." | tee -a "$LOG" ;;
    verbose) echo "${NOTE} $what asks plymouth for text on purpose (splash=verbose) - kept as it is." | tee -a "$LOG" ;;
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
          unparsed)  why="the variable is set in a form this script does not edit: export, declare, +=, or next to other commands on its line" ;;
          none)      why="no Linux entry in it has a cmdline line" ;;
          mixed)     why="it mixes CRLF and LF line endings" ;;
          *)         why="see $LOG" ;;
        esac
        echo "${ERROR} Could not add 'splash' to $what ($why). Add it to the kernel command line there by hand." | tee -a "$LOG"
      fi
      _splash_ok=false
      ;;
  esac
  splash_sources=$((splash_sources + 1))
  return 0
}

# Limine's entry tool, asked for the command line it gives <kernel>. One
# argument - it takes the kernel name alone - and it answers for any name, so an
# empty answer is the only failure it has.
lt_cmdline() {
  sudo limine-entry-tool --get-cmdline "$1" 2>/dev/null | head -n 1
  return 0
}
_lt_mode=false
_lt_check=false
_lt_names="${PLY_KERNELS:-default}"
declare -A _lt_orig=()
if _limine_conf=$(find_limine_conf); then
  if command -v limine-entry-tool &>/dev/null; then
    _lt_mode=true
    for _k in $_lt_names; do
      _lt_orig[$_k]="$(lt_cmdline "$_k")"
    done
  fi
else
  _limine_conf=""
fi

# /etc/kernel/cmdline: what mkinitcpio builds a UKI's command line from, and
# kernel-install writes loader entries from. First, because Limine's entry tool
# below falls back to it.
if sudo test -f /etc/kernel/cmdline; then
  ensure_splash kcmdline /etc/kernel/cmdline
  report_splash /etc/kernel/cmdline "$_sp"
fi

# Limine with its entry tool (CachyOS, or limine-mkinitcpio-hook from the AUR):
# the tool writes the kernel entries from KERNEL_CMDLINE and rewrites them on
# every kernel update, so the word goes there, not into limine.conf - as a `+=`
# line in /etc/default/limine, the file its own docs recommend `+=` for. Whether
# that line does what it should is then asked of the tool, kernel by kernel: each
# command line has to come out as before plus "splash". It does not when
# KERNEL_CMDLINE[default] is blank or unset - a `+=` makes the tool stop reading
# /etc/kernel/cmdline and /proc/cmdline, so it would boot with "splash" alone -
# or when a kernel has a KERNEL_CMDLINE[<kernel>] of its own. Then the line comes
# out again and it is reported.
ensure_splash_limine_tool() {
  local k f=/etc/default/limine after missing="" improved="" still="" bad="" verbose=false
  local -A now=()
  for k in $_lt_names; do
    now[$k]="$(lt_cmdline "$k")"
    if [ -z "${now[$k]}" ]; then
      report_splash "limine-entry-tool's command line" failed "It printed nothing for $k (limine-entry-tool --get-cmdline $k)."
      return 0
    fi
    if ! cmdline_has_splash "${now[$k]}"; then missing+="$k "; fi
    if cmdline_text_mode "${now[$k]}"; then verbose=true; fi
  done
  if [ -z "$missing" ]; then
    if [ "$verbose" = true ]; then
      report_splash "limine-entry-tool's command line" verbose
    else
      report_splash "limine-entry-tool's command line" present
    fi
    _lt_check=true
    return 0
  fi
  ensure_splash limine-tool "$f"
  if [ "$_sp" != added ]; then
    report_splash "$f" "$_sp"
    return 0
  fi
  for k in $_lt_names; do
    after="$(lt_cmdline "$k")"
    if cmdline_same "${now[$k]}" "$after"; then
      if [[ " $missing " == *" $k "* ]]; then still+="$k "; fi
    elif [[ " $missing " == *" $k "* ]] && cmdline_plus_splash "${now[$k]}" "$after"; then
      improved+="$k "
    else
      bad="$k"
      break
    fi
  done
  if [ -n "$bad" ]; then
    undo_splash_edit "$f"
    report_splash "$f" failed "With $f ending in KERNEL_CMDLINE[default]+=\"splash\", limine-entry-tool would give $bad the command line \"$after\" instead of \"${now[$bad]}\" plus 'splash' - put back. Add 'splash' where its command line comes from, then run: sudo limine-mkinitcpio"
    return 0
  fi
  if [ -z "$improved" ]; then
    undo_splash_edit "$f"
    report_splash "$f" failed "limine-entry-tool does not build its command line from KERNEL_CMDLINE[default] here (a KERNEL_CMDLINE[<kernel>] of its own, or none at all, so it reads /etc/kernel/cmdline or /proc/cmdline) - put back. Add 'splash' where it does come from, then run: sudo limine-mkinitcpio"
    return 0
  fi
  report_splash "$f" added
  if [ -n "$still" ]; then
    report_splash "limine-entry-tool's command line for ${still% }" failed "A KERNEL_CMDLINE[<kernel>] of its own replaces the default line for it - add 'splash' to that one in $f, then run: sudo limine-mkinitcpio"
  fi
  _lt_check=true
  return 0
}
if [ "$_lt_mode" = true ]; then
  ensure_splash_limine_tool
elif [ -n "$_limine_conf" ]; then
  # A limine.conf nothing generates (archinstall writes one like that): the
  # entries themselves carry the command line.
  ensure_splash limine "$_limine_conf"
  report_splash "$_limine_conf" "$_sp"
fi

# systemd-boot: every entry that boots one of this system's kernels, on the ESP
# or an XBOOTLDR partition. archinstall writes them once and never again, so
# they are edited in place. Read on fd 3, so nothing in the loop can swallow the
# list.
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

# CachyOS's systemd-boot manager rewrites those entries from LINUX_OPTIONS on
# every kernel update, which would take the word straight back out of them.
if [ -f /etc/sdboot-manage.conf ]; then
  ensure_splash shellvar-set /etc/sdboot-manage.conf LINUX_OPTIONS
  report_splash /etc/sdboot-manage.conf "$_sp"
fi

# GRUB: GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub (the normal entries -
# the recovery ones stay without), then grub.cfg rebuilt from it. Only when
# this run changed the file, since grub-mkconfig would also apply anything else
# that is pending in it. grub.cfg is copied to grub.cfg.pre-plymouth first, and
# both files go back if grub-mkconfig fails, gives no entry the word, or leaves
# out a menu entry the old grub.cfg had (os-prober's, one written by hand).
if command -v grub-mkconfig &>/dev/null && [ -f /etc/default/grub ] && sudo test -f /boot/grub/grub.cfg; then
  _grub_cfg=/boot/grub/grub.cfg
  grub_cfg_splash() {
    sudo grep -qE '^[[:space:]]*linux[[:space:]].*[[:space:]]splash([=[:space:]]|$)' "$_grub_cfg"
  }
  grub_titles() {
    sudo grep -oE "^[[:space:]]*(menuentry|submenu)[[:space:]]+('[^']*'|\"[^\"]*\")" "$_grub_cfg" 2>/dev/null \
      | sed -E 's/^[[:space:]]*(menuentry|submenu)[[:space:]]+//' | sort -u
    return 0
  }
  ensure_splash shellvar /etc/default/grub GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub.d/*.cfg
  if [ "$_sp" = added ]; then
    cp "$PLY_TMP/old" "$PLY_TMP/grub-default.old"
    _grub_titles_before=$(grub_titles)
    if ! sudo cp -- "$_grub_cfg" "$_grub_cfg.pre-plymouth" 2>>"$LOG"; then
      echo "${ERROR} Could not back up $_grub_cfg - putting /etc/default/grub back." | tee -a "$LOG"
      sudo cp -- "$PLY_TMP/grub-default.old" /etc/default/grub 2>>"$LOG" || true
      _sp=failed
    elif ! sudo grub-mkconfig -o "$_grub_cfg" >> "$LOG" 2>&1; then
      echo "${ERROR} grub-mkconfig failed - putting /etc/default/grub back; grub.cfg was left as it was." | tee -a "$LOG"
      sudo cp -- "$PLY_TMP/grub-default.old" /etc/default/grub 2>>"$LOG" || true
      _sp=failed
    else
      _grub_lost=$(comm -23 <(printf '%s\n' "$_grub_titles_before") <(grub_titles) | sed '/^$/d' | paste -sd, -)
      if [ -n "$_grub_lost" ] || ! grub_cfg_splash; then
        if [ -n "$_grub_lost" ]; then
          echo "${ERROR} The regenerated grub.cfg lost menu entries ($_grub_lost) - putting grub.cfg and /etc/default/grub back." | tee -a "$LOG"
        else
          echo "${ERROR} grub.cfg has no 'splash' after grub-mkconfig - putting grub.cfg and /etc/default/grub back." | tee -a "$LOG"
        fi
        sudo cp -- "$_grub_cfg.pre-plymouth" "$_grub_cfg" 2>>"$LOG" || true
        sudo cp -- "$PLY_TMP/grub-default.old" /etc/default/grub 2>>"$LOG" || true
        _sp=failed
      fi
    fi
    report_splash /etc/default/grub "$_sp"
  elif [ "$_sp" = present ] && ! grub_cfg_splash; then
    report_splash "$_grub_cfg" failed \
      "/etc/default/grub has it but grub.cfg is older - run: sudo grub-mkconfig -o /boot/grub/grub.cfg"
  else
    report_splash /etc/default/grub "$_sp"
  fi
fi

# Safety net for Limine's entry tool: whatever this run edited, each kernel's
# command line has to be what it was, or that plus "splash". Otherwise every
# file it reads that this run touched goes back.
if [ "$_lt_mode" = true ]; then
  for _k in $_lt_names; do
    _final="$(lt_cmdline "$_k")"
    if cmdline_same "${_lt_orig[$_k]}" "$_final"; then continue; fi
    if ! cmdline_has_splash "${_lt_orig[$_k]}" && cmdline_plus_splash "${_lt_orig[$_k]}" "$_final"; then continue; fi
    undo_splash_edit /etc/kernel/cmdline /etc/default/limine
    report_splash "limine-entry-tool's command line for $_k" failed \
      "It came out as \"$_final\" instead of \"${_lt_orig[$_k]}\" plus 'splash', so /etc/kernel/cmdline and /etc/default/limine were put back."
    _lt_check=false
    break
  done
fi

# Nothing this script knows how to edit: rEFInd, EFISTUB, a grub.cfg outside
# /boot/grub, a UKI built from /etc/cmdline.d alone. That is only a problem when
# this boot's own command line has no splash either.
if [ "$splash_sources" -eq 0 ]; then
  if cmdline_has_splash "$(cat /proc/cmdline 2>/dev/null)"; then
    echo "${NOTE} This machine's bootloader is not one this script edits, but this boot already has 'splash' on its command line - nothing to do." | tee -a "$LOG"
  else
    echo "${ERROR} Found no kernel command line to add 'splash' to (no /etc/kernel/cmdline, Limine config, systemd-boot entry of this system or GRUB), and this boot has none. Add it to your bootloader's entry by hand, or plymouth shows text instead of the logo." | tee -a "$LOG"
    _splash_ok=false
  fi
fi
sudo sync 2>/dev/null || true

echo "${NOTE} Rebuilding the initramfs so the next boot carries the theme..." | tee -a "$LOG"
_rebuild_failed=false
if ! rebuild_initramfs "$LOG"; then
  _rebuild_failed=true
  echo "${ERROR} The theme is selected but the initramfs was not rebuilt, so the next boot still shows the old splash. Fix the error above, then rebuild (sudo limine-mkinitcpio on CachyOS+Limine, else sudo mkinitcpio -P)." | tee -a "$LOG"
fi

# limine-mkinitcpio has just rewritten the entries from KERNEL_CMDLINE: each
# installed kernel's entry in limine.conf has to carry the word now.
if [ "$_lt_check" = true ] && [ "$_rebuild_failed" = false ]; then
  _lt_missing=""
  if ! sudo cat -- "$_limine_conf" > "$PLY_TMP/limine.conf" 2>>"$LOG" \
     || ! _lt_missing=$(python3 -c "$SPLASH_PY" limine-verify "$PLY_TMP/limine.conf" $_lt_names 2>>"$LOG"); then
    echo "${ERROR} The Limine entries in $_limine_conf still have no 'splash' for: ${_lt_missing:-(could not read it)}. Check KERNEL_CMDLINE in /etc/default/limine, then run: sudo limine-mkinitcpio" | tee -a "$LOG"
    _splash_ok=false
  else
    echo "${OK} The Limine entries in $_limine_conf carry 'splash' for every kernel." | tee -a "$LOG"
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
