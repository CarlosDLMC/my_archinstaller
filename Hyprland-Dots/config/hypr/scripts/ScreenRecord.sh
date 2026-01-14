#!/usr/bin/env bash
# Screen Recording script for Hyprland

# variables
time=$(date "+%d-%b_%H-%M-%S")
dir="$(xdg-user-dir VIDEOS)/Recordings"
file="Recording_${time}.mp4"
pidfile="/tmp/wf-recorder.pid"

iDIR="$HOME/.config/swaync/icons"
iDoR="$HOME/.config/swaync/images"
sDIR="$HOME/.config/hypr/scripts"

notify_cmd_base="notify-send -t 5000 -h string:x-canonical-private-synchronous:record-notify"
notify_cmd_rec="${notify_cmd_base} -i ${iDIR}/video.png"
notify_cmd_NOT="notify-send -u low -i ${iDoR}/note.png"

# Check if recording is in progress
is_recording() {
    if [[ -f "$pidfile" ]]; then
        pid=$(cat "$pidfile")
        if ps -p "$pid" > /dev/null 2>&1; then
            return 0
        else
            rm "$pidfile"
            return 1
        fi
    fi
    return 1
}

# Stop recording
stop_recording() {
    if is_recording; then
        pid=$(cat "$pidfile")
        kill -INT "$pid"
        rm "$pidfile"
        "${sDIR}/Sounds.sh" --screenshot 2>/dev/null || true
        ${notify_cmd_rec} "Recording Stopped" "Saved to ${dir}"
    else
        ${notify_cmd_NOT} "No Recording" "No active recording found"
    fi
}

# Record fullscreen
record_fullscreen() {
    if is_recording; then
        ${notify_cmd_NOT} "Already Recording" "Stop current recording first"
        return
    fi

    "${sDIR}/Sounds.sh" --screenshot 2>/dev/null || true
    ${notify_cmd_rec} "Recording Started" "Fullscreen recording"

    wf-recorder -f "${dir}/${file}" &
    echo $! > "$pidfile"
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

    "${sDIR}/Sounds.sh" --screenshot 2>/dev/null || true
    ${notify_cmd_rec} "Recording Started" "Area recording"

    wf-recorder -g "$geometry" -f "${dir}/${file}" &
    echo $! > "$pidfile"
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

    "${sDIR}/Sounds.sh" --screenshot 2>/dev/null || true
    ${notify_cmd_rec} "Recording Started" "Recording ${active_window_class}"

    wf-recorder -g "$geometry" -f "${dir}/${file}" &
    echo $! > "$pidfile"
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
