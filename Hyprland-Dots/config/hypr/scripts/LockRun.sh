#!/usr/bin/env bash
# Start the lock screen, and record why it stops.
#
# hypridle's lock_cmd used to discard hyprlock's output, so when hyprlock quit
# mid-lock there was no record of it anywhere - the only evidence was
# Hyprland's "lockscreen app died" screen, and its runtime log is wiped at
# logout. This keeps the current and previous lock's output plus the exit code,
# which is the one datum that says whether hyprlock crashed or chose to quit.
#
# Called from hypridle.conf's lock_cmd, which fires on every
# `loginctl lock-session` (so also from scripts/LockScreen.sh).

LOGDIR="$HOME/.cache/hypr-logs"
LOG="$LOGDIR/hyprlock.log"
MAX_BYTES=$((4 * 1024 * 1024))

mkdir -p "$LOGDIR" 2>/dev/null

# Already locked: hypridle calls this on every lock-session, and a second
# hyprlock must never be started.
if pidof hyprlock >/dev/null 2>&1; then
    exit 0
fi

# Keep one previous generation, and never let either grow unbounded.
if [ -f "$LOG" ]; then
    mv -f "$LOG" "$LOG.1" 2>/dev/null
fi
for f in "$LOG.1"; do
    [ -f "$f" ] && [ "$(stat -c%s "$f" 2>/dev/null || echo 0)" -gt "$MAX_BYTES" ] \
        && : >"$f"
done

{
    echo "=== lock requested $(date -Is) ==="
    echo "--- SovietLockGen.py ---"
} >>"$LOG" 2>&1

# Size the widgets for whatever monitors are attached right now.
python3 "$HOME/.config/hypr/scripts/SovietLockGen.py" >>"$LOG" 2>&1
_gen_rc=$?
echo "  generator rc=$_gen_rc" >>"$LOG" 2>&1

# If the generator failed, the hyprlock-monitors.conf in place may name outputs this
# machine does not have (a black lock screen with no clock or input field). Keep only
# the FIRST monitor's block ("# ══ <name>" starts each one), then blank its monitor
# selectors so it applies to whatever monitor is present. Blanking every block of a
# multi-monitor file drew each monitor's clock and input field on every screen, on
# top of each other.
_lock_conf="$HOME/.config/hypr/hyprlock-monitors.conf"
if [ "$_gen_rc" -ne 0 ] && [ -f "$_lock_conf" ]; then
    awk '/^# ══ /{ n++ } n <= 1' "$_lock_conf" \
        | sed -E 's/^([[:space:]]*monitor[[:space:]]*=).*/\1/' >"$_lock_conf.tmp" \
        && mv "$_lock_conf.tmp" "$_lock_conf"
fi

echo "--- hyprlock ---" >>"$LOG" 2>&1
hyprlock >>"$LOG" 2>&1
rc=$?
echo "=== hyprlock exited rc=$rc at $(date -Is) ===" >>"$LOG" 2>&1
exit "$rc"
