#!/bin/bash
# Hunk - review-first terminal diff viewer for agent-authored changesets.
#
# This is the "read what the agents actually wrote" half. The agents report state
# in herdr's sidebar - working, done, blocked - but the sidebar says nothing about
# the code. `hunk diff --watch` renders the working tree as a review stream with a
# file sidebar and agent annotations beside the lines, and re-renders as the agent
# writes. The hds layout parks it in a permanent quadrant.
#
# Not in the repos or the AUR. Upstream's one-liner is `curl https://hunk.dev/
# install.sh | sh`, which this does not use: it installs to ~/.hunk, and piping an
# unread script into a shell is the one thing this repo does nowhere else. Instead
# we do what herdr.sh does - resolve the release from the GitHub API, verify the
# archive against the published SHA256SUMS, and install the binary to
# ~/.local/bin - so both out-of-band binaries arrive the same, checked way.
#
# The release is a tar.gz (unlike herdr's bare binary):
#   hunkdiff-linux-x64/
#     hunk            <- the binary; "hunk" is binaryName in metadata.json
#     metadata.json
#     skills/         <- bundled agent skills, reachable later via `hunk skill path`
#
# `hunk update` keeps it current afterwards.

hunk_pkg=(
  jq   # the herdr layout functions parse herdr's socket-API JSON with it
)

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "[ERROR] Failed to change directory to $PARENT_DIR"; exit 1; }

if ! source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_hunk.log"

printf "\n%s - Installing ${SKY_BLUE}Hunk${RESET} dependencies .... \n" "${NOTE}"
for PKG in "${hunk_pkg[@]}"; do
  install_package "$PKG" "$LOG"
done

BIN="$HOME/.local/bin/hunk"
mkdir -p "$HOME/.local/bin"

case "$(uname -m)" in
  x86_64)  HUNK_ASSET="hunkdiff-linux-x64.tar.gz" ;;
  aarch64) HUNK_ASSET="hunkdiff-linux-arm64.tar.gz" ;;
  *) echo "${ERROR} Unsupported architecture $(uname -m) for Hunk." | tee -a "$LOG"
     record_package_failure "hunk"; exit 0 ;;
esac

printf "\n%s - Resolving the latest ${SKY_BLUE}Hunk${RESET} release .... \n" "${NOTE}"
# `|| RELEASE=""`: Global_functions.sh runs `set -e`, so a failing curl in a bare
# assignment ended the script right here, silently - the skip branch below never
# ran and nothing was recorded. GitHub's unauthenticated rate limit (a 403) is
# enough to trigger it on a re-run.
RELEASE=$(curl -fsSL --max-time 30 https://api.github.com/repos/modem-dev/hunk/releases/latest 2>>"$LOG") || RELEASE=""
HUNK_VER="" HUNK_URL="" HUNK_SUMS=""
if [ -n "$RELEASE" ]; then
  read -r HUNK_VER HUNK_URL HUNK_SUMS <<EOF || true
$(printf '%s' "$RELEASE" | python3 -c "
import json,sys
d=json.load(sys.stdin); want='$HUNK_ASSET'
a={x['name']: x['browser_download_url'] for x in d.get('assets',[])}
print(d['tag_name'].lstrip('v'), a.get(want,''), a.get('SHA256SUMS',''))
" 2>>"$LOG")
EOF
fi

if [ -z "$HUNK_URL" ] || [ -z "$HUNK_SUMS" ]; then
  if [ -z "$RELEASE" ]; then
    echo "${ERROR} Could not reach the GitHub API." | tee -a "$LOG"
  else
    echo "${ERROR} Release had no $HUNK_ASSET or no SHA256SUMS." | tee -a "$LOG"
  fi
  if [ -x "$BIN" ]; then
    echo "${NOTE} Keeping the Hunk already at $BIN." | tee -a "$LOG"
  else
    echo "${ERROR} Skipping Hunk." | tee -a "$LOG"
    record_package_failure "hunk"; exit 0
  fi
# Already current? `hunk --version` prints a bare version, e.g. "0.22.0".
elif [ -x "$BIN" ] && [ "$("$BIN" --version 2>/dev/null | tr -d '[:space:]')" = "$HUNK_VER" ]; then
  echo "${OK} Hunk $HUNK_VER already installed." | tee -a "$LOG"
else
  printf "\n%s - Downloading ${SKY_BLUE}Hunk $HUNK_VER${RESET} .... \n" "${NOTE}"
  TMPD=$(mktemp -d) || exit 0
  if curl -fsSL --max-time 300 -o "$TMPD/$HUNK_ASSET" "$HUNK_URL" 2>>"$LOG" &&
     curl -fsSL --max-time 60 -o "$TMPD/SHA256SUMS" "$HUNK_SUMS" 2>>"$LOG"; then
    # Verify before trusting it. SHA256SUMS names the archive exactly, so run the
    # check from inside the directory with only that line - a missing or renamed
    # asset then fails the check instead of silently passing it.
    if ( cd "$TMPD" && grep -F " $HUNK_ASSET" SHA256SUMS | sha256sum -c - >/dev/null 2>&1 ); then
      if tar xzf "$TMPD/$HUNK_ASSET" -C "$TMPD" 2>>"$LOG"; then
        EXTRACTED=$(find "$TMPD" -type f -name hunk -perm -u+x | head -1)
        if [ -n "$EXTRACTED" ]; then
          install -m 755 "$EXTRACTED" "$BIN"
          echo "${OK} Hunk $HUNK_VER installed to $BIN (sha256 verified)." | tee -a "$LOG"
        else
          echo "${ERROR} No 'hunk' binary inside $HUNK_ASSET. NOT installed." | tee -a "$LOG"
          record_package_failure "hunk"
        fi
      else
        echo "${ERROR} Could not extract $HUNK_ASSET." | tee -a "$LOG"
        record_package_failure "hunk"
      fi
    else
      echo "${ERROR} Hunk sha256 mismatch against SHA256SUMS. NOT installed." | tee -a "$LOG"
      record_package_failure "hunk"
    fi
  else
    echo "${ERROR} Failed to download Hunk." | tee -a "$LOG"
    record_package_failure "hunk"
  fi
  rm -rf "$TMPD"
fi

[ -x "$BIN" ] || { printf "\n%s Hunk binary missing - nothing else to do.\n" "${WARN}"; exit 0; }

# The layout functions are dotfiles (config/zsh/herdr-layouts.zsh, sourced from
# .zshrc). Report rather than write: a file has one owner.
if [ -f "$HOME/.config/zsh/herdr-layouts.zsh" ]; then
  echo "${OK} herdr layout functions are in place (from the dotfiles)." | tee -a "$LOG"
else
  echo "${WARN} ~/.config/zsh/herdr-layouts.zsh not found - hds/hdl will not exist." | tee -a "$LOG"
  echo "${NOTE} Select the 'dots' option (or run install-scripts/dotfiles-main.sh)." | tee -a "$LOG"
fi

printf "\n${NOTE} ${SKY_BLUE}Hunk${RESET} installed. ${MAGENTA}hunk diff${RESET} reviews the working tree, ${MAGENTA}hunk diff --watch${RESET} re-renders as an agent writes, ${MAGENTA}hunk show${RESET} the last commit, ${MAGENTA}hunk log${RESET} the history. Inside herdr, ${YELLOW}hds${RESET} builds the square that keeps it on screen. Update later with ${MAGENTA}hunk update${RESET}.\n"
printf "\n%.0s" {1..2}
