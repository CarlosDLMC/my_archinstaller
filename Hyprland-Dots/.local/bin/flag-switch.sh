#!/usr/bin/env bash
# Switch which soviet flag ly draws, or report the current one.
#
#   ./flag-switch.sh              # print which variant is active
#   ./flag-switch.sh static       # switch to the still flag
#   ./flag-switch.sh animated     # switch to the waving flag
#   ./flag-switch.sh static --live-only    # change /etc/ly, leave the repo alone
#
# Both config.ini files are rewritten by default - the repo one as well as the
# installed one - so the repo stays the source of truth and a reinstall does
# not silently revert your choice. That leaves a one-line git diff to commit.
#
# The change is picked up the next time ly starts. It does not disturb the
# running greeter, so nothing happens to your current session.

set -euo pipefail

# This script lives outside the rice repo (deliberately not committed), so the
# repo config is found by absolute path rather than relative to the script.
# Override with LY_REPO_CONFIG if the repo ever moves.
REPO_CONFIG="${LY_REPO_CONFIG:-$HOME/Documents/my_archinstaller/assets/ly/config.ini}"
LIVE_CONFIG=/etc/ly/config.ini

current() {
    sed -n 's#^dur_file_path *=.*soviet-flag-\([a-z]*\)\.dur.*#\1#p' "$1" | head -1
}

if [ $# -eq 0 ]; then
    live=$(current "$LIVE_CONFIG")
    echo "active (/etc/ly):  ${live:-unknown}"
    if [ -r "$REPO_CONFIG" ]; then
        repo=$(current "$REPO_CONFIG")
        echo "repo   (assets):   ${repo:-unknown}"
        [ "$live" = "$repo" ] || echo "note: these disagree - a reinstall would switch you to '$repo'"
    else
        echo "repo   (assets):   not found at $REPO_CONFIG"
    fi
    exit 0
fi

TARGET="$1"; shift
LIVE_ONLY=false
[ "${1:-}" = "--live-only" ] && LIVE_ONLY=true

case "$TARGET" in
    static|animated) ;;
    *) echo "usage: $0 [static|animated] [--live-only]" >&2; exit 2 ;;
esac

[ -r "/etc/ly/soviet-flag-$TARGET.dur" ] || {
    echo "missing /etc/ly/soviet-flag-$TARGET.dur - run install-scripts/ly_config.sh" >&2
    exit 1
}

# Rewrite both dur_file_path lines in place: the chosen one live, the other
# commented out. Done as a rewrite rather than a comment toggle so running
# this twice cannot end up with two active lines or none.
rewrite() {
    local file="$1" sudo_cmd="$2" tmp
    tmp=$(mktemp)
    awk -v target="$TARGET" '
        /^[# ]*dur_file_path *=.*soviet-flag-/ {
            if ($0 ~ ("soviet-flag-" target "\\.dur"))
                print "dur_file_path = /etc/ly/soviet-flag-" target ".dur"
            else {
                match($0, /soviet-flag-[a-z]+\.dur/)
                print "# dur_file_path = /etc/ly/" substr($0, RSTART, RLENGTH)
            }
            next
        }
        { print }
    ' "$file" > "$tmp"
    grep -q "^dur_file_path *=.*soviet-flag-$TARGET\.dur" "$tmp" || {
        rm -f "$tmp"; echo "refusing to write $file: no dur_file_path line found" >&2; exit 1
    }
    $sudo_cmd cp "$tmp" "$file"
    rm -f "$tmp"
}

rewrite "$LIVE_CONFIG" sudo

if $LIVE_ONLY; then
    echo "ly will now draw: $TARGET  (/etc/ly only)"
elif [ -w "$REPO_CONFIG" ]; then
    rewrite "$REPO_CONFIG" ""
    echo "ly will now draw: $TARGET  (/etc/ly and the repo)"
else
    echo "ly will now draw: $TARGET  (/etc/ly only)"
    echo "repo config not writable at $REPO_CONFIG - a reinstall would revert this"
fi
echo "preview it without logging out:  flag-preview.sh $TARGET"
