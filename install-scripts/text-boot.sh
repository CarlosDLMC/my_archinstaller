#!/bin/bash
# Text boot - the kernel's and systemd's boot messages on screen, no splash.
#
# The opposite of plymouth.sh, and the shipped preset's choice: after the
# bootloader menu the screen scrolls the kernel log and systemd's "[  OK  ]
# Started ..." lines up to the login manager, as on a plain Arch install. CachyOS
# boots with `quiet splash` instead - `quiet` hides those lines and `splash`
# starts plymouth's graphical screen (the CachyOS watermark) over them - so this
# takes those two words off the kernel command line, wherever the machine keeps
# one: Limine's entry tool (KERNEL_CMDLINE in /etc/default/limine, CachyOS), a
# limine.conf nothing generates, /etc/kernel/cmdline (UKIs), systemd-boot entries
# and sdboot-manage, refind_linux.conf, and GRUB.
#
# It also takes the `kms` hook out of the initramfs (a drop-in in
# /etc/mkinitcpio.conf.d), so the GPU driver's takeover - a few seconds of black
# screen - comes after the LUKS prompt instead of in the middle of it.
#
# Plymouth itself is left installed where the distro put it. Without `splash` it
# runs in text mode - the LUKS prompt is a plain text prompt - and that is how the
# machine this repo was built from boots. install.sh does not run this when the
# plymouth option is selected as well: that one asks for the splash.
#
# Each edit removes those two words and nothing else, is checked before it is
# written (and, for Limine's entry tool and GRUB, against the command line the
# tool itself computes), and keeps the original as <file>.pre-text-boot.
# Re-running finds nothing to remove and changes nothing.

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "[ERROR] Failed to change directory to $PARENT_DIR"; exit 1; }

if ! source "$SCRIPT_DIR/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_text-boot.log"

printf "\n%s - Switching the boot to ${SKY_BLUE}text${RESET} (no 'quiet', no 'splash') \n" "${NOTE}"

TB_TMP="$(mktemp -d)"
trap 'rm -rf "$TB_TMP"' EXIT

