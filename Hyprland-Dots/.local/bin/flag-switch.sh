#!/usr/bin/env bash
# Switch which flag ly draws, and whether it waves, or report the current one.
#
#   ./flag-switch.sh              # print which flag and variant are active
#   ./flag-switch.sh sweden       # switch flag, keep the current variant
#   ./flag-switch.sh static       # switch to the still flag, same flag
#   ./flag-switch.sh norway animated       # both at once, in either order
#   ./flag-switch.sh static --live-only    # change /etc/ly, leave the repo alone
#
# The flags are whatever /etc/ly/<name>-flag-animated.dur files
# install-scripts/ly_config.sh installed; run with no arguments to list them.
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
# The installer takes the flag from the preset's ly_flag (the variant still
# comes from config.ini), so that line is kept in step as well.
REPO_PRESET="${LY_REPO_PRESET:-$(dirname "$(dirname "$(dirname "$REPO_CONFIG")")")/custom-preset.conf}"
LIVE_CONFIG=/etc/ly/config.ini

# "flag variant" from the live dur_file_path line, e.g. "soviet animated".
current() {
    sed -n 's#^dur_file_path *=.*/\([a-z]*\)-flag-\([a-z]*\)\.dur.*#\1 \2#p' "$1" | head -1
}

flags() {
    local f
    for f in /etc/ly/*-flag-animated.dur; do
        [ -r "$f" ] || continue
        f="${f##*/}"; echo "${f%-flag-animated.dur}"
    done
}

if [ $# -eq 0 ]; then
    live=$(current "$LIVE_CONFIG")
    echo "active (/etc/ly):  ${live:-unknown}"
    echo "flags installed:   $(flags | paste -sd' ' -)"
    if [ -r "$REPO_CONFIG" ]; then
        repo=$(current "$REPO_CONFIG")
        echo "repo   (assets):   ${repo:-unknown}"
        [ "$live" = "$repo" ] || echo "note: these disagree - a reinstall would switch you to '$repo'"
    else
        echo "repo   (assets):   not found at $REPO_CONFIG"
    fi
    exit 0
fi

read -r FLAG TARGET <<< "$(current "$LIVE_CONFIG")"
FLAG="${FLAG:-soviet}"; TARGET="${TARGET:-animated}"
LIVE_ONLY=false
for arg in "$@"; do
    case "$arg" in
        static|animated) TARGET="$arg" ;;
        --live-only) LIVE_ONLY=true ;;
        *)
            if flags | grep -qx -- "$arg"; then
                FLAG="$arg"
            else
                echo "usage: $0 [flag] [static|animated] [--live-only]" >&2
                echo "flags: $(flags | paste -sd' ' -)" >&2
                exit 2
            fi
            ;;
    esac
done

[ -r "/etc/ly/$FLAG-flag-$TARGET.dur" ] || {
    echo "missing /etc/ly/$FLAG-flag-$TARGET.dur - run install-scripts/ly_config.sh" >&2
    exit 1
}

# Rewrite both dur_file_path lines in place: the chosen one live, the other
# commented out. Done as a rewrite rather than a comment toggle so running
# this twice cannot end up with two active lines or none.
rewrite() {
    local file="$1" sudo_cmd="$2" tmp
    tmp=$(mktemp)
    awk -v flag="$FLAG" -v target="$TARGET" '
        /^[# ]*dur_file_path *=.*-flag-[a-z]+\.dur/ {
            match($0, /-flag-[a-z]+\.dur/)
            variant = substr($0, RSTART + 6, RLENGTH - 10)
            if (variant == target)
                print "dur_file_path = /etc/ly/" flag "-flag-" target ".dur"
            else
                print "# dur_file_path = /etc/ly/" flag "-flag-" variant ".dur"
            next
        }
        { print }
    ' "$file" > "$tmp"
    grep -q "^dur_file_path *=.*/$FLAG-flag-$TARGET\.dur" "$tmp" || {
        rm -f "$tmp"; echo "refusing to write $file: no dur_file_path line found" >&2; exit 1
    }
    $sudo_cmd cp "$tmp" "$file"
    rm -f "$tmp"
}

rewrite "$LIVE_CONFIG" sudo

if $LIVE_ONLY; then
    echo "ly will now draw: $FLAG $TARGET  (/etc/ly only)"
elif [ -w "$REPO_CONFIG" ]; then
    rewrite "$REPO_CONFIG" ""
    if [ -w "$REPO_PRESET" ] && grep -q '^ly_flag=' "$REPO_PRESET"; then
        sed -i "s/^ly_flag=.*/ly_flag=\"$FLAG\"/" "$REPO_PRESET"
    fi
    echo "ly will now draw: $FLAG $TARGET  (/etc/ly and the repo)"
else
    echo "ly will now draw: $FLAG $TARGET  (/etc/ly only)"
    echo "repo config not writable at $REPO_CONFIG - a reinstall would revert this"
fi
echo "preview it without logging out:  flag-preview.sh $FLAG $TARGET"
