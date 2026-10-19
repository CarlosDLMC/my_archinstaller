#!/usr/bin/env bash
# Screensaver: your text art (~/.local/share/screensaver/art.txt, made with
# ImgToText.py - see the README's Screensaver section) drawn by ttfx effects,
# one random effect after another, in a fullscreen foot.
#
#   Screensaver.sh         open it on the focused monitor
#   Screensaver.sh --run   the loop inside that terminal
#
# Any key, mouse movement or click, or focus leaving the window ends it.
# Notifications are held while it runs.
# 60 fps, not 120: foot draws on the CPU, and measured fullscreen on this
# machine 120 fps cost ~75% of a core against ~59% at 60.

# Not under ~/.config/hypr: an installer re-run replaces that folder with the
# repo's copy, and the art is yours, not the repo's.
art="$HOME/.local/share/screensaver/art.txt"
app_id="screensaver"

if [[ ${1:-} != --run ]]; then
    command -v ttfx >/dev/null || { notify-send "Screensaver" "ttfx is not installed"; exit 1; }
    [[ -f $art ]] || { notify-send "Screensaver" "No art yet: make $art with ImgToText.py"; exit 1; }
    # Already up
    hyprctl clients -j | jq -e --arg id "$app_id" 'any(.class == $id)' >/dev/null && exit 0
    # Opaque, whatever alpha foot.ini gives normal terminals
    exec foot --fullscreen --app-id "$app_id" -o colors-dark.alpha=1.0 "$0" --run
fi

focused() {
    hyprctl activewindow -j | jq -e --arg id "$app_id" '.class == $id' >/dev/null 2>&1
}

finish() {
    [[ -n ${pid:-} ]] && kill "$pid" 2>/dev/null
    printf '\033[?1003l\033[?1006l\033[?25h'   # mouse reporting off, cursor back
    stty echo 2>/dev/null
    hyprctl eval 'hl.config({ cursor = { invisible = false } })' >/dev/null 2>&1
    # Notifications back - unless Do Not Disturb was already on
    [[ ${was_paused:-} == false ]] && dunstctl set-paused false
    exit 0
}
trap finish INT TERM HUP QUIT

# The window opens at 80x24 and is resized once Hyprland has made it
# fullscreen; ttfx measures the terminal once, at start.
deadline=$((SECONDS + 2))
while ((SECONDS < deadline)) && [[ $(stty size 2>/dev/null) == "24 80" ]]; do
    sleep 0.02
done

stty -echo
# Notifications would pop up over it - message text on an unattended screen.
# dunst holds them while paused and shows them when it resumes.
was_paused=$(dunstctl is-paused 2>/dev/null)
dunstctl set-paused true 2>/dev/null
# Report all mouse motion as input, so moving the mouse wakes it like a key.
printf '\033]11;rgb:00/00/00\007\033[?25l\033[?1003h\033[?1006h'
hyprctl eval 'hl.config({ cursor = { invisible = true } })' >/dev/null 2>&1

while true; do
    ttfx -i "$art" --frame-rate 60 \
        --canvas-width 0 --canvas-height 0 --reuse-canvas \
        --anchor-canvas c --anchor-text c \
        --random-effect --no-eol --no-restore-cursor \
        `# 22 of ttfx's 37, picked by watching each one on the art` \
        --include-effects binarypath blackhole bouncyballs burn decrypt \
            expand fireworks highlight middleout orbittingvolley pour rain \
            scattered slice slide spray swarm sweep synthgrid thunderstorm \
            unstable vhstape &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        if read -rsn1 -t 1 || ! focused; then
            finish
        fi
    done
done
