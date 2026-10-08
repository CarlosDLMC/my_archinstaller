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
# archive against the published SHA256SUMS, and install into ~/.local/bin - so
# both out-of-band binaries arrive the same, checked way.
#
# The release is a tar.gz (unlike herdr's bare binary):
#   hunkdiff-linux-x64/
#     hunk            <- the binary; "hunk" is binaryName in metadata.json
#     metadata.json
#     skills/         <- bundled agent skills; `hunk skill path` prints one
#
# The whole tree is kept, as ~/.local/bin/.hunk-release/, and ~/.local/bin/hunk
# is a symlink into it. hunk finds its skills by walking up from its own binary
# (symlinks resolved) looking for skills/<name>/SKILL.md, so the bare binary this
# used to install had none: `hunk skill path` failed with "Could not locate the
# bundled Hunk hunk-review skill".
#
# Why inside ~/.local/bin and not ~/.local/share/hunk: hunk works out how it was
# installed from the real path of its binary. Under ~/.local/bin it takes itself
# for a local source build - it shows no update notices, and `hunk update` only
# prints advice. Anywhere else in $HOME it takes itself for an npm install: it
# shows "Update available ... run `hunk update`" at startup, and `hunk update`
# then runs `npm install --global hunkdiff`, which leaves a second, separate hunk
# under npm's prefix while this one stays old. So neither place makes
# `hunk update` work - update by re-running this script.

hunk_pkg=(
  jq   # the herdr layout functions parse herdr's socket-API JSON with it
)

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "[ERROR] Failed to change directory to $PARENT_DIR"; exit 1; }

if ! source "$SCRIPT_DIR/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_hunk.log"

printf "\n%s - Installing ${SKY_BLUE}Hunk${RESET} dependencies .... \n" "${NOTE}"
for PKG in "${hunk_pkg[@]}"; do
  install_package "$PKG" "$LOG"
done

BIN="$HOME/.local/bin/hunk"
# The release tree $BIN points into - see the header for why it lives here.
REL="$HOME/.local/bin/.hunk-release"
mkdir -p "$HOME/.local/bin"

# A run interrupted inside the swap below leaves the previous tree parked at
# .old - put it back so the symlink resolves again. A half-extracted .new is
# simply dropped (the binary alone is ~160 MB).
if [ ! -e "$REL" ] && [ -d "$REL.old" ]; then
  mv -T "$REL.old" "$REL" || true
fi
rm -rf "$REL.new" "$REL.old"

case "$(uname -m)" in
  x86_64)  HUNK_ASSET="hunkdiff-linux-x64.tar.gz" ;;
  aarch64) HUNK_ASSET="hunkdiff-linux-arm64.tar.gz" ;;
  *) echo "${ERROR} Unsupported architecture $(uname -m) for Hunk." | tee -a "$LOG"
     record_package_failure "hunk"; exit 0 ;;
esac

