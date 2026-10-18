#!/usr/bin/env bash
# GTK3 apps that are already open take the new wallpaper's colours.
#
# GTK3 reads ~/.config/gtk-3.0/gtk.css only when an app starts, but it re-reads
# its theme whenever the theme name changes. So the wallust colours live in a
# theme that exists under two names, Wallust-A and Wallust-B (~/.themes), and
# this switches to whichever one is not in use. Run after every `wallust run`
# (WallustSwww.sh, WallpaperEffects.sh): the theme reads the freshly written
# ~/.config/gtk-3.0/wallust.css, and every open Thunar, file picker and so on
# repaints with it. Both are the same complete dark theme, so nothing flashes.

current=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")
if [ "$current" = "Wallust-A" ]; then
    next="Wallust-B"
else
    next="Wallust-A"
fi

# Not installed (a machine set up before these themes existed): leave GTK alone.
[ -f "$HOME/.themes/$next/gtk-3.0/gtk.css" ] || exit 0

gsettings set org.gnome.desktop.interface gtk-theme "$next"
