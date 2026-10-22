#!/usr/bin/env bash
# Preserve the session's log across logout.
#
# Two logs vanish exactly when you need them:
#   - ly writes the session's stdout/stderr - mango's log included, mango
#     logs to stderr - to ~/.local/state/ly-session.log,
#     but TRUNCATES it at every login, so a session that died last night is
#     unreadable this morning.
# This mirrors ly's log into ~/.cache/hypr-logs/ and keeps the previous
# session's copy, so a crash can still be read after logging back in.
#
# Cheap: one `tail -F`, no polling.
#
# Started from ~/.config/mango/startup.conf.

LOGDIR="$HOME/.cache/hypr-logs"
SRC="$HOME/.local/state/ly-session.log"
DST="$LOGDIR/session.log"
MAX_BYTES=$((8 * 1024 * 1024))

mkdir -p "$LOGDIR" 2>/dev/null

# A mirror left over from the last session. Nothing ever ended one: it kept
# appending this session to session.log.1, and every login added another.
for _old in $(pgrep -u "$UID" -f "^tail -n \+1 -F( --pid=[0-9]+)? $SRC\$"); do
    kill "$_old" 2>/dev/null
done

# This session's mirror becomes last session's copy.
if [ -f "$DST" ]; then
    mv -f "$DST" "$DST.1" 2>/dev/null
fi
if [ -f "$DST.1" ] && [ "$(stat -c%s "$DST.1" 2>/dev/null || echo 0)" -gt "$MAX_BYTES" ]; then
    : >"$DST.1"
fi

{
    echo "=== session started $(date -Is) ==="
    echo "=== mirroring $SRC ==="
} >"$DST" 2>/dev/null

# ly may not have created the file yet on a very fast login.
for _ in $(seq 1 20); do
    [ -f "$SRC" ] && break
    sleep 0.5
done
[ -f "$SRC" ] || { echo "=== $SRC never appeared ===" >>"$DST"; exit 0; }

# -F survives ly truncating or recreating the file; --pid ends the mirror with
# this mango (GNU tail checks every second). Its pid is in the name of its IPC
# socket, $XDG_RUNTIME_DIR/mango-<pid>.sock - not $PPID: mango double-forks
# what it starts.
mango_pid=${MANGO_INSTANCE_SIGNATURE##*/mango-}
mango_pid=${mango_pid%.sock}
if [[ "$mango_pid" =~ ^[0-9]+$ ]] && kill -0 "$mango_pid" 2>/dev/null; then
    exec tail -n +1 -F --pid="$mango_pid" "$SRC" >>"$DST" 2>/dev/null
fi
exec tail -n +1 -F "$SRC" >>"$DST" 2>/dev/null