# Installed kernels, one pkgbase each - the same test as plymouth.sh. Limine's
# entry tool names its entries after them, and this system's loader entries
# boot /vmlinuz-<pkgbase>.
installed_kernels() {
  local d
  for d in /usr/lib/modules/*/; do
    [ -f "$d/pkgbase" ] || continue
    pacman -Qqo "${d}vmlinuz" &>/dev/null || continue
    cat "$d/pkgbase"
  done | sort -u
  return 0
}
TB_KERNELS="$(installed_kernels | paste -sd' ' -)"
TB_MACHINE_ID="$(cat /etc/machine-id 2>/dev/null || true)"
export TB_KERNELS TB_MACHINE_ID

TB_PY=$(cat <<'PY'
import os, re, sys

DROP = ('quiet', 'splash')

def words(v):
    return v.split()

def without(ws):
    return [w for w in ws if w not in DROP]

def comment(line):
    return re.match(r'\s*#', line) is not None

# One of the two words as a whole word of a config line: whitespace, a quote,
# "=" or ":" may border it (GRUB_CMDLINE_LINUX_DEFAULT="quiet splash",
# KERNEL_CMDLINE[default]+=quiet splash, cmdline: quiet).
WORD = re.compile(r'(?:(?<=^)|(?<=[\s"\'=:]))(?:quiet|splash)(?=[\s"\']|$)')

def has_drop(text):
    return WORD.search(text) is not None

# Removes the words from a piece of a line, with the space that went with each,
# and leaves everything else - quoting, other words, their order - as it was.
def strip(seg):
    out = seg
    while True:
        m = WORD.search(out)
        if not m:
            return out
        a, b = m.start(), m.end()
        if b < len(out) and out[b] in ' \t':
            b += 1
            while b < len(out) and out[b] in ' \t':
                b += 1
        elif a > 0 and out[a - 1] in ' \t':
            while a > 0 and out[a - 1] in ' \t':
                a -= 1
        out = out[:a] + out[b:]

# CRLF turned into LF, and the ending to write back with; a file mixing the two
# is refused (writing it back either way changes lines the edit never touched).
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

# /etc/kernel/cmdline: every line that is not a comment.
def kc_value(lines):
    return ' '.join(l.strip() for l in lines if l.strip() and not comment(l))

def edit_kcmdline(lines, var):
    for i, l in enumerate(lines):
        if not comment(l):
            lines[i] = strip(l)
    return 'ok'

# systemd-boot Type #1 entry: only one that boots a kernel of this system, as in
# plymouth.sh - another system's entries on a shared ESP are its own business.
def entry_value(lines):
    return ' '.join(re.sub(r'^\s*options', '', l, count=1).strip()
                    for l in lines if re.match(r'\s*options(\s|$)', l))

def entry_is_ours(lines):
    paths = [l.split(None, 1)[1].strip() for l in lines if re.match(r'\s*linux\s+\S', l)]
    if not paths:
        return None
    kernels = os.environ.get('TB_KERNELS', '').split()
    mid = os.environ.get('TB_MACHINE_ID', '').strip()
    if not kernels and not mid:
        return True
    for p in paths:
        if p.rsplit('/', 1)[-1] in ['vmlinuz-' + k for k in kernels]:
            return True
        if mid and '/' + mid + '/' in p:
            return True
    return False

def edit_entry(lines, var):
    ours = entry_is_ours(lines)
    if ours is None:
        return 'skip'
    if not ours:
        return 'foreign'
    for i, l in enumerate(lines):
        m = re.match(r'(\s*options)(.*)$', l)
        if m and re.match(r'\s*options(\s|$)', l):
            lines[i] = m.group(1) + strip(m.group(2))
    return 'ok'

# limine.conf written by hand or by archinstall: the cmdline lines of Linux
# entries, and of efi entries that boot a unified kernel image (EFI/Linux/).
CMDLINE = re.compile(r'^(\s*(?:kernel_cmdline|cmdline)\s*:)(.*)$')
UKI_PATH = re.compile(r'^\s*(?:path|image_path)\s*:.*/EFI/Linux/[^/\s]+\.efi\s*$', re.I)

def limine_linux_entries(lines):
    starts = [i for i, l in enumerate(lines) if re.match(r'\s*/', l)]
    out = []
    for n, s in enumerate(starts):
        body = list(range(s + 1, starts[n + 1] if n + 1 < len(starts) else len(lines)))
        cl = [i for i in body if CMDLINE.match(lines[i])]
        if not cl:
            continue
        if any(re.match(r'\s*protocol\s*:\s*linux\s*$', lines[i], re.I) for i in body) \
           or (any(re.match(r'\s*protocol\s*:\s*efi(?:_chainload)?\s*$', lines[i], re.I) for i in body)
               and any(UKI_PATH.match(lines[i]) for i in body)):
            out.append((s, cl))
    return out

def limine_entries(lines):
    return [cl for s, cl in limine_linux_entries(lines)]

# Snapshot boot entries: limine-snapper-sync's, under its "Snapshots" heading,
# or any entry that roots the system in a snapper snapshot. Each one boots the
# system as it was when its snapshot was taken, command line included, and
# keeps the words it was made with - one taken during the install, before this
# script ran, has CachyOS's `quiet splash`. They are not what the next boot
# starts, and nothing here can change them, so the read-back below leaves them
# out: counted, they failed the check on every run, and stopped the reboot.
SNAPSHOT_ROOT = re.compile(r'subvol=[^\s"\']*/\.snapshots/')

def snapshot_starts(lines):
    stack, out = [], set()
    for i, l in enumerate(lines):
        m = re.match(r'\s*(/+)\+?(.*)$', l)
        if not m:
            continue
        depth = len(m.group(1))
        while stack and stack[-1][0] >= depth:
            stack.pop()
        stack.append((depth, m.group(2).strip().lower()))
        if any(title == 'snapshots' for d, title in stack):
            out.add(i)
    return out

def is_snapshot(lines, s, cl, snaps):
    return s in snaps or any(SNAPSHOT_ROOT.search(lines[i]) for i in cl)

def edit_limine(lines, var):
    entries = limine_entries(lines)
    if not entries:
        return 'skip'
    for cl in entries:
        for i in cl:
            m = CMDLINE.match(lines[i])
            lines[i] = m.group(1) + strip(m.group(2))
    return 'ok'

# A variable assignment, in a sourced shell file (/etc/default/grub,
# /etc/sdboot-manage.conf) or in Limine's entry-tool config, whose own parser
# also takes unquoted values and `+=`. <var> is a regex for the name; the words
# are removed from the part after the "=". Whether that left the value the tool
# reads as it should is asked of the tool afterwards, by the caller.
def edit_assign(lines, var):
    pat = re.compile(r'^(\s*(?:export\s+)?(?:' + var + r')(?:\[[^\]]*\])?\+?=)(.*)$')
    found = False
    for i, l in enumerate(lines):
        if comment(l):
            continue
        m = pat.match(l)
        if m:
            found = True
            lines[i] = m.group(1) + strip(m.group(2))
    return 'ok' if found else 'undefined'

# rEFInd's refind_linux.conf: "label" "options" per line.
REFIND_LINE = re.compile(r'^(\s*"[^"]*"\s+")([^"]*)("\s*)$')

def edit_refind(lines, var):
    hit = False
    for i, l in enumerate(lines):
        m = None if comment(l) else REFIND_LINE.match(l)
        if m:
            hit = True
            lines[i] = m.group(1) + strip(m.group(2)) + m.group(3)
    return 'ok' if hit else 'none'

EDITS = {'kcmdline': edit_kcmdline, 'entry': edit_entry, 'limine': edit_limine,
         'assign': edit_assign, 'refind': edit_refind}

# The command lines a file gives the kernel, for the modes whose meaning can be
# read here; the assign modes are checked through their own tool instead.
def units(mode, lines):
    if mode == 'kcmdline':
        return [kc_value(lines)]
    if mode == 'entry':
        return [entry_value(lines)]
    if mode == 'refind':
        return [m.group(2) for m in (REFIND_LINE.match(l) for l in lines if not comment(l)) if m]
    if mode == 'limine':
        return [' '.join(CMDLINE.match(lines[i]).group(2).strip() for i in cl) for cl in limine_entries(lines)]
    return None

# Line by line: a changed line must be the old one with only the words gone.
def only_dropped(old, new):
    if len(old) != len(new):
        return False
    for a, b in zip(old, new):
        if a != b and (strip(a) != b or not has_drop(a)):
            return False
    return True

cmd = sys.argv[1]
if cmd == 'edit':
    mode, src, dst = sys.argv[2:5]
    var = sys.argv[5] if len(sys.argv) > 5 else ''
    text, nl = load(src)
    if text is None:
        print('mixed')
        sys.exit(0)
    old = lines_of(text)
    new = list(old)
    status = EDITS[mode](new, var)
    if status != 'ok':
        print(status)
        sys.exit(0)
    if new == old:
        print('clean')
        sys.exit(0)
    if not only_dropped(old, new):
        print('unsafe')
        sys.exit(0)
    u_old, u_new = units(mode, old), units(mode, new)
    if u_old is not None and (len(u_old) != len(u_new)
                              or any(words(y) != without(words(x)) for x, y in zip(u_old, u_new))):
        print('unsafe')
        sys.exit(0)
    body = nl.join(new) + (nl if text.endswith('\n') else '')
    with open(dst, 'w', newline='') as f:
        f.write(body)
    print('removed')
elif cmd in ('limine-check', 'limine-snapshots'):
    # limine-check: every Linux entry of a generated limine.conf but the
    # snapshot ones - no word left. Prints the offending cmdline lines.
    # limine-snapshots: how many snapshot entries still have a word.
    text, nl = load(sys.argv[2])
    lines = lines_of(text or '')
    snaps = snapshot_starts(lines)
    def has_word(cl):
        return any(set(words(CMDLINE.match(lines[i]).group(2))) & set(DROP) for i in cl)
    if cmd == 'limine-snapshots':
        print(sum(1 for s, cl in limine_linux_entries(lines) if is_snapshot(lines, s, cl, snaps) and has_word(cl)))
        sys.exit(0)
    bad = [lines[i].strip() for s, cl in limine_linux_entries(lines) if not is_snapshot(lines, s, cl, snaps)
           for i in cl if set(words(CMDLINE.match(lines[i]).group(2))) & set(DROP)]
    print('\n'.join(bad))
    sys.exit(1 if bad else 0)
PY
)