printf "\n%s - Resolving the latest ${SKY_BLUE}Hunk${RESET} release .... \n" "${NOTE}"
# Downloads give up on a stall, not on a clock: --max-time caps the whole
# transfer, and at 300 s the ~56 MB hunk (~30 MB herdr) asset failed on any link
# under ~1.5 Mbit/s - every run, with no retry - while pacman fetched the other
# ~2 GB on the same link. Now: under 10 KB/s for a minute aborts, three retries.
# `|| RELEASE=""`: Global_functions.sh runs `set -e`, so a failing curl in a bare
# assignment ended the script right here, silently - the skip branch below never
# ran and nothing was recorded. GitHub's unauthenticated rate limit (a 403) is
# enough to trigger it on a re-run.
RELEASE=$(curl -fsSL --max-time 30 --retry 3 --retry-delay 5 --retry-all-errors https://api.github.com/repos/modem-dev/hunk/releases/latest 2>>"$LOG") || RELEASE=""
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
# Already current? `hunk --version` prints a bare version, e.g. "0.22.0". Only
# in the release-tree layout: earlier versions of this script left a bare binary
# with no skills beside it, and a matching version number must not keep that.
elif [ -x "$BIN" ] && [ -d "$REL/skills" ] &&
     [ "$(readlink -f "$BIN")" = "$(readlink -f "$REL/hunk")" ] &&
     [ "$("$BIN" --version 2>/dev/null | tr -d '[:space:]')" = "$HUNK_VER" ]; then
  echo "${OK} Hunk $HUNK_VER already installed." | tee -a "$LOG"
else
  printf "\n%s - Downloading ${SKY_BLUE}Hunk $HUNK_VER${RESET} .... \n" "${NOTE}"
  TMPD=$(mktemp -d) || exit 0
  if curl -fsSL --connect-timeout 20 --speed-limit 10240 --speed-time 60 --retry 3 --retry-delay 5 --retry-all-errors -o "$TMPD/$HUNK_ASSET" "$HUNK_URL" 2>>"$LOG" &&
     curl -fsSL --max-time 60 --retry 3 --retry-delay 5 --retry-all-errors -o "$TMPD/SHA256SUMS" "$HUNK_SUMS" 2>>"$LOG"; then
    # Verify before trusting it. SHA256SUMS names the archive exactly, so run the
    # check from inside the directory with only that line - a missing or renamed
    # asset then fails the check instead of silently passing it. The whole line
    # is matched (hash, text or binary marker, exact name): a substring match
    # would also pick up e.g. "$HUNK_ASSET.sig", and sha256sum -c then fails a
    # good download on the file that was never fetched.
    _asset_re=$(printf '%s' "$HUNK_ASSET" | sed 's/[.[\*^$]/\\&/g')
    if ( cd "$TMPD" && grep -E "^[0-9a-fA-F]{64} [ *]${_asset_re}\$" SHA256SUMS | sha256sum -c - >/dev/null 2>&1 ); then
      # Extracted next to the live tree rather than into $TMPD: /tmp is a tmpfs,
      # and only a rename within one filesystem swaps a whole tree in one step.
      if mkdir -p "$REL.new" && tar xzf "$TMPD/$HUNK_ASSET" -C "$REL.new" 2>>"$LOG"; then
        EXTRACTED=$(find "$REL.new" -type f -name hunk -perm -u+x | head -1)
        if [ -n "$EXTRACTED" ]; then
          # Old tree aside, new tree in, then the link. A hunk running right now
          # keeps the binary it has open, and the only moment with no tree at all
          # is between two renames. `ln -sfn` also replaces the bare binary that
          # earlier versions of this script installed at $BIN; the link is
          # relative, so it survives the home directory moving.
          if { [ ! -e "$REL" ] || mv -T "$REL" "$REL.old"; } &&
             mv -T "$(dirname "$EXTRACTED")" "$REL" &&
             ln -sfn .hunk-release/hunk "$BIN"; then
            rm -rf "$REL.old"
            echo "${OK} Hunk $HUNK_VER installed to $REL, linked from $BIN (sha256 verified)." | tee -a "$LOG"
          else
            # Put the previous tree back rather than leave $BIN dangling.
            if [ ! -e "$REL" ] && [ -d "$REL.old" ]; then mv -T "$REL.old" "$REL" || true; fi
            echo "${ERROR} Could not move Hunk $HUNK_VER into $REL. NOT installed." | tee -a "$LOG"
            record_package_failure "hunk"
          fi
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
  rm -rf "$TMPD" "$REL.new"
fi

# Installed and starting: take back a "hunk" an earlier failed run put in the
# failed-package list (see the same step in herdr.sh).
if [ -x "$BIN" ] && "$BIN" --version >/dev/null 2>&1; then
  clear_package_failure "hunk"
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

printf "\n${NOTE} ${SKY_BLUE}Hunk${RESET} installed. ${MAGENTA}hunk diff${RESET} reviews the working tree, ${MAGENTA}hunk diff --watch${RESET} re-renders as an agent writes, ${MAGENTA}hunk show${RESET} the last commit, ${MAGENTA}hunk log${RESET} the history. Inside herdr, ${YELLOW}hds${RESET} builds the square that keeps it on screen. ${MAGENTA}hunk skill path${RESET} prints the bundled review skill for your agent. Update later by re-running ${MAGENTA}install-scripts/hunk.sh${RESET} - not ${MAGENTA}hunk update${RESET}, which does not recognise this install.\n"
printf "\n%.0s" {1..2}
