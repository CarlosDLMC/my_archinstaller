#!/usr/bin/env bash
# Screen Recording script for Hyprland

# variables
# ISO-ish and all-numeric: lexical order == chronological order, and no
# locale-dependent month name (this folder has German, English and Russian
# month abbreviations in it from LC_TIME changing over the years).
time=$(date "+%Y-%m-%d_%H-%M-%S")
dir="$(xdg-user-dir VIDEOS)/Recordings"
file="Recording_${time}.mp4"
pidfile="/tmp/wf-recorder.pid"
# Module IDs of the temporary null-sink + loopbacks used for "both" audio,
# so stop_recording can tear them down again.
mixfile="/tmp/wf-recorder.pamodules"
mixsink="wfrec_mix"

# none | system | mic | both. Overridable with --audio=<mode>; the OSD writes
# its toggle state here so the keybind and the CLI agree on the default.
audio_state_file="$HOME/.cache/screenrecord_audio"
audio_mode="none"

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
        unload_mix
        ${notify_cmd_rec} "Recording Stopped" "Saved to ${dir}"
    else
        unload_mix
        ${notify_cmd_NOT} "No Recording" "No active recording found"
    fi
}

# Tear down the null-sink/loopback mix, if one is up. Safe to call always:
# leftover modules from a crashed run are matched by name as well as by id,
# so they cannot pile up and eat the pulse client budget.
unload_mix() {
    if [[ -f "$mixfile" ]]; then
        while read -r id; do
            [[ -n "$id" ]] && pactl unload-module "$id" 2>/dev/null
        done < "$mixfile"
        rm -f "$mixfile"
    fi
    # Belt and braces: anything still carrying our sink name.
    pactl list short modules 2>/dev/null \
        | awk -v s="$mixsink" '$0 ~ s {print $1}' \
        | while read -r id; do pactl unload-module "$id" 2>/dev/null; done
}

# Build a single device that carries both the system output and the mic, by
# routing both into a null sink and recording its monitor. wf-recorder takes
# only one -a device, so mixing has to happen in PipeWire.
setup_mix() {
    local sink source
    sink=$(pactl get-default-sink 2>/dev/null)
    source=$(pactl get-default-source 2>/dev/null)

    unload_mix
    : > "$mixfile"

    local mod
    mod=$(pactl load-module module-null-sink \
        sink_name="$mixsink" \
        sink_properties=device.description=wf-recorder-mix 2>/dev/null) || return 1
    echo "$mod" >> "$mixfile"

    if [[ -n "$sink" ]]; then
        mod=$(pactl load-module module-loopback \
            source="${sink}.monitor" sink="$mixsink" latency_msec=50 2>/dev/null) \
            && echo "$mod" >> "$mixfile"
    fi
    if [[ -n "$source" ]]; then
        mod=$(pactl load-module module-loopback \
            source="$source" sink="$mixsink" latency_msec=50 2>/dev/null) \
            && echo "$mod" >> "$mixfile"
    fi

    echo "${mixsink}.monitor"
}

# Echo the wf-recorder audio arguments for the current $audio_mode (nothing
# at all when audio is off, so wf-recorder keeps its video-only path).
audio_args() {
    local dev
    case "$audio_mode" in
        system)
            dev=$(pactl get-default-sink 2>/dev/null)
            [[ -n "$dev" ]] && printf -- '--audio=%s.monitor' "$dev"
            ;;
        mic)
            dev=$(pactl get-default-source 2>/dev/null)
            [[ -n "$dev" ]] && printf -- '--audio=%s' "$dev"
            ;;
        both)
            dev=$(setup_mix)
            [[ -n "$dev" ]] && printf -- '--audio=%s' "$dev"
            ;;
    esac
}

# Human-readable audio suffix for the notification.
audio_label() {
    case "$audio_mode" in
        system) echo " · system audio" ;;
        mic)    echo " · mic" ;;
        both)   echo " · system audio + mic" ;;
        *)      echo "" ;;
    esac
}

# Start wf-recorder and save its PID. Returns 0 if it's still alive after a
# brief grace period, 1 if it died on startup (bad geometry, wrong output, etc.)
start_recorder() {
    # Kill any orphans before starting fresh
    pkill -x wf-recorder 2>/dev/null
    rm -f "$pidfile"

    local -a aargs=()
    local a
    a=$(audio_args)
    [[ -n "$a" ]] && aargs=("$a")

    wf-recorder "${aargs[@]}" "$@" &
    local pid=$!
    echo "$pid" > "$pidfile"
    sleep 0.4
    if kill -0 "$pid" 2>/dev/null; then
        return 0
    fi
    rm -f "$pidfile"
    unload_mix
    return 1
}

