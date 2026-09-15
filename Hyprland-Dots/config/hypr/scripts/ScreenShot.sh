#!/usr/bin/env bash
# Screenshots scripts

# variables
# All-numeric so lexical order == chronological order, and no locale-dependent
# month name (see ScreenRecord.sh for the same change).
time=$(date "+%Y-%m-%d_%H-%M-%S")
dir="$(xdg-user-dir PICTURES)/Screenshots"
file="Screenshot_${time}_${RANDOM}.png"

iDIR="$HOME/.config/swaync/icons"
iDoR="$HOME/.config/swaync/images"
sDIR="$HOME/.config/hypr/scripts"

# active_window_* are deliberately NOT computed here. They used to be, which
# cost an hyprctl call plus a jq fork (~15ms measured) on every screenshot of
# every kind, to build a filename only --active ever uses. shotactive sets them
# itself, and notify_view "active" is only ever reached from shotactive.

notify_cmd_base="notify-send -t 10000 -A action1=Open -A action2=Delete -h string:x-canonical-private-synchronous:shot-notify"
notify_cmd_shot="${notify_cmd_base} -i ${iDIR}/picture.png "
notify_cmd_shot_win="${notify_cmd_base} -i ${iDIR}/picture.png "
notify_cmd_NOT="notify-send -u low -i ${iDoR}/note.png "

# notify and view screenshot
notify_view() {
    if [[ "$1" == "active" ]]; then
        if [[ -e "${active_window_path}" ]]; then
            resp=$(timeout 5 ${notify_cmd_shot_win} " Screenshot of:" " ${active_window_class} Saved.")
            case "$resp" in
				action1)
					xdg-open "${active_window_path}" &
					;;
				action2)
					rm "${active_window_path}" &
					;;
			esac
        else
            ${notify_cmd_NOT} " Screenshot of:" " ${active_window_class} NOT Saved."
            "${sDIR}/Sounds.sh" --error
        fi

    else
        local check_file="${dir}/${file}"
        if [[ -e "$check_file" ]]; then
            resp=$(timeout 5 ${notify_cmd_shot} " Screenshot" " Saved")
			case "$resp" in
				action1)
					xdg-open "${check_file}" &
					;;
				action2)
					rm "${check_file}" &
					;;
			esac
        else
            ${notify_cmd_NOT} " Screenshot" " NOT Saved"
            "${sDIR}/Sounds.sh" --error
        fi
    fi
}

# countdown
countdown() {
	for sec in $(seq $1 -1 1); do
		notify-send -h string:x-canonical-private-synchronous:shot-notify -t 1000 -i "$iDIR"/timer.png  " Taking shot" " in: $sec secs"
		sleep 1
	done
}

# Set by --edit. Without it a capture goes straight to $dir and the clipboard
# and is announced by notify_view; with it satty gets the image instead and
# saving is whatever the user does in there (Ctrl+S saves, Ctrl+C copies).
annotate=false

# satty, sized to 80% of the focused monitor so the editor never opens bigger
# than the screen it lands on. Reads the image on stdin.
satty_open() {
	local res w h
	res=$(hyprctl monitors -j | jq -r '.[] | select(.focused==true) | "\(.width / .scale | floor)x\(.height / .scale | floor)"')
	w=$(echo "$res" | cut -dx -f1)
	h=$(echo "$res" | cut -dx -f2)
	w=$(( w * 80 / 100 ))
	h=$(( h * 80 / 100 ))

	satty -f - \
		--output-filename "${dir}/Screenshot_%Y-%m-%d_%H-%M-%S.png" \
		--copy-command wl-copy \
		--resize "${w}x${h}" \
		--early-exit
}

