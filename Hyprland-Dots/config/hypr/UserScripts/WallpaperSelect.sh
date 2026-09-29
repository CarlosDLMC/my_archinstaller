#!/usr/bin/env bash
# This script for selecting wallpapers (SUPER W)

# WALLPAPERS PATH
terminal=foot
wallDIR="$HOME/Pictures/wallpapers"
SCRIPTSDIR="$HOME/.config/hypr/scripts"
wallpaper_current="$HOME/.config/hypr/wallpaper_effects/.wallpaper_current"

# Directory for swaync
iDIR="$HOME/.config/swaync/images"
iDIRi="$HOME/.config/swaync/icons"

# awww transition config
FPS=60
TYPE="any"
DURATION=2
BEZIER=".43,1.19,1,.4"
SWWW_PARAMS="--transition-fps $FPS --transition-type $TYPE --transition-duration $DURATION --transition-bezier $BEZIER"

# Check if package bc exists
if ! command -v bc &>/dev/null; then
  notify-send -i "$iDIR/error.png" "bc missing" "Install package bc first"
  exit 1
fi

# Variables
rofi_theme="$HOME/.config/rofi/config-wallpaper.rasi"
focused_monitor=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')

# Ensure focused_monitor is detected
if [[ -z "$focused_monitor" ]]; then
  notify-send -i "$iDIR/error.png" "E-R-R-O-R" "Could not detect focused monitor"
  exit 1
fi

# Monitor details
scale_factor=$(hyprctl monitors -j | jq -r --arg mon "$focused_monitor" '.[] | select(.name == $mon) | .scale')
monitor_height=$(hyprctl monitors -j | jq -r --arg mon "$focused_monitor" '.[] | select(.name == $mon) | .height')

icon_size=$(echo "scale=1; ($monitor_height * 3) / ($scale_factor * 150)" | bc)
adjusted_icon_size=$(echo "$icon_size" | awk '{if ($1 < 15) $1 = 20; if ($1 > 25) $1 = 25; print $1}')
rofi_override="element-icon{size:${adjusted_icon_size}%;}"

# Kill existing wallpaper daemons for video
kill_wallpaper_for_video() {
  awww kill 2>/dev/null
  pkill mpvpaper 2>/dev/null
  pkill swaybg 2>/dev/null
  pkill hyprpaper 2>/dev/null
}

# Kill existing wallpaper daemons for image
kill_wallpaper_for_image() {
  pkill mpvpaper 2>/dev/null
  pkill swaybg 2>/dev/null
  pkill hyprpaper 2>/dev/null
}

# The find predicate that matches every wallpaper type (images & videos).
# Kept in one variable so the recursive "random" scan and the per-directory
# menu listing stay in sync.
WALL_FIND_TYPES=(
  -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o
  -iname "*.bmp" -o -iname "*.tiff" -o -iname "*.webp" -o
  -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.mov" -o -iname "*.webm"
)

# Retrieve every wallpaper in the tree - used ONLY to pick the ". random" entry.
# The menu itself is now browsed one directory at a time (see menu() below).
mapfile -d '' PICS < <(find -L "${wallDIR}" -type f \( "${WALL_FIND_TYPES[@]}" \) -print0)

