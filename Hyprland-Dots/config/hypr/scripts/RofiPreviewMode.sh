#!/usr/bin/env bash
# The window side of the launcher's preview mode (RofiFiles.sh, Shift+Enter in
# the ФАЙЛЫ tab).
#
#   RofiPreviewMode.sh on ROFI_PID
#   RofiPreviewMode.sh off
#
# While it is on, every window that opens floats in the left third of the
# screen beside the launcher (31% x 60% at 1% / 20%), without taking the
# keyboard from it and without animations, and closes the preview before it -
# one preview at a time. It ends with Shift+Enter again or when rofi closes;
# its window goes with it.
#
# mango has no window rule that can be switched on and off, so "on" adds one
# while it runs (setoption window_rule) and the end reloads the config, which
# drops it. A watcher stands in for Hyprland's window.open / layer.closed
# hooks: it closes the previous preview when the next window maps, and ends
# the mode when rofi exits.

run="${XDG_RUNTIME_DIR:-/tmp}"
watch_pid_file="$run/rofi-preview-watch.pid"
rule="is_floating:1,is_open_silent:1,no_animation:1,animation_type_open:none,animation_type_close:none,width:0.31,height:0.6,offset_x:-98,offset_y:-4,app_id:.*"

ids() { mmsg get all-clients | jq -r '.clients[].id' | sort -n; }

watch() { # rofi_pid
    local rofi=$1 known current="" line new mpid rc
    exec 3< <(mmsg watch all-clients 2>/dev/null)
    mpid=$!
    known=$(ids)
    finish() {
        [ -n "$current" ] && mmsg dispatch killclient "client,$current" >/dev/null 2>&1
        mmsg dispatch reload_config >/dev/null 2>&1
        kill "$mpid" 2>/dev/null
        rm -f "$watch_pid_file"
        exit 0
    }
    trap finish TERM INT
    while kill -0 "$rofi" 2>/dev/null; do
        # One full client list per change; poll rofi between changes. A
        # timeout is over 128; anything else is the stream gone - wait.
        read -r -t 0.5 line <&3
        rc=$?
        if ((rc)); then
            ((rc > 128)) || sleep 0.5
            continue
        fi
        new=$(jq -r '.clients[].id' <<<"$line" 2>/dev/null | sort -n | comm -13 <(printf '%s\n' "$known") -)
        known=$(jq -r '.clients[].id' <<<"$line" 2>/dev/null | sort -n)
        for id in $new; do
            [ -n "$current" ] && mmsg dispatch killclient "client,$current" >/dev/null 2>&1
            current=$id
        done
    done
    finish
}

case "$1" in
on)
    [ -n "$2" ] || exit 2
    mmsg dispatch "setoption,window_rule,$rule" >/dev/null
    # Detached from rofi: RofiFiles.sh runs in rofi's script mode, and rofi
    # waits for everything holding its pipe.
    watch "$2" </dev/null >/dev/null 2>&1 &
    echo "$!" >"$watch_pid_file"
    disown
    ;;
off)
    pid=$(cat "$watch_pid_file" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid"
    else
        mmsg dispatch reload_config >/dev/null 2>&1
    fi
    ;;
*)
    echo "usage: $0 on ROFI_PID | off" >&2
    exit 2
    ;;
esac