# grim straight into satty. Arguments are passed to grim verbatim. A cancelled
# selection leaves grim with nothing to capture and satty on an empty stdin
# only shows an error box, so go through a file and check it first.
#
# Piping grim into satty instead of using this temp file - with -t ppm, so grim
# emits bytes immediately instead of after a whole deflate pass, letting the
# capture overlap satty's startup - was tried and REVERTED. An isolated
# benchmark suggested it saved ~450ms, but that was a lucky sample. Measured
# properly on the real script, 14 interleaved runs each, timed to the moment
# satty's window appears on Hyprland's event socket:
#
#   temp file (this)   median 1736ms   mean 1649ms   stdev 269ms
#   piped ppm          median 1756ms   mean 1682ms   stdev 251ms
#   mean delta -33ms against a standard error of 98ms - indistinguishable.
#
# The run-to-run spread here is ~260ms, far larger than anything the pipeline
# can save. Nothing in this script is the bottleneck.
#
# What it actually was: the machine was on battery. EPP sits at balance_power
# and the cores idle around 1.6GHz against a 4.0GHz ceiling, and satty's startup
# is almost entirely single-threaded work - dynamic linking, GTK4/libadwaita
# init - so it scales close to linearly with clock. ~1.3s at 1.6GHz is roughly
# 0.5-0.6s on mains. The variance had the same cause: balance_power ramps
# opportunistically, so every run caught a different clock. So if screenshots
# feel slow, check `powerprofilesctl get` and whether the charger is in before
# touching anything here.
#
# Also ruled out by measurement along the way, all of them dead ends: image
# format and size (a 4KB image still takes satty 1245ms), the GSK renderer (the
# default already beats ngl/gl/vulkan/cairo), and a libadwaita portal stall
# (ADW_DISABLE_PORTAL is slower, not faster).
edit_shot() {
	local tmpfile
	tmpfile=$(mktemp --suffix=.png)
	grim -l 0 "$@" - >"$tmpfile" 2>/dev/null

	if [[ -s "$tmpfile" ]]; then
		satty_open <"$tmpfile"
	fi

	rm -f "$tmpfile"
}

# No shutter sound anywhere in here, deliberately. The notification is the
# feedback; a camera noise on every capture is just noise. Sounds.sh itself
# stays - Volume.sh still uses it, and --error still fires when a shot could
# not be saved.

# PNG compression level 1 on every path that SAVES a shot, not the default 6.
# Measured on a 2560x1440 monitor:
#
#   -l 0   108ms   11.1 MB      -l 2   415ms   3.7 MB
#   -l 1   366ms    3.8 MB      -l 6  1647ms   3.3 MB   (grim's default)
#
# So the default spent 1.3 seconds to save half a megabyte, on every single
# screenshot. Level 1 is 4.5x faster for 14% more disk.
#
# Note this is NOT the -l 0 that edit_shot uses: that writes a temp file which
# satty reads and deletes, where 11MB costs nothing. These files stay in
# ~/Pictures/Screenshots forever, so the size does matter here.
#
# The `sleep` that used to sit between the capture and notify_view is gone
# from every one of these. The pipeline is synchronous - when `grim | tee |
# wl-copy` returns, the file is already complete on disk and the clipboard
# already holds the image (verified, not assumed) - so those were up to two
# seconds of waiting for something that had already happened. The `sleep 1`
# before the capture in shot5/shot10 stays: that one is real, it lets the
# countdown notification leave the screen before the shutter.

# take shots
shotnow() {
	[[ $annotate == true ]] && { edit_shot; return; }
	cd ${dir} && grim -l 1 - | tee "$file" | wl-copy
	notify_view
}

