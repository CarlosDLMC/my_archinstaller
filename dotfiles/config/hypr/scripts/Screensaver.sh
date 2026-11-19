#!/usr/bin/env bash
# Screensaver: your text art (the *.txt files in ~/.local/share/screensaver/art/,
# or ~/.local/share/screensaver/art.txt when that folder has none; made with
# ImgToText.py - see the README's Screensaver section) drawn by ttfx effects,
# a random piece with a random effect, one after another, in a fullscreen foot;
# every other monitor shows a live copy of that screen (wl-mirror).
#
#   Screensaver.sh          open it on the focused monitor, copied to the
#                           others; ending it goes straight back to the
#                           desktop
#   Screensaver.sh --lock   the same, but ending it locks the screen, the way
#                           CTRL+ALT+L does
#   Screensaver.sh --run    the loop inside that terminal (started by the
#                           above, which stays behind to end it all)
#
# Any key, mouse movement or click on any of the monitors, focus leaving the
# screensaver windows, or the screen locking ends it - nothing shows above the
# lock screen, so it would only run unseen.
# Notifications are held while it runs.
# 60 fps, not 120: foot draws on the CPU, and measured fullscreen on this
# machine 120 fps cost ~75% of a core against ~59% at 60.

# Not under ~/.config/hypr: an installer re-run replaces that folder with the
# repo's copy, and the art is yours, not the repo's.
art_dir="$HOME/.local/share/screensaver/art"
# The single piece ScreensaverArt.sh makes on a fresh install
art_file="$HOME/.local/share/screensaver/art.txt"
app_id="screensaver"
# Exists once every window is up: input before that is the windows opening
armed="${XDG_RUNTIME_DIR:-/tmp}/screensaver.armed"

