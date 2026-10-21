#!/usr/bin/env bash
# This script applies wallpapers.
#
#   WallpaperSelect.sh FILE   apply FILE. SUPER W opens the quickshell wallpaper
#                             carousel (bar/components/WallpaperOsd.qml), and a
#                             pick there lands here through this mode.
#   WallpaperSelect.sh        the old rofi menu, kept as a fallback.

# WALLPAPERS PATH
terminal=foot
wallDIR="$HOME/Pictures/wallpapers"
SCRIPTSDIR="$HOME/.config/hypr/scripts"
wallpaper_current="$HOME/.config/hypr/wallpaper_effects/.wallpaper_current"

# Notification icons
iDIR="$HOME/.config/hypr/notify/images"
iDIRi="$HOME/.config/hypr/notify/icons"

# awww transition config. "center" grows the new wallpaper as a circle from
# the middle of the screen out to the edges; "any" grew it from a random point.
# WALLPAPER_TRANSITION overrides it: the quickshell carousel draws its own
# reveal (two slanted edges opening from the centre) and then asks for "none",
# so awww swaps the image instantly under the finished reveal.
FPS=60
TYPE="${WALLPAPER_TRANSITION:-center}"
DURATION=2
BEZIER=".43,1.19,1,.4"
SWWW_PARAMS="--transition-fps $FPS --transition-type $TYPE --transition-duration $DURATION --transition-bezier $BEZIER"

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