# Command lines compared word for word, in order.
cmdline_minus() { tr -s ' \t\n' '\n' <<< "$1" | sed '/^$/d' | grep -vxE 'quiet|splash' | paste -sd' ' -; }
cmdline_norm()  { tr -s ' \t\n' '\n' <<< "$1" | sed '/^$/d' | paste -sd' ' -; }
cmdline_has_drop() { tr -s ' \t\n' '\n' <<< "$1" | grep -qxE 'quiet|splash'; }
# Is <after> exactly <before> without the two words?
cmdline_is_stripped() { [ "$(cmdline_norm "$2")" = "$(cmdline_minus "$1")" ]; }

# The value of <var> once <files> are sourced in a clean shell - how
# grub-mkconfig reads /etc/default/grub and /etc/default/grub.d.
shellvar_value() {
  local var="$1"
  shift
  env -i PATH=/usr/bin:/bin V="$var" bash -c 'for f; do if [ -r "$f" ]; then . "$f"; fi; done >/dev/null 2>&1 </dev/null
                                            printf "%s" "${!V-}"' _ "$@" 2>/dev/null
  return 0
}

_edited=()
_failed=false
_sources=0

# tb_edit <mode> <file> [<name regex>]: removes the words from <file> and sets
# _st to removed, clean, skip, foreign, undefined, none - or to why it could
# not: mixed, unsafe, error, failed. Read and written through sudo (the ESP is
# root-only on CachyOS). Always returns 0: Global_functions.sh sets -e.
tb_edit() {
  local mode="$1" file="$2" var="${3:-}"
  _st=failed
  sudo test -f "$file" || { _st=skip; return 0; }
  if ! sudo cat -- "$file" > "$TB_TMP/old" 2>>"$LOG"; then
    return 0
  fi
  rm -f "$TB_TMP/new"
  _st=$(python3 -c "$TB_PY" edit "$mode" "$TB_TMP/old" "$TB_TMP/new" "$var" 2>>"$LOG") || _st=error
  [ -n "$_st" ] || _st=error
  [ "$_st" = removed ] || return 0
  if ! sudo cp -- "$file" "$file.pre-text-boot" 2>>"$LOG" || ! sudo cmp -s -- "$TB_TMP/old" "$file.pre-text-boot"; then
    echo "${ERROR} Could not back up $file to $file.pre-text-boot - not editing it." | tee -a "$LOG"
    _st=failed
    return 0
  fi
  if sudo cp -- "$TB_TMP/new" "$file" 2>>"$LOG" && sudo cmp -s -- "$TB_TMP/new" "$file"; then
    _edited+=("$file")
  else
    sudo cp -- "$TB_TMP/old" "$file" 2>>"$LOG" || true
    _st=failed
  fi
  return 0
}

