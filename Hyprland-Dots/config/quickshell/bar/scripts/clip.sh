#!/usr/bin/env bash
# Clipboard history for the bar's picker, on top of cliphist.
#
# Omarchy's clipboard plugin runs its own `wl-paste --watch` capture because
# Omarchy does not ship cliphist. This machine does, with its history already
# populated and image capture already running, so only the picker is replaced -
# the store stays exactly as it was.
#
# Everything addresses entries by cliphist's id. `cliphist decode` wants the
# whole "<id>\t<preview>" line rather than the id alone, and previews contain
# arbitrary text - quotes, tabs, newlines, shell metacharacters - so the line is
# never reconstructed or passed through an argument: it is looked up here and
# piped straight back into cliphist.
#
# Subcommands:
#   (listing is NOT here: the picker reads `cliphist list` itself and parses it
#   in one pass. Going through jq cost 28ms and doubled the payload.)
#   thumb <id> <f>  decode an image entry to <f>
#   copy  <id>      put the entry on the clipboard
#   delete <id>     remove one entry
#   wipe            remove everything

set -uo pipefail

line_for() {
  # No `exit` in the awk: exiting on the first match closes the pipe, cliphist
  # takes SIGPIPE, and `set -o pipefail` then reports the whole lookup as
  # failed - so every decode aborted even though the line had been found. The
  # list is a few hundred lines; reading all of it costs nothing.
  cliphist list 2>/dev/null | awk -F'\t' -v want="$1" '$1 == want && !seen { print; seen = 1 }'
}

# How many decoded previews to keep on disk at once. The list shows about ten
# rows plus one large preview, so a dozen covers what can be on screen. Without
# a cap this directory grew to 72MB of full-size screenshots - every one of
# them a byte-for-byte duplicate of something cliphist already stores.
#
# Downscaling them instead was measured and rejected: `magick -resize 900x900`
# takes 489ms against 25ms to decode, which would be felt on every scroll.
THUMB_KEEP=12

cmd_thumb() {
  local line out dir
  line=$(line_for "$1") || exit 1
  [[ -n $line ]] || exit 1
  out=$2
  dir=$(dirname "$out")
  mkdir -p "$dir"
  printf '%s' "$line" | cliphist decode > "$out" 2>/dev/null || exit 1
  [[ -s $out ]] || { rm -f "$out"; exit 1; }

  # Drop all but the newest THUMB_KEEP, so a long scroll cannot fill the disk.
  ls -1t "$dir" 2>/dev/null | tail -n +$((THUMB_KEEP + 1)) | while IFS= read -r old_file; do
    [[ -n $old_file ]] && rm -f -- "$dir/$old_file"
  done

  printf '%s\n' "$out"
}

# Everything here is reconstructible from cliphist in 25ms a piece, so nothing
# is kept between uses of the picker.
cmd_thumbclean() {
  local dir=$1
  [[ -n $dir && $dir == *clip-thumbs ]] || exit 2
  rm -f -- "$dir"/*.img 2>/dev/null
  exit 0
}

cmd_copy() {
  local line
  line=$(line_for "$1") || exit 1
  [[ -n $line ]] || exit 1
  printf '%s' "$line" | cliphist decode | wl-copy
}

cmd_delete() {
  local line
  line=$(line_for "$1") || exit 1
  [[ -n $line ]] || exit 1
  printf '%s' "$line" | cliphist delete
}

case "${1:-}" in
  thumb)  cmd_thumb "${2:?id}" "${3:?outfile}" ;;
  thumbclean) cmd_thumbclean "${2:?dir}" ;;
  copy)   cmd_copy "${2:?id}" ;;
  delete) cmd_delete "${2:?id}" ;;
  wipe)   cliphist wipe ;;
  *) echo "usage: clip.sh thumb <id> <file>|thumbclean <dir>|copy <id>|delete <id>|wipe" >&2; exit 2 ;;
esac
