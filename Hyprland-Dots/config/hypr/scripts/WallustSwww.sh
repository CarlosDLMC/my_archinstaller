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

# Update helpers that depend on the path
ln -sf "$wallpaper_path" "$rofi_link" || true
mkdir -p "$(dirname "$wallpaper_current")"
cp -f "$wallpaper_path" "$wallpaper_current" || true

# Run wallust (silent) to regenerate templates defined in ~/.config/wallust/wallust.toml
# -s is used in this repo to keep things quiet and avoid extra prompts
wallust run -s "$wallpaper_path" || true

# wallust rewrites its template targets after its own hooks run, so the rofi
# palette can only be conditioned once `wallust run` has exited - see
# RofiContrast.py, which picks a readable text colour for each colour slot.
"$HOME/.config/hypr/scripts/RofiContrast.py" || true
