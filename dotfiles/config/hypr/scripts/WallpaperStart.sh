#!/usr/bin/env bash
# Start the wallpaper at login (mango startup.conf): mpvpaper looping the video
# picked last, or awww-daemon, which shows the last image by itself.
#
# WallpaperSelect.sh writes the video's path to .wallpaper_video when a video
# is picked and empties it when an image is. Under Hyprland it commented and
# uncommented lines of the compositor config instead.
video_file="$HOME/.config/hypr/wallpaper_effects/.wallpaper_video"

video=""
[ -s "$video_file" ] && IFS= read -r video <"$video_file"
if [ -n "$video" ] && [ -f "$video" ] && command -v mpvpaper >/dev/null; then
    exec mpvpaper '*' -o "load-scripts=no no-audio --loop" "$video"
fi
exec awww-daemon --format argb
