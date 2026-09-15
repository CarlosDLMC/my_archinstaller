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
cd "$PARENT_DIR" || { echo "${ERROR} Failed to change directory to $PARENT_DIR"; exit 1; }

if ! source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"; then
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
MANIFEST=$(curl -fsSL --max-time 30 https://herdr.dev/latest.json 2>>"$LOG")
if [ -z "$MANIFEST" ]; then
  echo "${ERROR} Could not reach herdr.dev - skipping Herdr." | tee -a "$LOG"
  record_package_failure "herdr"; exit 0
fi

read -r HERDR_VER HERDR_URL HERDR_SHA <<EOF
$(printf '%s' "$MANIFEST" | python3 -c "
import json,sys
d=json.load(sys.stdin); a='$HERDR_ASSET'
print(d['version'], d['assets'][a], d['sha256'][a])
" 2>>"$LOG")
EOF

if [ -z "$HERDR_URL" ]; then
  echo "${ERROR} Herdr manifest had no $HERDR_ASSET asset - skipping." | tee -a "$LOG"
  record_package_failure "herdr"; exit 0
fi

# Skip the download when the installed binary is already this version.
if [ -x "$BIN" ] && "$BIN" --version 2>/dev/null | grep -q "$HERDR_VER"; then
  echo "${OK} Herdr $HERDR_VER already installed." | tee -a "$LOG"
else
  printf "\n%s - Downloading ${SKY_BLUE}Herdr $HERDR_VER${RESET} .... \n" "${NOTE}"
  TMP=$(mktemp) || exit 0
  if curl -fsSL --max-time 300 -o "$TMP" "$HERDR_URL" 2>>"$LOG"; then
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

[ -x "$BIN" ] || { printf "\n%s Herdr binary missing - skipping configuration.\n" "${WARN}"; exit 0; }

# ------------------------------------------------- config from the dotfiles
CFG="$HOME/.config/herdr/config.toml"
if [ -f "$CFG" ]; then
  # __HOME__ -> the real home. See the header for why the dotfile is templated.
  if grep -q '__HOME__' "$CFG"; then
    sed -i "s#__HOME__#$HOME#g" "$CFG"
    echo "${OK} Resolved __HOME__ paths in $CFG" | tee -a "$LOG"
  fi
  if "$BIN" --default-config >/dev/null 2>&1; then
    echo "${OK} Herdr config in place from the dotfiles." | tee -a "$LOG"
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
  systemctl --user daemon-reload 2>>"$LOG"
  systemctl --user enable --now herdr-workspace-numbers.service >>"$LOG" 2>&1 \
    && echo "${OK} herdr-workspace-numbers.service enabled." | tee -a "$LOG" \
    || echo "${WARN} Could not enable herdr-workspace-numbers.service - see $LOG" | tee -a "$LOG"
else
  echo "${WARN} herdr-watch-workspace-numbers missing (dotfiles); unit written but not enabled." | tee -a "$LOG"
fi

printf "\n${NOTE} ${SKY_BLUE}Herdr${RESET} installed. Run ${MAGENTA}herdr${RESET} to start. ${YELLOW}ALT+1..9${RESET} workspaces, ${YELLOW}ALT+TAB${RESET} tabs, ${YELLOW}ALT+HJKL${RESET} panes, ${YELLOW}ALT+N/ALT+Q${RESET} new/close workspace, ${YELLOW}CTRL+B ?${RESET} for everything else. Update later with ${MAGENTA}herdr update${RESET}.\n"
printf "\n%.0s" {1..2}