tb_undo() {
  local f
  for f in "$@"; do
    if [[ " ${_edited[*]} " == *" $f "* ]]; then
      sudo cp -- "$f.pre-text-boot" "$f" 2>>"$LOG" || true
    fi
  done
  return 0
}

# report <what> <status> [what to do by hand]
report() {
  local what="$1" st="$2" why
  case "$st" in
    skip|undefined|none) return 0 ;;
    foreign)
      echo "${NOTE} $what boots a kernel that is not installed here (another system on this ESP?) - left alone." | tee -a "$LOG"
      return 0 ;;
    clean)   echo "${OK} $what has neither 'quiet' nor 'splash'." | tee -a "$LOG" ;;
    removed) echo "${OK} Took 'quiet'/'splash' out of $what - the original is kept as $what.pre-text-boot." | tee -a "$LOG" ;;
    *)
      if [ -n "${3:-}" ]; then
        why="$3"
      else
        case "$st" in
          mixed)  why="it mixes CRLF and LF line endings" ;;
          unsafe) why="the edit would have changed more than those two words" ;;
          *)      why="see $LOG" ;;
        esac
      fi
      echo "${ERROR} Could not take 'quiet'/'splash' out of $what ($why). Remove them from the kernel command line there by hand." | tee -a "$LOG"
      _failed=true
      ;;
  esac
  _sources=$((_sources + 1))
  return 0
}

_need_rebuild=false

# /etc/kernel/cmdline: what mkinitcpio builds a UKI's command line from, and
# kernel-install writes loader entries from. First, because Limine's entry tool
# falls back to it.
tb_edit kcmdline /etc/kernel/cmdline
report /etc/kernel/cmdline "$_st"
[ "$_st" = removed ] && _need_rebuild=true

