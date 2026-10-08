#!/bin/bash
# Herdr - terminal workspace manager for AI coding agents.
#
# Herdr is NOT in the repos or the AUR. It is a single static binary published
# on GitHub and advertised through https://herdr.dev/latest.json, which carries
# both the per-platform download URL and its sha256. This script reads that
# manifest rather than pinning a version, so a fresh install always gets the
# current release; `herdr update` keeps it current afterwards.
#
# Everything on the desktop side is owned by the dotfiles and arrives with
# dotfiles-main.sh (which is why install.sh runs this script AFTER it):
#   - config/herdr/config.toml          keybindings, theme, sidebar rows, sounds
#   - config/herdr/sounds/*.mp3         done/request tones (freedesktop, -> mp3)
#   - .local/bin/herdr-goto-tab         focus-or-create tab, on CTRL+ALT+1..9
#   - .local/bin/herdr-close-workspace  ALT+Q popup: close workspace + worktree
#   - .local/bin/herdr-close-tab        ALT+C popup: close tab
#   - .local/bin/herdr-sync-workspace-numbers   one-shot $num token stamp
#   - .local/bin/herdr-watch-workspace-numbers  the daemon behind the unit below
#   - config/hypr/UserConfigs/UserKeybinds.lua  unbinds ALT+Tab so herdr gets it
#
# This script owns three things the dotfiles cannot:
#   1. the binary itself
#   2. the systemd --user unit (it names an absolute ExecStart)
#   3. rewriting __HOME__ in the copied config.toml
#
# On (3): herdr's [[keys.command]] entries take a command string, and a tracked
# dotfile cannot contain this machine's $HOME. The dotfiles ship __HOME__ and
# this script substitutes it in the *installed* copy. Re-running is safe - the
# sed is a no-op once there are no placeholders left.

herdr_pkg=(
  ffmpeg      # herdr shells out to a player for mp3 notification sounds
  libpulse    # provides paplay, the first player herdr looks for
)

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "[ERROR] Failed to change directory to $PARENT_DIR"; exit 1; }

if ! source "$SCRIPT_DIR/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_herdr.log"

printf "\n%s - Installing ${SKY_BLUE}Herdr${RESET} dependencies .... \n" "${NOTE}"
for PKG in "${herdr_pkg[@]}"; do
  install_package "$PKG" "$LOG"
done

# ---------------------------------------------------------------- the binary
BIN="$HOME/.local/bin/herdr"
mkdir -p "$HOME/.local/bin"

case "$(uname -m)" in
  x86_64)  HERDR_ASSET="linux-x86_64" ;;
  aarch64) HERDR_ASSET="linux-aarch64" ;;
  *) echo "${ERROR} Unsupported architecture $(uname -m) for Herdr." | tee -a "$LOG"
     record_package_failure "herdr"; exit 0 ;;
esac