# Everything only the rofi menu needs: bc and the focused monitor for the icon
# size, and the ". random" pick from the whole tree. Applying a FILE needs none
# of it, so it must not be able to fail on any of it.
prepare_menu() {
  # Check if package bc exists
  if ! command -v bc &>/dev/null; then
    notify-send -i "$iDIR/error.png" "Нет bc" "Сначала установите пакет bc"
    exit 1
  fi

  # Variables
  rofi_theme="$HOME/.config/rofi/config-wallpaper.rasi"
  focused_monitor=$(mmsg get all-monitors | jq -r '.monitors[] | select(.active) | .name')

  # Ensure focused_monitor is detected
  if [[ -z "$focused_monitor" ]]; then
    notify-send -i "$iDIR/error.png" "ОШИБКА" "Не удалось определить активный монитор"
    exit 1
  fi

  # Monitor details. mango's height is already the logical one (pixels / scale).
  monitor_height=$(mmsg get all-monitors | jq -r --arg mon "$focused_monitor" '.monitors[] | select(.name == $mon) | .height')

  icon_size=$(echo "scale=1; ($monitor_height * 3) / 150" | bc)
  adjusted_icon_size=$(echo "$icon_size" | awk '{if ($1 < 15) $1 = 20; if ($1 > 25) $1 = 25; print $1}')
  rofi_override="element-icon{size:${adjusted_icon_size}%;}"

  # Retrieve every wallpaper in the tree - used ONLY to pick the ". random" entry.
  # The menu itself is now browsed one directory at a time (see build_menu() below).
  mapfile -d '' PICS < <(find -L "${wallDIR}" -type f \( "${WALL_FIND_TYPES[@]}" \) -print0)

  RANDOM_PIC=""
  if (( ${#PICS[@]} > 0 )); then
    RANDOM_PIC="${PICS[$((RANDOM % ${#PICS[@]}))]}"
  fi
  RANDOM_PIC_NAME=". random"

  # Rofi command
  rofi_command="rofi -i -show -dmenu -config $rofi_theme -theme-str $rofi_override"
}

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
  #
  # Both loops read the file list on fd 3, not stdin: anything in the loop that
  # reads stdin eats the next NUL-separated path. ffmpeg does (it polls for
  # keys while it works), so a video preview that took over ~0.5 s cut the first
  # bytes off the next path - and with MENU_PATH holding the real path, that
  # pick then failed with "File not found".
  local subdir
  while IFS= read -r -d '' -u 3 subdir; do
    add_menu_entry dir "$subdir" "${subdir##*/}/" "folder"
  done 3< <(find -L "$dir" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

  # Wallpapers directly in this folder (non-recursive), sorted.
  local pic_path pic_name cache_gif_image cache_preview_image
  while IFS= read -r -d '' -u 3 pic_path; do
    pic_name="${pic_path##*/}"
    if [[ "$pic_name" =~ \.gif$ ]]; then
      cache_gif_image="$HOME/.cache/gif_preview/${pic_name}.png"
      if [[ ! -f "$cache_gif_image" ]]; then
        mkdir -p "$HOME/.cache/gif_preview"
        # % doubled: magick reads %d in a file name as a frame number, so "anim
        # %d.gif" was opened as "anim 0.gif" and never got a preview.
        magick "${pic_path//\%/%%}[0]" -resize 1920x1080 "${cache_gif_image//\%/%%}" </dev/null
      fi
      add_menu_entry file "$pic_path" "$pic_name" "$cache_gif_image"
    elif [[ "${pic_name,,}" =~ \.(mp4|mkv|mov|webm)$ ]]; then
      cache_preview_image="$HOME/.cache/video_preview/${pic_name}.png"
      if [[ ! -f "$cache_preview_image" ]]; then
        mkdir -p "$HOME/.cache/video_preview"
        # -update 1: one image, not a numbered sequence - without it an output
        # name with %d in it ("only %d.mp4.png") was written as "only 1.mp4.png",
        # so the cache never matched and the preview was redone every time.
        ffmpeg -nostdin -v error -y -i "$pic_path" -ss 00:00:01.000 -vframes 1 -update 1 "$cache_preview_image" </dev/null
      fi
      add_menu_entry file "$pic_path" "$pic_name" "$cache_preview_image"
    else
      add_menu_entry file "$pic_path" "$pic_name" "$pic_path"
    fi
  done 3< <(find -L "$dir" -mindepth 1 -maxdepth 1 -type f \( "${WALL_FIND_TYPES[@]}" \) -print0 | sort -z)
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

# Remember the kind of wallpaper for the next login: WallpaperStart.sh (mango
# startup.conf) loops this video with mpvpaper, or starts awww when the file is
# empty, and awww shows the last image by itself. Written through a temp file,
# so a login never reads it half-written. A name can hold any byte but a
# newline, which no file picked here has.
record_wallpaper_kind() {
  local selected_file="$1"
  local video_file="$HOME/.config/hypr/wallpaper_effects/.wallpaper_video"

  mkdir -p "$(dirname "$video_file")"
  # Case-insensitive, like main() and the find -iname listing: clip.MP4 played
  # as a video but was saved as an image, so the next login showed a still.
  if [[ "${selected_file,,}" =~ \.(mp4|mkv|mov|webm)$ ]]; then
    printf '%s\n' "$selected_file" > "$video_file.tmp" && mv -f "$video_file.tmp" "$video_file"
    echo "Configured for live wallpaper (video)."
  else
    : > "$video_file"
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
    notify-send -i "$iDIR/error.png" "ОШИБКА" "mpvpaper не найден"
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

  apply_selected
}

# Apply selected_file, picked in the menu above or given on the command line.
apply_selected() {
  # A video selection needs mpvpaper, and that is checked HERE rather than only
  # inside apply_video_wallpaper below.
  #
  # record_wallpaper_kind runs unconditionally and, for a video, makes the next
  # login start mpvpaper. apply_video_wallpaper's own guard then refuses and
  # the running session is left alone - which is why this looked harmless. But
  # the next login would start a binary that is not installed (WallpaperStart.sh
  # falls back to awww then, but the choice is still wrong). Refuse before
  # anything is written, not after.
  if [[ "${selected_file,,}" =~ \.(mp4|mkv|mov|webm)$ ]] \
     && ! command -v mpvpaper &>/dev/null; then
    notify-send -i "$iDIR/error.png" "Видеообои недоступны" \
      "Не установлен mpvpaper, поэтому видео $(basename "$selected_file") использовать нельзя. Ничего не изменено." 2>/dev/null
    echo "mpvpaper is not installed - refusing to switch to a video wallpaper."
    exit 1
  fi

  # The next login starts the same kind of wallpaper
  record_wallpaper_kind "$selected_file"

  # **CHECK FIRST** if it's a video or an image **before calling any function**
  if [[ "${selected_file,,}" =~ \.(mp4|mkv|mov|webm)$ ]]; then
    apply_video_wallpaper "$selected_file"
  else
    apply_image_wallpaper "$selected_file"
  fi
}

# Direct mode: apply the file given on the command line, no menu.
if (( $# > 0 )); then
  selected_file="$1"
  # Absolute, as a menu pick always is: WallustSwww.sh points
  # ~/.config/rofi/.current_wallpaper at this path, and a relative link would
  # point nowhere.
  [[ "$selected_file" == /* ]] || selected_file="$PWD/$selected_file"
  if [[ ! -f "$selected_file" ]]; then
    notify-send -i "$iDIR/error.png" "Обои не найдены" "$selected_file" 2>/dev/null
    echo "File not found: $selected_file"
    exit 1
  fi
  apply_selected
  exit
fi

# Check if rofi is already running
if pidof rofi >/dev/null; then
  pkill rofi
fi

prepare_menu
main