# Limine with its entry tool (CachyOS): the tool writes the kernel entries from
# KERNEL_CMDLINE - in /etc/default/limine, or /etc/limine-entry-tool.conf and its
# drop-ins - and rewrites them on every kernel update, so the words go out of
# there and the entries are then regenerated. The result is asked of the tool,
# kernel by kernel: each command line has to come out as before minus the words.
lt_cmdline() {
  sudo limine-entry-tool --get-cmdline "$1" 2>/dev/null | head -n 1
  return 0
}
_limine_conf=$(find_limine_conf) || _limine_conf=""
if [ -n "$_limine_conf" ] && command -v limine-entry-tool &>/dev/null; then
  declare -A _lt_before=()
  _lt_names="${TB_KERNELS:-default}"
  for _k in $_lt_names; do _lt_before[$_k]="$(lt_cmdline "$_k")"; done
  _lt_files=()
  for _f in /etc/default/limine /etc/limine-entry-tool.conf /etc/limine-entry-tool.d/*.conf; do
    sudo test -f "$_f" && _lt_files+=("$_f")
  done
  _lt_changed=()
  for _f in "${_lt_files[@]}"; do
    tb_edit assign "$_f" KERNEL_CMDLINE
    if [ "$_st" = removed ]; then
      _lt_changed+=("$_f")
    elif [ "$_st" != clean ] && [ "$_st" != undefined ]; then
      report "$_f" "$_st"
    fi
  done
  _lt_bad=""
  for _k in $_lt_names; do
    _after="$(lt_cmdline "$_k")"
    if [ -z "$_after" ] || ! cmdline_is_stripped "${_lt_before[$_k]}" "$_after"; then
      _lt_bad="$_k"
      break
    fi
  done
  if [ -n "$_lt_bad" ]; then
    tb_undo "${_lt_changed[@]}"
    report "limine-entry-tool's command line" failed \
      "for $_lt_bad it would be \"$_after\" instead of \"$(cmdline_minus "${_lt_before[$_lt_bad]}")\" - the files were put back. Edit KERNEL_CMDLINE in /etc/default/limine by hand, then run: sudo limine-mkinitcpio"
  elif [ ${#_lt_changed[@]} -gt 0 ]; then
    for _f in "${_lt_changed[@]}"; do report "$_f" removed; done
    _need_rebuild=true
  else
    report "limine-entry-tool's command line" clean
  fi
elif [ -n "$_limine_conf" ]; then
  # A limine.conf nothing generates (archinstall): the entries carry the line.
  tb_edit limine "$_limine_conf"
  report "$_limine_conf" "$_st"
fi

# systemd-boot: every entry that boots one of this system's kernels.
_entry_dirs=" "
for _esp in /boot /efi /boot/efi; do
  _d="$_esp/loader/entries"
  sudo test -d "$_d" || continue
  _real=$(sudo readlink -f -- "$_d" 2>/dev/null || echo "$_d")
  [[ "$_entry_dirs" == *" $_real "* ]] && continue
  _entry_dirs+="$_real "
  while IFS= read -r -d '' _entry <&3; do
    tb_edit entry "$_entry"
    report "$_entry" "$_st"
  done 3< <(sudo find "$_d" -maxdepth 1 -type f -name '*.conf' -print0 2>/dev/null)
done

# CachyOS's systemd-boot manager rewrites those entries from LINUX_OPTIONS on
# every kernel update, which would put the words straight back.
if [ -f /etc/sdboot-manage.conf ]; then
  _before=$(shellvar_value LINUX_OPTIONS /etc/sdboot-manage.conf)
  tb_edit assign /etc/sdboot-manage.conf LINUX_OPTIONS
  if [ "$_st" = removed ] && ! cmdline_is_stripped "$_before" "$(shellvar_value LINUX_OPTIONS /etc/sdboot-manage.conf)"; then
    tb_undo /etc/sdboot-manage.conf
    _st=unsafe
  fi
  report /etc/sdboot-manage.conf "$_st"
fi

# rEFInd.
for _rf in /boot/refind_linux.conf /efi/refind_linux.conf /boot/efi/refind_linux.conf; do
  if sudo test -f "$_rf"; then
    tb_edit refind "$_rf"
    report "$_rf" "$_st"
  fi
done

# GRUB: GRUB_CMDLINE_LINUX(_DEFAULT) in /etc/default/grub, then grub.cfg rebuilt
# from it - only when this run changed the file, with grub.cfg backed up first
# and both put back if grub-mkconfig fails or a 'linux' line of this system's
# entries still has a word.
if command -v grub-mkconfig &>/dev/null && [ -f /etc/default/grub ] && sudo test -f /boot/grub/grub.cfg; then
  _grub_cfg=/boot/grub/grub.cfg
  # A 'linux' line of this system's own entries that still has a word. Not
  # 30_os-prober's - another installed system's entries, with that system's own
  # command line - nor 40_custom's or 41_custom's, written by hand and copied in
  # as they are: none of them comes from GRUB_CMDLINE_LINUX*, so no edit here
  # can change them, and counted, a second Linux on the disk failed this check
  # on every run and put the correct edit back.
  grub_cfg_has_word() {
    sudo cat -- "$_grub_cfg" 2>/dev/null | awk '
      /^### BEGIN \/etc\/grub\.d\// { s = $3; sub(/.*\//, "", s) }
      /^### END \/etc\/grub\.d\// { s = "" }
      s == "30_os-prober" || s == "40_custom" || s == "41_custom" { next }
      /^[[:space:]]*linux[[:space:]].*[[:space:]](quiet|splash)([[:space:]]|$)/ { found = 1 }
      END { exit !found }'
  }
  _gv_before="$(shellvar_value GRUB_CMDLINE_LINUX /etc/default/grub /etc/default/grub.d/*.cfg) $(shellvar_value GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub /etc/default/grub.d/*.cfg)"
  tb_edit assign /etc/default/grub 'GRUB_CMDLINE_LINUX|GRUB_CMDLINE_LINUX_DEFAULT'
  if [ "$_st" = removed ]; then
    _gv_after="$(shellvar_value GRUB_CMDLINE_LINUX /etc/default/grub /etc/default/grub.d/*.cfg) $(shellvar_value GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub /etc/default/grub.d/*.cfg)"
    if ! cmdline_is_stripped "$_gv_before" "$_gv_after"; then
      tb_undo /etc/default/grub
      report /etc/default/grub failed "sourced the way grub-mkconfig reads it, the edit did not give \"$(cmdline_minus "$_gv_before")\" (is it also set in /etc/default/grub.d?) - put back"
    elif ! sudo cp -- "$_grub_cfg" "$_grub_cfg.pre-text-boot" 2>>"$LOG"; then
      tb_undo /etc/default/grub
      report /etc/default/grub failed "could not back up $_grub_cfg - put back"
    elif ! sudo grub-mkconfig -o "$_grub_cfg" >> "$LOG" 2>&1 || grub_cfg_has_word; then
      sudo cp -- "$_grub_cfg.pre-text-boot" "$_grub_cfg" 2>>"$LOG" || true
      tb_undo /etc/default/grub
      report /etc/default/grub failed "grub-mkconfig failed, or grub.cfg still has the words on a 'linux' line - both files were put back"
    else
      report /etc/default/grub removed
    fi
  elif grub_cfg_has_word && [ "$_st" = clean ]; then
    report "$_grub_cfg" failed "/etc/default/grub is clean but grub.cfg is older - run: sudo grub-mkconfig -o $_grub_cfg"
  else
    report /etc/default/grub "$_st"
  fi
fi

if [ "$_sources" -eq 0 ]; then
  if cmdline_has_drop "$(cat /proc/cmdline 2>/dev/null)"; then
    echo "${WARN} Found no kernel command line this script edits (EFISTUB, or a bootloader it does not know), and this boot has 'quiet' or 'splash'. Remove them from your bootloader's entry by hand." | tee -a "$LOG"
  else
    echo "${OK} This boot has neither 'quiet' nor 'splash', and there is no bootloader config here to change." | tee -a "$LOG"
  fi
fi

# No `kms` hook in the initramfs. It packs the GPU drivers (amdgpu, i915,
# nouveau...) into the image, so the driver takes the screen over while the LUKS
# prompt is up - on an RX 6700 XT that is ~2.5 s of black screen in the middle of
# typing the password. Without it the prompt stays on the firmware framebuffer
# and the driver loads from the root filesystem after the unlock; the blackout
# moves to among the [ OK ] lines. Only the splash needed the early driver.
# A drop-in, like plymouth.sh's, so deleting it puts the hook back.
TB_DROPIN=/etc/mkinitcpio.conf.d/zz-my_archinstaller-text-boot.conf
TB_DROPIN_BODY='# my_archinstaller text_boot (install-scripts/text-boot.sh): no `kms` hook, so
# the GPU driver loads after the disk is unlocked and its few seconds of black
# screen do not interrupt the LUKS password prompt. Delete this file and rebuild
# the initramfs to put it back.
_tb_hooks=()
for _tb_h in "${HOOKS[@]}"; do [ "$_tb_h" = kms ] || _tb_hooks+=("$_tb_h"); done
HOOKS=("${_tb_hooks[@]}")
unset _tb_hooks _tb_h'
if ! command -v mkinitcpio &>/dev/null; then
  : # booster/dracut: no HOOKS to change
elif mkinitcpio_has_hook kms; then
  if printf '%s\n' "$TB_DROPIN_BODY" > "$TB_TMP/dropin" \
     && sudo install -D -m 0644 -o root -g root "$TB_TMP/dropin" "$TB_DROPIN" 2>>"$LOG" \
     && ! mkinitcpio_has_hook kms; then
    echo "${OK} The 'kms' hook is out of the initramfs ($TB_DROPIN) - the GPU driver now loads after the disk is unlocked." | tee -a "$LOG"
    _need_rebuild=true
  else
    sudo rm -f -- "$TB_DROPIN" 2>>"$LOG" || true
    echo "${ERROR} Could not take the 'kms' hook out of the initramfs (see $LOG). The boot still works; the screen just goes black for a moment during the password prompt." | tee -a "$LOG"
    _failed=true
  fi
else
  echo "${OK} The initramfs has no 'kms' hook." | tee -a "$LOG"
fi

# Regenerate what carries the command line - Limine's entries
# (limine-mkinitcpio) and UKIs - and the image without kms. Only when this run
# changed one of them.
_rebuild_failed=false
if [ "$_need_rebuild" = true ]; then
  if ! rebuild_initramfs "$LOG"; then
    _rebuild_failed=true
    echo "${ERROR} The command line changed but the boot entries were not regenerated - the next boot still has 'quiet splash'. Run: sudo limine-mkinitcpio (CachyOS + Limine), else sudo mkinitcpio -P." | tee -a "$LOG"
  fi
fi

# The generated limine.conf itself, read back: what the next boot gets.
if [ -n "$_limine_conf" ] && [ "$_rebuild_failed" = false ] && command -v limine-entry-tool &>/dev/null; then
  if sudo cat -- "$_limine_conf" > "$TB_TMP/limine.conf" 2>>"$LOG" \
     && _left=$(python3 -c "$TB_PY" limine-check "$TB_TMP/limine.conf" 2>>"$LOG"); then
    _snaps=$(python3 -c "$TB_PY" limine-snapshots "$TB_TMP/limine.conf" 2>>"$LOG") || _snaps=0
    if [ "${_snaps:-0}" -gt 0 ] 2>/dev/null; then
      echo "${OK} No Limine entry in $_limine_conf has 'quiet' or 'splash', apart from $_snaps snapshot entr$([ "$_snaps" -eq 1 ] && echo y || echo ies): a snapshot boots the way the system was when it was taken, and those are left as they are." | tee -a "$LOG"
    else
      echo "${OK} No Limine entry in $_limine_conf has 'quiet' or 'splash'." | tee -a "$LOG"
    fi
  else
    echo "${ERROR} Limine entries in $_limine_conf still have 'quiet' or 'splash':" | tee -a "$LOG"
    printf '%s\n' "${_left:-(could not read it)}" | tee -a "$LOG"
    _failed=true
  fi
fi
sudo sync 2>/dev/null || true

# Recorded for the final check, which cannot see any of this: "text-boot" is
# not a pacman package, so only a later successful run takes it back out.
if [ "$_failed" = true ] || [ "$_rebuild_failed" = true ]; then
  record_package_failure "text-boot"
  printf "\n%.0s" {1..1}
  exit 1
fi
clear_package_failure "text-boot"
echo "${OK} The next boot shows the kernel and systemd messages." | tee -a "$LOG"
printf "\n%.0s" {1..1}