RANDOM_PIC=""
if (( ${#PICS[@]} > 0 )); then
  RANDOM_PIC="${PICS[$((RANDOM % ${#PICS[@]}))]}"
fi
RANDOM_PIC_NAME=". random"

# Rofi command
rofi_command="rofi -i -show -dmenu -config $rofi_theme -theme-str $rofi_override"

# The menu for one directory: sub-folders first (navigable), then the
# wallpapers that live directly in it; nothing is listed recursively -
# descending into a folder builds this menu again one level down.
#
# The entries are kept in arrays in THIS shell, and rofi returns the INDEX of
# the pick (-format i), never its text. Returning the text meant finding the
# file again by name, and the name did not survive the trip: rofi rewrites a
# name that is not valid UTF-8 for display, a newline split one entry into two
# lines, and the old find -iname lookup on the name was a glob.
# MENU_KIND[i] is up, random, dir or file, and MENU_PATH[i] the real path.
MENU_KIND=() MENU_PATH=() MENU_LABEL=() MENU_ICON=()

add_menu_entry() { # kind path label icon
  local label="$3" icon="$4"
  # One entry is one line for rofi, ended by "\0icon\x1f<icon>": a CR or LF in
  # the label, or a CR, LF or \x1f in the icon path, would break it apart. The
  # label is only what is shown - the path stays exact in MENU_PATH.
  label="${label//$'\n'/?}"
  label="${label//$'\r'/?}"
  case "$icon" in
    *$'\n'* | *$'\r'* | *$'\x1f'*) icon="image-x-generic" ;;
  esac
  MENU_KIND+=("$1")
  MENU_PATH+=("$2")
  MENU_LABEL+=("$label")
  MENU_ICON+=("$icon")
}

build_menu() {
  local dir="$1"
  MENU_KIND=() MENU_PATH=() MENU_LABEL=() MENU_ICON=()

  # ".." to go back up, shown everywhere except the top-level wallpapers dir.
  if [[ "$dir" != "$wallDIR" ]]; then
    add_menu_entry up "" ".." "go-up"
  fi

  # ". random" (a random wallpaper from the whole tree) only at the top level.
  if [[ "$dir" == "$wallDIR" ]] && [[ -n "$RANDOM_PIC" ]]; then
    add_menu_entry random "$RANDOM_PIC" "$RANDOM_PIC_NAME" "$RANDOM_PIC"
  fi

  # Immediate sub-folders, sorted. ${path##*/}, not $(basename): a command
  # substitution drops a trailing newline from the name.
  local subdir
  while IFS= read -r -d '' subdir; do
    add_menu_entry dir "$subdir" "${subdir##*/}/" "folder"
  done < <(find -L "$dir" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

  # Wallpapers directly in this folder (non-recursive), sorted.
  local pic_path pic_name cache_gif_image cache_preview_image
  while IFS= read -r -d '' pic_path; do
    pic_name="${pic_path##*/}"
    if [[ "$pic_name" =~ \.gif$ ]]; then
      cache_gif_image="$HOME/.cache/gif_preview/${pic_name}.png"
      if [[ ! -f "$cache_gif_image" ]]; then
        mkdir -p "$HOME/.cache/gif_preview"
        magick "$pic_path[0]" -resize 1920x1080 "$cache_gif_image"
      fi
      add_menu_entry file "$pic_path" "$pic_name" "$cache_gif_image"
    elif [[ "${pic_name,,}" =~ \.(mp4|mkv|mov|webm)$ ]]; then
      cache_preview_image="$HOME/.cache/video_preview/${pic_name}.png"
      if [[ ! -f "$cache_preview_image" ]]; then
        mkdir -p "$HOME/.cache/video_preview"
        ffmpeg -v error -y -i "$pic_path" -ss 00:00:01.000 -vframes 1 "$cache_preview_image"
      fi
      add_menu_entry file "$pic_path" "$pic_name" "$cache_preview_image"
    else
      add_menu_entry file "$pic_path" "$pic_name" "$pic_path"
    fi
  done < <(find -L "$dir" -mindepth 1 -maxdepth 1 -type f \( "${WALL_FIND_TYPES[@]}" \) -print0 | sort -z)
}

print_menu() {
  local i
  for i in "${!MENU_LABEL[@]}"; do
    printf "%s\x00icon\x1f%s\n" "${MENU_LABEL[$i]}" "${MENU_ICON[$i]}"
  done
}

# Offer SDDM Simple Wallpaper Option (only for non-video wallpapers)
set_sddm_wallpaper() {
  sleep 1

  # Resolve SDDM themes directory (standard and NixOS path)
  local sddm_themes_dir=""
  if [ -d "/usr/share/sddm/themes" ]; then
    sddm_themes_dir="/usr/share/sddm/themes"
  elif [ -d "/run/current-system/sw/share/sddm/themes" ]; then
    sddm_themes_dir="/run/current-system/sw/share/sddm/themes"
  fi

  [ -z "$sddm_themes_dir" ] && return 0

  local sddm_simple="$sddm_themes_dir/simple_sddm_2"

  # Only prompt if theme exists and its Backgrounds directory is writable
  if [ -d "$sddm_simple" ] && [ -w "$sddm_simple/Backgrounds" ]; then

    # Check if yad is running to avoid multiple notifications
    if pidof yad >/dev/null; then
      killall yad
    fi

    if yad --info --text="Set current wallpaper as SDDM background?\n\nNOTE: This only applies to SIMPLE SDDM v2 Theme" \
      --text-align=left \
      --title="SDDM Background" \
      --timeout=5 \
      --timeout-indicator=right \
      --button="yes:0" \
      --button="no:1"; then

      # Check if terminal exists
      if ! command -v "$terminal" &>/dev/null; then
        notify-send -i "$iDIR/error.png" "Missing $terminal" "Install $terminal to enable setting of wallpaper background"
        exit 1
      fi

      # Guarded like Refresh.sh guards RainbowBorders.sh: this script is not
      # shipped in the repo, and a bare exec of a missing file kills the shell
      # with "No such file or directory" instead of doing nothing.
      if [ ! -x "$SCRIPTSDIR/sddm_wallpaper.sh" ]; then
        notify-send -i "$iDIR/error.png" "SDDM background" \
          "scripts/sddm_wallpaper.sh is not installed - skipping." 2>/dev/null
        return 0
      fi
      exec "$SCRIPTSDIR/sddm_wallpaper.sh" --normal

    fi
  fi
}

# The body of a Lua string literal for any file name, built byte by byte in
# the C locale: \ and " escaped, and every control byte and every byte >= 0x80
# written as a three-digit decimal escape (\233 for a Latin-1 é). The saved
# line is then plain ASCII whatever the name is. Written raw, a CR or LF ended
# the string ("unfinished string"), and a byte that is not valid UTF-8 later
# stopped sed's .* in the UTF-8 session, leaving the tail of the old path
# behind - either way the require of Startup_Apps.lua failed and took every
# config loaded after it down. Always three digits, so a digit that follows in
# the name cannot join the escape. Called in $( ), so the locale stays local.
lua_escape() {
  local LC_ALL=C s="$1" out="" c o i
  for (( i = 0; i < ${#s}; i++ )); do
    c="${s:i:1}"
    case "$c" in
      '\') out+='\\' ;;
      '"') out+='\"' ;;
      *)
        printf -v o '%d' "'$c"
        if (( o < 32 || o > 126 )); then
          printf -v c '\\%03d' "$o"
        fi
        out+="$c"
        ;;
    esac
  done
  printf '%s' "$out"
}

modify_startup_config() {
  local selected_file="$1"
  local startup_config="$HOME/.config/hypr/configs/Startup_Apps.lua"

  # Startup_Apps.lua has these three lines inside hl.on("hyprland.start", ...):
  #   local livewallpaper = "..."
  #   run("awww-daemon --format argb")
  #   -- run("mpvpaper '*' ... " .. livewallpaper)
  # Image wallpaper: awww on, mpvpaper commented. Video: the other way round.
  # Case-insensitive, like main() and the find -iname listing: clip.MP4 played
  # as a video but was saved as an image, so the next login showed a still.
  if [[ "${selected_file,,}" =~ \.(mp4|mkv|mov|webm)$ ]]; then
    # For video wallpapers:
    # LC_ALL=C on every sed here: in the UTF-8 session .* stops at a byte that
    # is not valid UTF-8, so a line saved by an older version of this script
    # was only partly replaced.
    LC_ALL=C sed -i -E 's|^(\s*)run\("awww-daemon --format argb"\)|\1-- run("awww-daemon --format argb")|' "$startup_config"
    LC_ALL=C sed -i -E 's|^(\s*)--\s*run\("mpvpaper |\1run("mpvpaper |' "$startup_config"

    # The path is saved with $HOME in it (Startup_Apps.lua resolves it), then
    # escaped for the Lua string (lua_escape above), then for the sed
    # replacement, where \ & and the | delimiter are special - unescaped, "a &
    # b.mp4" pasted the whole matched line into the file.
    selected_file="${selected_file/#"$HOME"/\$HOME}"
    local _repl
    _repl=$(lua_escape "$selected_file")
    _repl=$(printf '%s' "$_repl" | LC_ALL=C sed -e 's/[\\&|]/\\&/g')
    LC_ALL=C sed -i -E "s|^local livewallpaper = .*|local livewallpaper = \"${_repl}\"|" "$startup_config"

    echo "Configured for live wallpaper (video)."
  else
    # For image wallpapers:
    LC_ALL=C sed -i -E 's|^(\s*)--\s*run\("awww-daemon --format argb"\)|\1run("awww-daemon --format argb")|' "$startup_config"
    LC_ALL=C sed -i -E 's|^(\s*)run\("mpvpaper |\1-- run("mpvpaper |' "$startup_config"
    # And forget the video: left in place, the stale path made copy.sh see
    # Startup_Apps.lua as changed and back hypr up on the next re-run.
    # The whole line, comment included, exactly as the repo ships it - the video
    # branch above drops the comment, and anything else still differs.
    LC_ALL=C sed -i -E 's|^local livewallpaper = .*|local livewallpaper = ""  -- WallpaperSelect.sh rewrites this line for video wallpapers|' "$startup_config"

    echo "Configured for static wallpaper (image)."
  fi
}

# Apply Image Wallpaper
apply_image_wallpaper() {
  local image_path="$1"

  kill_wallpaper_for_image

  if ! pgrep -x "awww-daemon" >/dev/null; then
    echo "Starting awww-daemon..."
    awww-daemon --format argb &
  fi

  # No -o here on purpose: `awww img` without --outputs sets the image on
  # every output, which is what changing "the wallpaper" should mean. It used
  # to pass -o "$focused_monitor", so on a multi-monitor setup only the screen
  # you happened to be on changed and the others kept the old wallpaper.
  awww img "$image_path" $SWWW_PARAMS

  # Run additional scripts (pass the image path to avoid cache race conditions)
  "$SCRIPTSDIR/WallustSwww.sh" "$image_path"
  sleep 2
  "$SCRIPTSDIR/Refresh.sh"
  sleep 1

  set_sddm_wallpaper
}

apply_video_wallpaper() {
  local video_path="$1"

  # Check if mpvpaper is installed
  if ! command -v mpvpaper &>/dev/null; then
    notify-send -i "$iDIR/error.png" "E-R-R-O-R" "mpvpaper not found"
    return 1
  fi
  kill_wallpaper_for_video

  # Apply video wallpaper using mpvpaper
  mpvpaper '*' -o "load-scripts=no no-audio --loop" "$video_path" &
}

# Main function
main() {
  # Browse the wallpapers tree one directory at a time. A folder pick descends,
  # ".." goes back up, and a file (or ". random") pick ends the loop with
  # selected_file set to the chosen wallpaper.
  local current_dir="$wallDIR"
  local idx
  selected_file=""

  while true; do
    build_menu "$current_dir"
    # -no-custom: only a listed entry can come back, never typed text.
    idx=$(print_menu | $rofi_command -format i -no-custom)

    if [[ -z "$idx" ]]; then
      echo "No choice selected. Exiting."
      exit 0
    fi
    if ! [[ "$idx" =~ ^[0-9]+$ ]] || (( idx >= ${#MENU_KIND[@]} )); then
      echo "Not a menu entry ($idx). Exiting."
      exit 0
    fi

    case "${MENU_KIND[$idx]}" in
      up)
        # Never above the wallpapers root - build_menu only offers ".." below
        # it. ${%/*}, not $(dirname): exact for any folder name.
        current_dir="${current_dir%/*}"
        continue
        ;;
      dir)
        current_dir="${MENU_PATH[$idx]}"
        continue
        ;;
      random | file)
        selected_file="${MENU_PATH[$idx]}"
        ;;
    esac

    if [[ ! -f "$selected_file" ]]; then
      echo "File not found: $selected_file"
      exit 1
    fi
    break
  done

  # A video selection needs mpvpaper, and that is checked HERE rather than only
  # inside apply_video_wallpaper below.
  #
  # modify_startup_config runs unconditionally and, for a video, comments out
  # run("awww-daemon --format argb") and uncomments the mpvpaper line in
  # Startup_Apps.lua. apply_video_wallpaper's own guard then refuses and the
  # running session is left alone - which is why this looked harmless. But the
  # startup config has already been switched to a binary that is not installed,
  # so the NEXT login comes up with no wallpaper at all and stays that way until
  # the Lua is hand-edited or an image is picked again. Refuse before anything
  # is written, not after.
  if [[ "${selected_file,,}" =~ \.(mp4|mkv|mov|webm)$ ]] \
     && ! command -v mpvpaper &>/dev/null; then
    notify-send -i "$iDIR/error.png" "Video wallpaper unavailable" \
      "mpvpaper is not installed, so $(basename "$selected_file") cannot be used. Nothing was changed." 2>/dev/null
    echo "mpvpaper is not installed - refusing to switch to a video wallpaper."
    exit 1
  fi

  # Modify Startup_Apps.lua based on wallpaper type
  modify_startup_config "$selected_file"

  # **CHECK FIRST** if it's a video or an image **before calling any function**
  if [[ "${selected_file,,}" =~ \.(mp4|mkv|mov|webm)$ ]]; then
    apply_video_wallpaper "$selected_file"
  else
    apply_image_wallpaper "$selected_file"
  fi
}

# Check if rofi is already running
if pidof rofi >/dev/null; then
  pkill rofi
fi

main