printf "\n%s - Fetching ${SKY_BLUE}Herdr${RESET} release manifest .... \n" "${NOTE}"
# Downloads give up on a stall, not on a clock: --max-time caps the whole
# transfer, and at 300 s the ~56 MB hunk (~30 MB herdr) asset failed on any link
# under ~1.5 Mbit/s - every run, with no retry - while pacman fetched the other
# ~2 GB on the same link. Now: under 10 KB/s for a minute aborts, three retries.
# `|| MANIFEST=""`: Global_functions.sh runs `set -e`, and a bare assignment
# from a failing curl is a failing command - the script used to die right here,
# silently, before the skip branch below could record anything. That also
# skipped the __HOME__ substitution further down on a re-run, which copy.sh had
# just made necessary again.
MANIFEST=$(curl -fsSL --max-time 30 --retry 3 --retry-delay 5 --retry-all-errors https://herdr.dev/latest.json 2>>"$LOG") || MANIFEST=""
HERDR_VER="" HERDR_URL="" HERDR_SHA=""
if [ -n "$MANIFEST" ]; then
  read -r HERDR_VER HERDR_URL HERDR_SHA <<EOF2 || true
$(printf '%s' "$MANIFEST" | python3 -c "
import json,sys
d=json.load(sys.stdin); a='$HERDR_ASSET'
print(d['version'], d['assets'][a], d['sha256'][a])
" 2>>"$LOG")
EOF2
fi

if [ -z "$MANIFEST" ] || [ -z "$HERDR_URL" ]; then
  if [ -z "$MANIFEST" ]; then
    echo "${ERROR} Could not reach herdr.dev." | tee -a "$LOG"
  else
    echo "${ERROR} Herdr manifest had no $HERDR_ASSET asset." | tee -a "$LOG"
  fi
  if [ -x "$BIN" ]; then
    # Already installed: no download today, but the config below still needs
    # doing, so carry on instead of exiting.
    echo "${NOTE} Keeping the Herdr already at $BIN and configuring it." | tee -a "$LOG"
  else
    echo "${ERROR} Skipping Herdr." | tee -a "$LOG"
    record_package_failure "herdr"; exit 0
  fi
elif [ -x "$BIN" ] && [ "$("$BIN" --version 2>/dev/null | grep -oE "[0-9]+(\.[0-9]+)+" | head -n1)" = "$HERDR_VER" ]; then
  # Skip the download when the installed binary is already this version.
  echo "${OK} Herdr $HERDR_VER already installed." | tee -a "$LOG"
else
  printf "\n%s - Downloading ${SKY_BLUE}Herdr $HERDR_VER${RESET} .... \n" "${NOTE}"
  TMP=$(mktemp) || exit 0
  if curl -fsSL --connect-timeout 20 --speed-limit 10240 --speed-time 60 --retry 3 --retry-delay 5 --retry-all-errors -o "$TMP" "$HERDR_URL" 2>>"$LOG"; then
    # Verify before trusting it: this is a binary from outside the distro's
    # package manager, so the sha256 from the manifest is the only integrity
    # check there is. A mismatch means we do not install it at all.
    GOT=$(sha256sum "$TMP" | cut -d' ' -f1)
    if [ "$GOT" = "$HERDR_SHA" ]; then
      install -m 755 "$TMP" "$BIN"
      echo "${OK} Herdr $HERDR_VER installed to $BIN (sha256 verified)." | tee -a "$LOG"
    else
      echo "${ERROR} Herdr sha256 mismatch - expected $HERDR_SHA, got $GOT. NOT installed." | tee -a "$LOG"
      record_package_failure "herdr"
    fi
  else
    echo "${ERROR} Failed to download Herdr." | tee -a "$LOG"
    record_package_failure "herdr"
  fi
  rm -f "$TMP"
fi

# Installed and starting: take back a "herdr" an earlier failed run put in the
# failed-package list (the final check can only re-verify it through pacman,
# which does not know it). A failed update with the old binary still working
# is not "missing" either - its error is in the log.
if [ -x "$BIN" ] && "$BIN" --version >/dev/null 2>&1; then
  clear_package_failure "herdr"
fi

[ -x "$BIN" ] || { printf "\n%s Herdr binary missing - skipping configuration.\n" "${WARN}"; exit 0; }

# ------------------------------------------------- config from the dotfiles
CFG="$HOME/.config/herdr/config.toml"
if [ -f "$CFG" ]; then
  # __HOME__ -> the real home. See the header for why the dotfile is templated.
  # The binds are type = "shell" commands, so a home that needs quoting (a space:
  # /home/John Doe) goes in single-quoted - raw, every tab bind and ALT+Q ran
  # "/home/John" with arguments. TOML-escaped as well, since the commands sit in
  # double-quoted strings. An ordinary home goes in as it is.
  if grep -q '__HOME__' "$CFG"; then
    python3 - "$CFG" <<'PY'
import os, shlex, sys
p = sys.argv[1]
home = shlex.quote(os.path.expanduser("~")).replace("\\", "\\\\").replace('"', '\\"')
with open(p) as f:
    text = f.read()
with open(p, "w") as f:
    f.write(text.replace("__HOME__", home))
PY
    echo "${OK} Resolved __HOME__ paths in $CFG" | tee -a "$LOG"
  fi
  # Checked by herdr itself (`herdr --default-config` only prints the built-in
  # defaults). This used to be a TOML parse, and valid TOML is not enough: herdr
  # is installed unpinned, from latest.json, while config.toml is tracked here,
  # and on a key a release renamed or a value of another type it drops the
  # WHOLE config for its defaults - every bind and layout - while this said
  # [OK]. A config it drops ("using defaults") is recorded, so the final check
  # stops the reboot; other notes (a sound file it cannot find) are only shown.
  if _herdr_check=$("$BIN" config check 2>&1); then
    echo "${OK} Herdr config in place from the dotfiles (herdr config check: ok)." | tee -a "$LOG"
    clear_package_failure "herdr-config"
  elif grep -q 'using defaults' <<< "$_herdr_check"; then
    echo "${ERROR} herdr rejects $CFG and would start with its defaults:" | tee -a "$LOG"
    printf '%s\n' "$_herdr_check" | tee -a "$LOG"
    record_package_failure "herdr-config"
  else
    echo "${WARN} herdr config check has notes; the config is still used:" | tee -a "$LOG"
    printf '%s\n' "$_herdr_check" | tee -a "$LOG"
    clear_package_failure "herdr-config"
  fi
else
  echo "${WARN} $CFG not found - the dotfiles' herdr config did not arrive." | tee -a "$LOG"
  echo "${NOTE} Select the 'dots' option (or run install-scripts/dotfiles-main.sh)." | tee -a "$LOG"
fi

# --------------------------------------------- claude agent-state integration
# Reports Claude Code's session id to herdr so conversations resume into their
# native sessions after a server restart. Writes ~/.claude/hooks/ and adds a
# SessionStart hook to ~/.claude/settings.json; it is a no-op outside herdr.
if command -v claude >/dev/null 2>&1; then
  if "$BIN" integration status 2>/dev/null | grep -q '^claude: not installed'; then
    "$BIN" integration install claude >>"$LOG" 2>&1 \
      && echo "${OK} Herdr claude integration installed." | tee -a "$LOG" \
      || echo "${WARN} Herdr claude integration failed - see $LOG" | tee -a "$LOG"
  else
    echo "${OK} Herdr claude integration already present." | tee -a "$LOG"
  fi
fi

# ------------------------------------------------------- $num sidebar daemon
# Herdr has no built-in workspace-number token, so the sidebar reads a custom
# $num token from workspace metadata - and that metadata is NOT persisted across
# server restarts. This unit re-stamps it. Drop it if herdr ever grows a real
# number token; nothing else depends on it.
UNIT_DIR="$HOME/.config/systemd/user"
mkdir -p "$UNIT_DIR"
cat > "$UNIT_DIR/herdr-workspace-numbers.service" <<EOF
[Unit]
Description=Keep herdr \$num sidebar tokens in sync with live workspace numbering

[Service]
Type=simple
ExecStart=%h/.local/bin/herdr-watch-workspace-numbers
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

if [ -x "$HOME/.local/bin/herdr-watch-workspace-numbers" ]; then
  # Guarded: with no user bus (installer started through su/sudo -u) this
  # fails, and under set -e that used to end the script with nothing printed.
  systemctl --user daemon-reload 2>>"$LOG" || true
  systemctl --user enable --now herdr-workspace-numbers.service >>"$LOG" 2>&1 \
    && echo "${OK} herdr-workspace-numbers.service enabled." | tee -a "$LOG" \
    || echo "${WARN} Could not enable herdr-workspace-numbers.service - see $LOG" | tee -a "$LOG"
else
  echo "${WARN} herdr-watch-workspace-numbers missing (dotfiles); unit written but not enabled." | tee -a "$LOG"
fi

printf "\n${NOTE} ${SKY_BLUE}Herdr${RESET} installed. Run ${MAGENTA}herdr${RESET} to start. ${YELLOW}ALT+1..9${RESET} workspaces, ${YELLOW}ALT+TAB${RESET} tabs, ${YELLOW}ALT+HJKL${RESET} panes, ${YELLOW}ALT+W/ALT+Q${RESET} new/close workspace, ${YELLOW}ALT+B${RESET} previous workspace, ${YELLOW}CTRL+B ?${RESET} for everything else. Update later with ${MAGENTA}herdr update${RESET}.\n"
printf "\n%.0s" {1..2}
