#!/usr/bin/env bash
# The overview's window pictures (SUPER+A): one still per window, taken when it
# opens. Under Hyprland the overview showed live pictures through Hyprland's
# own window-capture protocol; quickshell can only capture whole outputs on
# mango, so grim captures each window (ext-image-copy-capture, by its
# foreign-toplevel id) - covered windows and windows on other workspaces too.
#
#   overview-shots.sh DIR ID:FOREIGN_TOPLEVEL_ID...
#
# Quarter size: the overview draws a window at about a sixth of its size.
# PPM, not PNG: no compression to wait for, and the files only live on the
# runtime tmpfs until the next open.

dir=${1:?usage: overview-shots.sh DIR ID:FOREIGN_TOPLEVEL_ID...}
shift
mkdir -p "$dir"
rm -f "$dir"/*.ppm

for pair in "$@"; do
    id=${pair%%:*}
    toplevel=${pair#*:}
    grim -s 0.25 -t ppm -T "$toplevel" "$dir/$id.ppm" 2>/dev/null &
done
wait
