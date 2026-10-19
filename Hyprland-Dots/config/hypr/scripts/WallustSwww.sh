#!/usr/bin/env bash
# Wallust: derive colors from the current wallpaper and update templates
# Usage: WallustSwww.sh [absolute_path_to_wallpaper]

set -euo pipefail

# Inputs and paths
passed_path="${1:-}"
rofi_link="$HOME/.config/rofi/.current_wallpaper"
wallpaper_current="$HOME/.config/hypr/wallpaper_effects/.wallpaper_current"

# Helper: get focused monitor name (prefer JSON)
get_focused_monitor() {
  if command -v jq >/dev/null 2>&1; then
    hyprctl monitors -j | jq -r '.[] | select(.focused) | .name'
  else
    hyprctl monitors | awk '/^Monitor/{name=$2} /focused: yes/{print name}'
  fi
}

# Determine wallpaper_path
wallpaper_path=""
if [[ -n "$passed_path" && -f "$passed_path" ]]; then
  wallpaper_path="$passed_path"
else
  # Ask the daemon. `awww query` prints one line per output:
  #   : DP-3: 2560x1440, scale: 1, currently displaying: image: /path/with spaces.png
  # Everything after "image: " is the path, so take it whole - an awk field would cut
  # "Lofi - Anime Girl2.png" at the first space. (The old ~/.cache/awww/<output> lookup
  # broke when awww started versioning that directory; the daemon is the source of truth.)
  current_monitor="$(get_focused_monitor)"
  for i in {1..10}; do
    wallpaper_path="$(awww query 2>/dev/null | sed -n "s/^: ${current_monitor}: .*image: //p" | head -n 1)"
    [[ -n "$wallpaper_path" && -f "$wallpaper_path" ]] && break
    sleep 0.1
  done
fi

if [[ -z "${wallpaper_path:-}" || ! -f "$wallpaper_path" ]]; then
  # Nothing to do; avoid failing loudly so callers can continue
  exit 0
fi

# Update helpers that depend on the path - unless what awww shows is an effect
# image (WallpaperEffects.sh's .wallpaper_modified, made FROM .wallpaper_current).
# Callers without a path (Game Mode, the animations menu, monitor profiles) used
# to copy it over .wallpaper_current, and "Без эффектов" could no longer bring the
# original back. The colours still follow what is on screen.
case "$wallpaper_path" in
  "$HOME/.config/hypr/wallpaper_effects/"*) ;;
  *)
    ln -sf "$wallpaper_path" "$rofi_link" || true
    mkdir -p "$(dirname "$wallpaper_current")"
    cp -f "$wallpaper_path" "$wallpaper_current" || true
    ;;
esac

# How bright the wallpaper is (0 black .. 1 white), for the group tabs:
# UserDecorations.lua deepens their see-through black tint on bright wallpapers
# so the white titles stay readable. wallust cannot say this - its dark16
# palette is dark whatever the picture. Written before wallust runs, so the
# reload its own Hyprland colours trigger picks this up as well; through a
# temp file, so Hyprland never reads it half-written.
tone_file="$HOME/.config/hypr/wallust/wallpaper-tone.lua"
if brightness="$(LC_ALL=C magick "${wallpaper_path}[0]" -resize 200x -colorspace Gray -format '%[fx:mean]' info: 2>/dev/null)" \
  && [[ "$brightness" =~ ^[0-9]*\.?[0-9]+$ ]]; then
  mkdir -p "$(dirname "$tone_file")"
  printf -- '-- Written by WallustSwww.sh on every wallpaper change.\nreturn { brightness = %s }\n' "$brightness" \
    > "$tone_file.tmp" && mv -f "$tone_file.tmp" "$tone_file" || true
fi

# Run wallust (silent) to regenerate templates defined in ~/.config/wallust/wallust.toml
# -s is used in this repo to keep things quiet and avoid extra prompts
wallust run -s "$wallpaper_path" || true

# btop: BtopTheme.py turns the palette wallust just wrote into
# btop/themes/wallust.theme (omarchy's layout) and makes a running btop reload
# it with SIGUSR2 - btop reads its theme only at startup otherwise. cava needs
# nothing - it reloads its own config when the file changes.
"$HOME/.config/hypr/scripts/BtopTheme.py" || true
# GTK3 apps already open (Thunar, file pickers) re-read their Wallust theme -
# see GtkReload.sh. They repaint with it when next focused.
"$HOME/.config/hypr/scripts/GtkReload.sh" || true

# wallust rewrites its template targets after its own hooks run, so the rofi
# palette can only be conditioned once `wallust run` has exited - see
# RofiContrast.py, which picks a readable text colour for each colour slot.
"$HOME/.config/hypr/scripts/RofiContrast.py" || true

# The icons follow too: IconsWallust.py recolours Flat-Remix-Wallust-Dark with
# the accent wallust just wrote. In the background - about a second, and
# nothing waits on it.
"$HOME/.config/hypr/scripts/IconsWallust.py" >/dev/null 2>&1 &
