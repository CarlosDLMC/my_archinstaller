#!/usr/bin/env bash
# Run a key bind's command once per key press.
#
#   Once.sh -d DISPATCHER [ARGS...]   mmsg dispatch DISPATCHER,ARG1,ARG2,...
#   Once.sh COMMAND [ARGS...]         COMMAND ARGS...
#
# mango repeats every key bind while its key is held; Hyprland only repeated
# the binds marked as repeating. Held a moment too long, SUPER+Q closed a
# second window and SUPER+1 flipped between two workspaces (view goes back to
# the previous workspace when asked for the current one). keybinds.conf sends
# every bind that must fire once per press through this script.
#
# The repeats follow the keyboard's repeat settings (settings.conf): the first
# comes repeat_delay (300 ms) after the press, then one every 1000 / repeat_rate
# (20 ms). So a call with the same arguments as the previous one less than
# 40 ms after it is a repeat and is dropped. One 280-330 ms after it is the
# first repeat - or the same key pressed again at just that moment: it waits
# 45 ms, and runs unless another call came in meanwhile (a held key repeats
# 20 ms later). Anything else - another key, the same key again - runs.

REPEAT_DELAY_MS=300
REPEAT_GAP_MS=40

dir="${XDG_RUNTIME_DIR:-/tmp}/mango-once"
[ -d "$dir" ] || mkdir -p "$dir"
key="${*//[^A-Za-z0-9]/_}"
stamp="$dir/${key:0:200}"

# EPOCHREALTIME is seconds.microseconds; the separator follows LC_NUMERIC.
now=${EPOCHREALTIME/[.,]/}
now=$((10#$now / 1000))
last=0
[ -f "$stamp" ] && read -r last <"$stamp"
echo "$now" >"$stamp"

gap=$((now - ${last:-0}))
if ((gap < REPEAT_GAP_MS)); then
    exit 0
fi
if ((gap > REPEAT_DELAY_MS - 20 && gap < REPEAT_DELAY_MS + 30)); then
    sleep 0.045
    read -r latest <"$stamp"
    [ "$latest" = "$now" ] || exit 0
fi

if [ "$1" = -d ]; then
    shift
    IFS=,
    exec mmsg dispatch "$*" >/dev/null
fi
exec "$@"
