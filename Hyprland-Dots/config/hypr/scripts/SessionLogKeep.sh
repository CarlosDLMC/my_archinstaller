#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# Preserve the session's log across logout.
#
# Two logs vanish exactly when you need them:
#   - Hyprland's own log lives in $XDG_RUNTIME_DIR, cleared when the last
#     session ends.
#   - ly writes the session's stdout/stderr to ~/.local/state/ly-session.log,
#     but TRUNCATES it at every login, so a session that died last night is
#     unreadable this morning.
# This mirrors ly's log into ~/.cache/hypr-logs/ and keeps the previous
# session's copy, so a crash can still be read after logging back in.
#
# Cheap: one `tail -F`, no polling. Note Hyprland writes little here unless
# `debug { disable_logs = false }` is set - abort/stderr messages still land.
#
# Started from configs/Startup_Apps.lua (hyprland.start handler).

LOGDIR="$HOME/.cache/hypr-logs"
SRC="$HOME/.local/state/ly-session.log"
DST="$LOGDIR/session.log"
MAX_BYTES=$((8 * 1024 * 1024))

mkdir -p "$LOGDIR" 2>/dev/null

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

# -F survives ly truncating or recreating the file.
exec tail -n +1 -F "$SRC" >>"$DST" 2>/dev/null
