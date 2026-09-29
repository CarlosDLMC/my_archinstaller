#!/usr/bin/env bash
# RofiBeats - unified, dynamic UI (add, remove, manage, play)

mDIR="$HOME/Music/"
iDIR="$HOME/.config/swaync/icons"
rofi_theme="$HOME/.config/rofi/config-rofi-Beats.rasi"
rofi_theme_menu="$HOME/.config/rofi/config-rofi-Beats-menu.rasi"
music_list="$HOME/.config/rofi/online_music.list"

mkdir -p "$(dirname "$music_list")"
[[ -f "$music_list" ]] || touch "$music_list"

# Send notification
notification() {
  notify-send -u normal -i "$iDIR/music.png" "$@"
}

# Every mpv this script starts carries this marker, and only those are
# looked for and stopped. It used to be `pgrep -x mpv` plus `kill -9` on each
# one, so starting or stopping music SIGKILLed a video you were watching in
# mpv (the 'unique-wallpaper-process' exclusion never matched anything).
MUSIC_MARK="--title=RofiBeats"
# Anchored on the command being mpv: a bare match on the marker also hit any
# shell or grep whose command line merely mentions it.
MUSIC_MATCH="^mpv .*${MUSIC_MARK}( |\$)"

# Check if RofiBeats music is currently playing
music_playing() { pgrep -f -- "$MUSIC_MATCH" >/dev/null; }

# Stop RofiBeats' own mpv (SIGTERM: mpv exits cleanly on it)
stop_music() {
  if music_playing; then
    pkill -f -- "$MUSIC_MATCH" || true
    notification "Music stopped"
  fi
}

# Populate local music file list
populate_local_music() {
  local_music=()
  filenames=()
  while IFS= read -r file; do
    local_music+=("$file")
    filenames+=("$(basename "$file")")
  done < <(find -L "$mDIR" -type f \( -iname "*.mp3" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.ogg" -o -iname "*.mp4" \))
}

# Play selected local music file
play_local_music() {
  populate_local_music
  choice=$(printf "%s\n" "${filenames[@]}" | rofi -i -dmenu -config "$rofi_theme" \
    -theme-str 'entry { placeholder: "🎵 Choose Local Music"; }')
  [[ -z "$choice" ]] && exit 1
  for ((i = 0; i < "${#filenames[@]}"; ++i)); do
    if [ "${filenames[$i]}" = "$choice" ]; then
      music_playing && stop_music
      notification "Now Playing:" "$choice"
      mpv "$MUSIC_MARK" --no-video --playlist-start="$i" --loop-playlist "${local_music[@]}"
      break
    fi
  done
}

# Shuffle and play all local music
shuffle_local_music() {
  music_playing && stop_music
  notification "Shuffle Play local music"
  mpv "$MUSIC_MARK" --no-video --shuffle --loop-playlist "$mDIR"
}

# Play selected online music
play_online_music() {
  if [ ! -s "$music_list" ]; then
    notify-send -u low -i "$iDIR/music.png" "No online music found" "Add some with Manage Music"
    exit 0
  fi
  choice=$(awk -F'|' '{print $1}' "$music_list" | sort | rofi -i -dmenu -config "$rofi_theme" \
    -theme-str 'entry { placeholder: "🌐 Choose Online Station"; }')
  [[ -z "$choice" ]] && exit 1
  link=$(awk -F'|' -v name="$choice" '$1 == name {print $2; exit}' "$music_list")
  [[ -z "$link" ]] && {
    notify-send -u low -i "$iDIR/music.png" "URL not found for" "$choice"
    exit 1
  }
  music_playing && stop_music
  notification "Now Playing:" "$choice"
  mpv "$MUSIC_MARK" --no-video --shuffle "$link"
}

# Manage online music list (add, remove, view)
manage_music() {
  sub_choice=$(printf "Add Music\nRemove Music\nView List" | rofi -dmenu \
    -config "$rofi_theme_menu" \
    -theme-str 'entry { placeholder: "🛠️ Manage Music List"; }')

  case "$sub_choice" in
  "Add Music")
    name=$(rofi -dmenu -lines 0 -config "$rofi_theme_menu" \
      -theme-str 'entry { placeholder: "🎼 Enter Music Title"; }')
    [[ -z "$name" ]] && return
    url=$(rofi -dmenu -lines 0 -config "$rofi_theme_menu" \
      -theme-str 'entry { placeholder: "🔗 Enter Music URL"; }')
    [[ -z "$url" ]] && return
    echo "$name|$url" >>"$music_list"
    notification "Added" "$name"
    ;;
  "Remove Music")
    entry=$(awk -F'|' '{print $1}' "$music_list" | rofi -dmenu -config "$rofi_theme_menu" \
      -theme-str 'entry { placeholder: "🗑️ Select Music to Remove"; }')
    [[ -z "$entry" ]] && return
    # By the exact name field. `grep -vF ... && mv` skipped the mv when the last
    # station was removed (grep printed nothing and exited 1) while still saying
    # "Removed", and -F also dropped every station whose line merely contained
    # the name. ENVIRON, not awk -v, so a backslash in the name stays as typed.
    E="$entry" awk -F'|' '$1 != ENVIRON["E"]' "$music_list" >"$music_list.tmp" \
      && mv "$music_list.tmp" "$music_list"
    notification "Removed" "$entry"
    ;;
  "View List")
    # Show only titles, not URLs
    awk -F'|' '{print $1}' "$music_list" | rofi -dmenu -config "$rofi_theme_menu" \
      -theme-str 'entry { placeholder: "📜 Online Music List"; }' >/dev/null
    ;;
  esac
}

# Main menu
user_choice=$(printf "%s\n" \
  "Play from Online Stations" \
  "Play from Music directory" \
  "Shuffle Play from Music directory" \
  "Stop RofiBeats" \
  "Manage Music List" |
  rofi -dmenu -config "$rofi_theme_menu" \
    -theme-str 'entry { placeholder: "🎧 RofiBeats Menu"; }')

case "$user_choice" in
"Play from Online Stations") play_online_music ;;
"Play from Music directory") play_local_music ;;
"Shuffle Play from Music directory") shuffle_local_music ;;
"Stop RofiBeats") music_playing && stop_music ;;
"Manage Music List") manage_music ;;
esac
