#!/usr/bin/env bash
# source https://wiki.archlinux.org/title/Hyprland#Using_a_script_to_change_wallpaper_every_X_minutes

# This script will randomly go through the files of a directory, setting it
# up as the wallpaper at regular intervals
#
# NOTE: this script uses bash (not POSIX shell) for the RANDOM variable

wallust_refresh=$HOME/.config/hypr/scripts/RefreshNoWaybar.sh


if [[ $# -lt 1 ]] || [[ ! -d $1   ]]; then
	echo "Usage:
	$0 <dir containing images>"
	exit 1
fi

# Edit below to control the images transition. awww's own names: the SWWW_*
# ones this exported are swww's, which awww does not read, so it used its
# defaults instead.
export AWWW_TRANSITION_FPS=60
export AWWW_TRANSITION=simple

# This controls (in seconds) when to switch to the next image
INTERVAL=1800

while true; do
	# Image files only, as WallpaperRandom.sh lists them: a bare `find` also gave
	# the directory itself, its subfolders and any other file, `awww img` failed
	# on those, and the same wallpaper stayed for another half hour.
	find -L "$1" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o \
		-iname "*.pnm" -o -iname "*.tga" -o -iname "*.tiff" -o -iname "*.webp" -o \
		-iname "*.bmp" -o -iname "*.farbfeld" -o -iname "*.gif" \) \
		| while read -r img; do
			echo "$((RANDOM % 1000)):$img"
		done \
		| sort -n | cut -d':' -f2- \
		| while read -r img; do
			awww img "$img"
			# Regenerate colors from the exact image path to avoid cache races
			$HOME/.config/hypr/scripts/WallustSwww.sh "$img"
			# Refresh UI components that depend on wallust output
			$wallust_refresh
			sleep $INTERVAL
			
		done
done
