#!/usr/bin/env bash
# Screen Recording script for Hyprland

# variables
time=$(date "+%d-%b_%H-%M-%S")
dir="$(xdg-user-dir VIDEOS)/Recordings"
file="Recording_${time}.mp4"
pidfile="/tmp/wf-recorder.pid"

iDIR="$HOME/.config/swaync/icons"
iDoR="$HOME/.config/swaync/images"

notify_cmd_base="notify-send -t 5000 -h string:x-canonical-private-synchronous:record-notify"
notify_cmd_rec="${notify_cmd_base} -i ${iDIR}/video.png"
notify_cmd_NOT="notify-send -u low -i ${iDoR}/note.png"

# Check if recording is in progress
is_recording() {
    if [[ -f "$pidfile" ]]; then
        pid=$(cat "$pidfile")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        else
            rm -f "$pidfile"
        fi
    fi
    # Fallback: detect orphaned wf-recorder
    if pgrep -x wf-recorder > /dev/null 2>&1; then
        pgrep -x wf-recorder | head -1 > "$pidfile"
        return 0
    fi
    return 1
}

# Stop recording
stop_recording() {
    if is_recording; then
        pid=$(cat "$pidfile")
        kill -INT "$pid" 2>/dev/null
        rm -f "$pidfile"
        # Clean up any orphans
        pkill -x wf-recorder 2>/dev/null
        ${notify_cmd_rec} "Recording Stopped" "Saved to ${dir}"
    else
        ${notify_cmd_NOT} "No Recording" "No active recording found"
    fi
}

# Start wf-recorder and save its PID
start_recorder() {
    # Kill any orphans before starting fresh
    pkill -x wf-recorder 2>/dev/null
    rm -f "$pidfile"
    wf-recorder "$@" &
    echo $! > "$pidfile"
}

# Record fullscreen
record_fullscreen() {
    if is_recording; then
        ${notify_cmd_NOT} "Already Recording" "Stop current recording first"
        return
    fi

    ${notify_cmd_rec} "Recording Started" "Fullscreen recording"

    start_recorder -f "${dir}/${file}"
}

# Record selected area
record_area() {
    if is_recording; then
        ${notify_cmd_NOT} "Already Recording" "Stop current recording first"
        return
    fi

    geometry=$(slurp)
    if [[ -z "$geometry" ]]; then
        ${notify_cmd_NOT} "Recording Cancelled" "No area selected"
        return
    fi

    ${notify_cmd_rec} "Recording Started" "Area recording"

    start_recorder -g "$geometry" -f "${dir}/${file}"
}

# Record active window
record_active() {
    if is_recording; then
        ${notify_cmd_NOT} "Already Recording" "Stop current recording first"
        return
    fi

    active_window_class=$(hyprctl -j activewindow | jq -r '(.class)')
    w_pos=$(hyprctl activewindow | grep 'at:' | cut -d':' -f2 | tr -d ' ' | tail -n1)
    w_size=$(hyprctl activewindow | grep 'size:' | cut -d':' -f2 | tr -d ' ' | tail -n1 | sed s/,/x/g)
    geometry="${w_pos} ${w_size}"

    ${notify_cmd_rec} "Recording Started" "Recording ${active_window_class}"

    start_recorder -g "$geometry" -f "${dir}/${file}"
}

# Toggle recording (for simple keybind)
toggle_recording() {
    if is_recording; then
        stop_recording
    else
        record_area
    fi
}

# Create directory if it doesn't exist
if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir"
fi

# Handle arguments
case "$1" in
    --fullscreen)
        record_fullscreen
        ;;
    --area)
        record_area
        ;;
    --active)
        record_active
        ;;
    --stop)
        stop_recording
        ;;
    --toggle)
        toggle_recording
        ;;
    *)
        echo "Available Options: --fullscreen --area --active --stop --toggle"
        echo "Current status: $(is_recording && echo 'Recording' || echo 'Not recording')"
        ;;
esac

exit 0
