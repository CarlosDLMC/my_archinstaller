#!/usr/bin/env bash
# Script for Random Wallpaper ( CTRL ALT W)

wallDIR="$HOME/Pictures/wallpapers"
SCRIPTSDIR="$HOME/.config/hypr/scripts"


# -print0 with `mapfile -d ""`, not a bare $(find): unquoted command
# substitution is word-split on whitespace, so a wallpaper named
# "Night monochrome.jpg" became TWO array entries - a truncated ".../Night" and
# a bare "monochrome.jpg" - and picking either made awww bail out with
# "Unrecognized format by `image` crate", leaving the wallpaper unchanged.
# Several of the shipped wallpapers have spaces in their names, so a good
# fraction of random picks silently did nothing. WallpaperSelect.sh already
# collects its list this way.
mapfile -d '' PICS < <(find -L "${wallDIR}" -type f \( \
  -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.pnm" -o \
  -name "*.tga" -o -name "*.tiff" -o -name "*.webp" -o -name "*.bmp" -o \
  -name "*.farbfeld" -o -name "*.gif" \) -print0)
RANDOMPICS="${PICS[$((RANDOM % ${#PICS[@]}))]}"


# Transition config
FPS=30
TYPE="random"
DURATION=1
BEZIER=".43,1.19,1,.4"
SWWW_PARAMS="--transition-fps $FPS --transition-type $TYPE --transition-duration $DURATION --transition-bezier $BEZIER"


# No -o here on purpose: `awww img` without --outputs sets the image on
# every output, which is what changing "the wallpaper" should mean. It used
# to pass -o "$focused_monitor", so on a multi-monitor setup only the screen
# you happened to be on changed and the others kept the old wallpaper.
awww query || awww-daemon --format argb && awww img "${RANDOMPICS}" $SWWW_PARAMS

wait $!
"$SCRIPTSDIR/WallustSwww.sh" &&

wait $!
sleep 2
"$SCRIPTSDIR/Refresh.sh"