# Pick the output (monitor) whose bounds contain the given x,y point.
output_for_point() {
    local x=$1 y=$2
    hyprctl -j monitors | jq -r --argjson x "$x" --argjson y "$y" '
        .[] | select(
            $x >= .x and $x < (.x + .width) and
            $y >= .y and $y < (.y + .height)
        ) | .name' | head -1
}

# Name of the monitor that currently has focus.
focused_output() {
    hyprctl -j monitors | jq -r '.[] | select(.focused) | .name' | head -1
}

# Record one whole monitor. $1 = output name; defaults to the focused monitor.
# wf-recorder with no -o silently grabs the *first* output it enumerates (the
# laptop panel here), so the output is always passed explicitly.
record_fullscreen() {
    if is_recording; then
        ${notify_cmd_NOT} "Already Recording" "Stop current recording first"
        return
    fi

    local output="$1"
    [[ -z "$output" ]] && output=$(focused_output)

    if [[ -z "$output" ]]; then
        ${notify_cmd_NOT} "Recording Failed" "Could not determine which monitor to record"
        return
    fi

    if start_recorder -o "$output" -f "${dir}/${file}"; then
        ${notify_cmd_rec} "Recording Started" "${output}$(audio_label)"
    else
        ${notify_cmd_NOT} "Recording Failed" "wf-recorder exited immediately"
    fi
}

# Record selected area
record_area() {
    if is_recording; then
        ${notify_cmd_NOT} "Already Recording" "Stop current recording first"
        return
    fi

    # Ask slurp for the output name alongside the geometry so wf-recorder
    # records the correct monitor on multi-monitor setups.
    selection=$(slurp -f "%o %x,%y %wx%h")
    if [[ -z "$selection" ]]; then
        ${notify_cmd_NOT} "Recording Cancelled" "No area selected"
        return
    fi

    output=$(awk '{print $1}' <<< "$selection")
    geometry=$(cut -d' ' -f2- <<< "$selection")

    if start_recorder -o "$output" -g "$geometry" -f "${dir}/${file}"; then
        ${notify_cmd_rec} "Recording Started" "Region on ${output}$(audio_label)"
    else
        ${notify_cmd_NOT} "Recording Failed" "wf-recorder exited immediately"
    fi
}

# Pick a whole monitor with slurp (click anywhere on the one you want).
record_pick_monitor() {
    local output
    output=$(slurp -o -f "%o")
    if [[ -z "$output" ]]; then
        ${notify_cmd_NOT} "Recording Cancelled" "No monitor selected"
        return
    fi
    record_fullscreen "$output"
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

    # Resolve which monitor this window sits on so wf-recorder targets it.
    win_x=${w_pos%,*}
    win_y=${w_pos#*,}
    output=$(output_for_point "$win_x" "$win_y")

    if [[ -n "$output" ]]; then
        start_recorder -o "$output" -g "$geometry" -f "${dir}/${file}"
    else
        start_recorder -g "$geometry" -f "${dir}/${file}"
    fi

    if [[ $? -eq 0 ]]; then
        ${notify_cmd_rec} "Recording Started" "${active_window_class}$(audio_label)"
    else
        ${notify_cmd_NOT} "Recording Failed" "wf-recorder exited immediately"
    fi
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

# Handle arguments. --audio=<mode> may appear anywhere; everything else is
# positional, so the OSD can call e.g. `--fullscreen HDMI-A-2 --audio=both`.
args=()
audio_given=0
for arg in "$@"; do
    case "$arg" in
        --audio=*)
            audio_mode="${arg#--audio=}"
            audio_given=1
            ;;
        *)
            args+=("$arg")
            ;;
    esac
done

# No explicit mode: use whatever the OSD toggles were last left on.
if [[ $audio_given -eq 0 && -r "$audio_state_file" ]]; then
    audio_mode=$(tr -d '[:space:]' < "$audio_state_file")
fi
case "$audio_mode" in
    none|system|mic|both) ;;
    *) audio_mode="none" ;;
esac

case "${args[0]}" in
    --fullscreen)
        record_fullscreen "${args[1]}"
        ;;
    --pick-monitor)
        record_pick_monitor
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
    --status)
        is_recording && echo "recording" || echo "idle"
        ;;
    *)
        echo "Usage: ScreenRecord.sh <mode> [output] [--audio=none|system|mic|both]"
        echo "  modes: --fullscreen [output] --pick-monitor --area --active --stop --toggle --status"
        echo "Current status: $(is_recording && echo 'Recording' || echo 'Not recording')"
        echo "Audio mode: ${audio_mode}"
        ;;
esac

exit 0
