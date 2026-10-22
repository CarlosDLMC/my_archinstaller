#!/usr/bin/env bash
# The overview's window pictures (SUPER+A): one still per window, taken when it
# opens. Under Hyprland the overview showed live pictures through Hyprland's
# own window-capture protocol; quickshell can only capture whole outputs on
# mango, so grim captures each window (ext-image-copy-capture, by its
# foreign-toplevel id) - covered windows and windows on other workspaces too.
#
#   overview-shots.sh DIR ID:FOREIGN_TOPLEVEL_ID:WIDTHxHEIGHT...
#
# mango captures a window with everything attached to it: LibreWolf keeps an
# invisible surface up and left of its window, and that area comes out opaque
# black. A picture bigger than its window gets its black border cut off.
# Only then: a dark window's own black edge stays.
#
# Quarter size: the overview draws a window at about a sixth of its size.
# PPM, not PNG: no compression to wait for, and the files only live on the
# runtime tmpfs until the next open.

dir=${1:?usage: overview-shots.sh DIR ID:FOREIGN_TOPLEVEL_ID:WxH...}
shift
mkdir -p "$dir"
rm -f "$dir"/*.ppm

shot() {
    local id=$1 toplevel=$2 size=$3 f="$dir/$1.ppm" w h
    grim -s 0.25 -t ppm -T "$toplevel" "$f" 2>/dev/null || return
    # PPM header: P6, then width and height.
    read -r w h < <(head -c 64 "$f" | tr -s ' \n' ' ' | cut -d' ' -f2,3)
    if (( w > ${size%x*} / 4 + 2 || h > ${size#*x} / 4 + 2 )); then
        magick "$f" -bordercolor black -border 1 -trim +repage "$f.tmp.ppm" 2>/dev/null \
            && mv "$f.tmp.ppm" "$f"
    fi
}

for arg in "$@"; do
    IFS=: read -r id toplevel size <<<"$arg"
    shot "$id" "$toplevel" "${size:-99999x99999}" &
done
wait
