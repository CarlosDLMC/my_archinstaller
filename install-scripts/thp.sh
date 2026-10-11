#!/bin/bash
# Transparent huge pages on request only (madvise), not for all memory.
#
# CachyOS's kernel is built with THP "always": every program's anonymous memory
# is backed by whole 2MB pages wherever the kernel can, even where the program
# only touches a little of each. For a desktop that is mostly overhead. Measured
# on the machine this repo was built from: the quickshell bar was 192MB fair
# share under "always" and 126MB under "madvise" (84MB of it had been huge
# pages), and the session read ~1.6GB at login before and ~1.35GB after.
# Programs that want huge pages - databases, the JVM, some games - still get
# them by asking (madvise), so nothing loses a feature.
#
# The setting lives in /sys and is gone at every boot, so it is a tmpfiles.d
# rule: `w!` writes it at boot only. It is applied right away as well (with
# --boot, or the `!` line is skipped), but memory already handed out stays in
# huge pages until the programs holding it restart - the next login.
# cachyos-settings' own thp.conf (defrag) and thp-shrinker.conf are left alone;
# this is a separate file. Re-running rewrites the same file and changes nothing.
## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "[ERROR] Failed to change directory to $PARENT_DIR"; exit 1; }
if ! source "$SCRIPT_DIR/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_thp.log"

THP=/sys/kernel/mm/transparent_hugepage/enabled
RULE=/etc/tmpfiles.d/thp-madvise.conf

printf "\n%s - Setting transparent huge pages to ${SKY_BLUE}madvise${RESET} \n" "${NOTE}"

if [ ! -e "$THP" ]; then
  echo "${NOTE} This kernel has no transparent huge pages ($THP) - nothing to do." | tee -a "$LOG"
  exit 0
fi

if ! sudo tee "$RULE" >/dev/null <<'EOF'
# Transparent huge pages only where a program asks for them (madvise), not for
# all anonymous memory - see install-scripts/thp.sh in my_archinstaller.
# Delete this file to go back to the kernel's default.
w! /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise
EOF
then
  echo "${ERROR} Could not write $RULE" | tee -a "$LOG"
  exit 1
fi
echo "${OK} Wrote $RULE (applied at every boot)." | tee -a "$LOG"

# The same command the boot runs, so this also proves the rule itself works.
if sudo systemd-tmpfiles --create --boot "$RULE" 2>&1 | tee -a "$LOG" \
   && grep -q '\[madvise\]' "$THP"; then
  echo "${OK} Transparent huge pages: $(cat "$THP"). Programs already running keep their huge pages until they restart." | tee -a "$LOG"
else
  echo "${WARN} The rule is in place but $THP reads '$(cat "$THP" 2>/dev/null)' - it will be set at the next boot." | tee -a "$LOG"
fi