shopt -s nullglob
arts=("$art_dir"/*.txt)
((${#arts[@]})) || [[ ! -f $art_file ]] || arts=("$art_file")

run=false
lock=false
for arg in "$@"; do
  case $arg in
  --run) run=true ;;
  --lock) lock=true ;;
  *)
    echo "usage: Screensaver.sh [--lock]" >&2
    exit 2
    ;;
  esac
done

# The copies of the screen on the other monitors (rules.conf floats them)
mirror_title="screensaver-mirror"

windows() {
  mmsg get all-clients | jq --arg id "$app_id" "[.clients[] | select(.appid == \$id)] | length" 2>/dev/null
}

focused() {
  mmsg get focusing-client | jq -e --arg id "$app_id" ".appid == \$id" >/dev/null 2>&1
}

if ! $run; then
  # With --lock, a screensaver that cannot start still locks: idle and
  # SUPER+CTRL+ALT+L count on the screen ending up locked.
  command -v ttfx >/dev/null || {
    notify-send "Screensaver" "ttfx is not installed"
    $lock && exec "$HOME/.config/hypr/scripts/LockScreen.sh"
    exit 1
  }
  ((${#arts[@]})) || {
    notify-send "Screensaver" "No art yet: make $art_dir/*.txt with ImgToText.py"
    $lock && exec "$HOME/.config/hypr/scripts/LockScreen.sh"
    exit 1
  }
  # Already up
  (($(windows) > 0)) && exit 0

  pids=()
  finish() {
    trap "" INT TERM HUP QUIT USR1 # once is enough
    # With --lock: lock, as CTRL+ALT+L does - unless it already is, which is
    # also why it can be ending. Lock first, close second: the windows (their
    # last frames still on them) stay up until hyprlock runs, plus a moment
    # for it to draw, so the lock screen covers the screensaver directly.
    # Closing first showed the desktop while LockScreen.sh and hyprlock
    # started. At most 3 s, so a lock that never comes cannot keep it up.
    if $lock && ! pidof hyprlock >/dev/null; then
      setsid -f "$HOME/.config/hypr/scripts/LockScreen.sh" >/dev/null 2>&1
      for _ in {1..27}; do
        pidof hyprlock >/dev/null && break
        sleep 0.1
      done
      sleep 0.3
    fi
    ((${#pids[@]})) && kill "${pids[@]}" 2>/dev/null
    rm -f "$armed"
    # Notifications back - unless Do Not Disturb was already on
    [[ ${was_paused:-} == false ]] && dunstctl set-paused false
    exit 0
  }
  # USR1: a window got a key or the mouse
  trap finish INT TERM HUP QUIT USR1

  rm -f "$armed"
  # Notifications would pop up over it - message text on an unattended screen.
  # dunst holds them while paused and shows them when it resumes.
  was_paused=$(dunstctl is-paused 2>/dev/null)
  dunstctl set-paused true 2>/dev/null

  # Drawn once, on the monitor that has the focus; every other monitor shows a
  # live copy of that one (wl-mirror, on the GPU) - a second terminal drawing
  # its own would cost the CPU twice. Without wl-mirror the other monitors
  # keep showing the desktop.
  # Opaque, whatever alpha foot.ini gives normal terminals
  SCREENSAVER_PARENT=$$ foot --fullscreen --app-id "$app_id" -o colors-dark.alpha=1.0 "$0" --run &
  term=$!
  pids+=("$term")
  for _ in {1..40}; do
    (($(windows) > 0)) && break
    sleep 0.05
  done
  current=$(mmsg get all-monitors | jq -r "first(.monitors[] | select(.active) | .name)")
  if command -v wl-mirror >/dev/null && [[ -n $current ]]; then
    mapfile -t others < <(mmsg get all-monitors | jq -r ".monitors[] | select(.active | not) | .name")
    for mon in "${others[@]}"; do
      # A copy that asks for fullscreen itself (--fullscreen-output) gets no
      # frame on a monitor that is not the focused one, with every capture
      # method; one that opens as a small window, is moved there and is made
      # fullscreen by mango keeps getting them. rules.conf keeps the focus
      # off it (no_focus), so the keys stay with the terminal.
      wl-mirror -b screencopy-dmabuf --no-show-cursor --title "$mirror_title" "$current" >/dev/null 2>&1 &
      pids+=($!)
      id=""
      for _ in {1..40}; do
        id=$(mmsg get all-clients | jq -r --arg t "$mirror_title" "first(.clients[] | select(.title == \$t and (.is_fullscreen | not)) | .id)" 2>/dev/null)
        [[ -n $id ]] && break
        sleep 0.05
      done
      [[ -n $id ]] || continue
      mmsg dispatch "tagmon,$mon,0" "client,$id" >/dev/null 2>&1
      # moving it took the focus to that monitor
      mmsg dispatch "focusmon,$current" >/dev/null 2>&1
      mmsg dispatch togglefullscreen "client,$id" >/dev/null 2>&1
    done
  fi
  # The pointer hides at once and comes back when the mouse moves - which ends
  # the screensaver anyway (hide_cursor, patched mango).
  mmsg dispatch hide_cursor >/dev/null 2>&1
  sleep 0.4
  touch "$armed"

  # The terminal reports its own keys and mouse (USR1); the mouse over a copy
  # reaches no terminal, so the pointer is watched here as well.
  pointer=$(mmsg get cursorpos 2>/dev/null)
  while true; do
    # in the background, so USR1 ends it at once
    sleep 0.5 &
    wait $!
    if ! kill -0 "$term" 2>/dev/null || ! focused || pidof hyprlock >/dev/null ||
      [[ $(mmsg get cursorpos 2>/dev/null) != "$pointer" ]]; then
      finish
    fi
  done
fi

# ---- --run: one window ----
parent=${SCREENSAVER_PARENT:-}

# A key or the mouse: tell the launcher, which locks and then closes every
# window - this one keeps its last frame until then.
wake() {
  trap "" INT TERM HUP QUIT
  [[ -n ${pid:-} ]] && kill "$pid" 2>/dev/null
  [[ -n $parent ]] && kill -USR1 "$parent" 2>/dev/null
  for _ in {1..50}; do
    [[ -n $parent ]] && kill -0 "$parent" 2>/dev/null || break
    sleep 0.1
  done
  printf "\033[?1003l\033[?1006l\033[?25h" # mouse reporting off, cursor back
  stty echo 2>/dev/null
  exit 0
}
trap wake INT TERM QUIT

# The window opens at 80x24 and is resized once mango has made it
# fullscreen; ttfx measures the terminal once, at start.
deadline=$((SECONDS + 2))
while ((SECONDS < deadline)) && [[ $(stty size 2>/dev/null) == "24 80" ]]; do
  sleep 0.02
done

stty -echo
# Report all mouse motion as input, so moving the mouse wakes it like a key.
printf "\033]11;rgb:00/00/00\007\033[?25l\033[?1003h\033[?1006h"

# The machine's colours, the lock screen's and dunst's: ink on black, a dim
# grey, a near-white, and red only for heat - sparks, fire, lightning, a
# glitch. ttfx's own defaults are a different palette for every effect (orange
# to lavender to mint, purple and cyan...); here every effect gets these
# instead, and the art always settles in the ink, bright at the top.
bright=F2F2EC ink=D8D8D0 dim=6E7066 dark=45463F red=C42B1C
ramp="$bright $ink $dim"
# 21 of ttfx's 37, picked by watching each one on the art
declare -A colours=(
  [binarypath]="--binary-colors $dark $dim $ink --final-gradient-stops $ramp"
  # ttfx 0.5.0 ignores --star-colors: the explosion keeps its own rainbow
  [blackhole]="--blackhole-color $bright --star-colors $red $bright $ink $dim --final-gradient-stops $ramp"
  [bouncyballs]="--ball-colors $ink $dim $red --final-gradient-stops $ramp"
  [burn]="--starting-color $dim --burn-colors $bright $red $dark --final-gradient-stops $ramp"
  [decrypt]="--ciphertext-colors $dark $dim $ink --final-gradient-stops $ramp"
  [expand]="--final-gradient-stops $ramp"
  [fireworks]="--firework-colors $red $bright $ink --final-gradient-stops $ramp"
  [highlight]="--final-gradient-stops $ramp"
  [middleout]="--starting-color $bright --final-gradient-stops $ramp"
  [orbittingvolley]="--final-gradient-stops $ramp"
  [pour]="--starting-color $bright --final-gradient-stops $ramp"
  [rain]="--rain-colors $dark $dim $ink --final-gradient-stops $ramp"
  [scattered]="--final-gradient-stops $ramp"
  [slice]="--final-gradient-stops $ramp"
  [slide]="--final-gradient-stops $ramp"
  [spray]="--final-gradient-stops $ramp"
  [sweep]="--final-gradient-stops $ramp"
  [synthgrid]="--grid-gradient-stops $red $dark --text-gradient-stops $ramp"
  # The raindrops stay ttfx's light blue: there is no option for them
  [thunderstorm]="--lightning-color $bright --glowing-text-color $red --spark-glow-color $red --final-gradient-stops $ramp"
  [unstable]="--unstable-color $red --final-gradient-stops $ramp"
  [vhstape]="--glitch-line-colors $bright $red $dim $bright --glitch-wave-colors $bright $red $dim $bright --noise-colors 000000 $dark $dim $ink $bright --final-gradient-stops $ramp"
)
effects=("${!colours[@]}")

while true; do
  # The Mosfilm logo opens, always scattered; then a random piece with a
  # random effect, never the same piece twice in a row
  if [[ -z ${last_art:-} && -f $art_dir/mosfilm_logo.txt ]]; then
    art=$art_dir/mosfilm_logo.txt
    effect=scattered
  else
    art=${arts[RANDOM % ${#arts[@]}]}
    while ((${#arts[@]} > 1)) && [[ $art == "${last_art:-}" ]]; do
      art=${arts[RANDOM % ${#arts[@]}]}
    done
    effect=${effects[RANDOM % ${#effects[@]}]}
  fi
  last_art=$art
  read -ra opts <<<"${colours[$effect]}"
  ttfx -i "$art" --frame-rate 60 \
    --canvas-width 0 --canvas-height 0 --reuse-canvas \
    --anchor-canvas c --anchor-text c \
    --no-eol --no-restore-cursor "$effect" "${opts[@]}" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if read -rsn1 -t 1; then
      # input from before every window was up is the windows opening
      [[ -e $armed ]] && wake
    elif [[ -z $parent ]] || ! kill -0 "$parent" 2>/dev/null; then
      # the launcher is gone: nothing would end this window
      kill "$pid" 2>/dev/null
      exit 0
    fi
  done
done
