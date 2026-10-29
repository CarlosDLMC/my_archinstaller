#!/usr/bin/env bash
# Game Mode (SUPER+SHIFT+G). Turns off animations, blur, shadows, gaps and
# rounding, makes windows opaque and stops the wallpaper - awww's picture or
# mpvpaper's video, which would otherwise keep decoding behind the game.
#
# The overrides go into a file on the runtime tmpfs that mango sources last
# (state/machine.conf, written by MachineConf.sh); mango reloads when it
# appears or goes. So game mode holds across config reloads and ends with the
# session. Within mango's limits:
# - window opacity is fixed when a window opens, so windows already open keep
#   theirs (an unfocused terminal stays translucent); windows opened in game
#   mode are opaque;
# - the bar keeps its blur (mango never changes a mapped surface's blur).
# The bar is told too: with no gaps it reserves its whole height (mango has one
# gap for top and bottom, and the bar's reserved strip counts on it).

notif="$HOME/.config/hypr/notify/images/ja.png"
SCRIPTSDIR="$HOME/.config/hypr/scripts"
state="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/mango-gamemode.conf"

if [ ! -e "$state" ]; then
    cat >"$state" <<'CONF'
# Game mode (GameMode.sh) - removed again when it is switched off.
animations=0
layer_animations=0
shadows=0
layer_shadows=0
blur=0
blur_layer=0
border_radius=0
border_px=1
gap_inner_horizontal=0
gap_inner_vertical=0
gap_outer_horizontal=0
gap_outer_vertical=0
focused_opacity=1.0
unfocused_opacity=1.0
window_rule=focused_opacity:1.0,unfocused_opacity:1.0,app_id:.*
CONF
    rust-bar msg gamemode set true >/dev/null 2>&1
    awww kill 2>/dev/null
    pkill -x mpvpaper
    notify-send -t 1000 -e -u low -i "$notif" "Игровой режим:" "включён"
    exit
fi

rm -f "$state"
rust-bar msg gamemode set false >/dev/null 2>&1
# The wallpaper comes back the way it starts at login: WallpaperStart.sh loops
# the video picked last, or starts awww-daemon, which shows its last image by
# itself (an effect image too). Starting awww here showed that cached still on
# top of a video, and WallustSwww.sh below then themed the desktop from it.
# Not when a wallpaper was picked during game mode: that one already runs.
if ! pgrep -x mpvpaper >/dev/null && ! pgrep -x awww-daemon >/dev/null; then
    setsid -f "$SCRIPTSDIR/WallpaperStart.sh" >/dev/null 2>&1
fi
sleep 0.1
"$SCRIPTSDIR/WallustSwww.sh"
sleep 0.5
"$SCRIPTSDIR/Refresh.sh"
notify-send -t 1000 -e -u normal -i "$notif" "Игровой режим:" "выключен"