# Name of the monitor the pointer is currently on. This is deliberately not
# the focused monitor: the pointer can sit on one screen while focus is on the
# other, and "the screen my mouse is in" means the pointer.
#
# hyprctl reports x,y in layout coordinates but width,height in pixels, so the
# logical extent is width/scale. Both monitors here are scale 1, but dividing
# keeps it right on a scaled display.
output_at_cursor() {
	local pos x y
	pos=$(hyprctl cursorpos 2>/dev/null | tr -d ' ')
	x=${pos%,*}
	y=${pos#*,}

	[[ -z "$x" || -z "$y" ]] && return 1

	hyprctl -j monitors | jq -r --argjson x "$x" --argjson y "$y" '
		.[] | select(
			$x >= .x and $x < (.x + (.width / .scale)) and
			$y >= .y and $y < (.y + (.height / .scale))
		) | .name' | head -1
}

# Shot of the monitor under the pointer, taken immediately.
shotmouse() {
	local output
	output=$(output_at_cursor)

	if [[ -z "$output" ]]; then
		${notify_cmd_NOT} " Screenshot" " Could not find the monitor under the pointer"
		return 1
	fi

	shotmonitor "$output"
}

# Shot of one whole monitor. $1 = output name, defaults to the focused one.
shotmonitor() {
	local output="$1"
	[[ -z "$output" ]] && output=$(hyprctl -j monitors | jq -r '.[] | select(.focused) | .name' | head -1)

	if [[ -z "$output" ]]; then
		${notify_cmd_NOT} " Screenshot" " Could not determine which monitor"
		return 1
	fi

	[[ $annotate == true ]] && { edit_shot -o "$output"; return; }
	cd ${dir} && grim -l 1 -o "$output" - | tee "$file" | wl-copy
	notify_view
}

shot5() {
	countdown '5'
	[[ $annotate == true ]] && { sleep 1; edit_shot; return; }
	sleep 1 && cd ${dir} && grim -l 1 - | tee "$file" | wl-copy
	notify_view
}

shot10() {
	countdown '10'
	[[ $annotate == true ]] && { sleep 1; edit_shot; return; }
	sleep 1 && cd ${dir} && grim -l 1 - | tee "$file" | wl-copy
	notify_view
}

shotwin() {
	w_pos=$(hyprctl activewindow | grep 'at:' | cut -d':' -f2 | tr -d ' ' | tail -n1)
	w_size=$(hyprctl activewindow | grep 'size:' | cut -d':' -f2 | tr -d ' ' | tail -n1 | sed s/,/x/g)
	[[ $annotate == true ]] && { edit_shot -g "$w_pos $w_size"; return; }
	cd ${dir} && grim -l 1 -g "$w_pos $w_size" - | tee "$file" | wl-copy
	notify_view
}

shotarea() {
	[[ $annotate == true ]] && { edit_shot -g "$(slurp)"; return; }

	tmpfile=$(mktemp)
	grim -l 1 -g "$(slurp)" - >"$tmpfile"

  # Copy with saving
	if [[ -s "$tmpfile" ]]; then
		wl-copy <"$tmpfile"
		mv "$tmpfile" "$dir/$file"
	fi
	notify_view
}

shotactive() {
    active_window_class=$(hyprctl -j activewindow | jq -r '(.class)')
    active_window_file="Screenshot_${time}_${active_window_class}.png"
    active_window_path="${dir}/${active_window_file}"

    local geom
    geom=$(hyprctl -j activewindow | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')

	[[ $annotate == true ]] && { edit_shot -g "$geom"; return; }

    grim -l 1 -g "$geom" "${active_window_path}"
    notify_view "active"
}

if [[ ! -d "$dir" ]]; then
	mkdir -p "$dir"
fi

# --edit can sit anywhere in the arguments; strip it out before dispatching so
# the mode is still $1 and "--monitor DP-1 --edit" works.
args=()
for arg in "$@"; do
	if [[ "$arg" == "--edit" ]]; then
		annotate=true
	else
		args+=("$arg")
	fi
done
set -- "${args[@]}"

if [[ "$1" == "--now" ]]; then
	shotnow
elif [[ "$1" == "--monitor" ]]; then
	shotmonitor "$2"
elif [[ "$1" == "--mouse" ]]; then
	shotmouse
elif [[ "$1" == "--in5" ]]; then
	shot5
elif [[ "$1" == "--in10" ]]; then
	shot10
elif [[ "$1" == "--win" ]]; then
	shotwin
elif [[ "$1" == "--area" ]]; then
	shotarea
elif [[ "$1" == "--active" ]]; then
	shotactive
else
	echo -e "Available Options : --now --mouse --monitor [output] --in5 --in10 --win --area --active [--edit]"
fi

exit 0
