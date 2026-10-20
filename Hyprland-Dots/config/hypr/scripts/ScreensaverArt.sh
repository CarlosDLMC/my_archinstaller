#!/usr/bin/env bash
# Screensaver art for this screen: one ~/.local/share/screensaver/art/<name>.txt
# for each image in ~/.local/share/screensaver/images/, made by ImgToText.py as
# tall as a fullscreen foot minus 2 rows - and narrower, if it would come
# within 2 columns of the sides.
#
#   ScreensaverArt.sh [IMAGE...]   default: every image in images/
#   ScreensaverArt.sh --new        only the images that never had art made here
#
# Startup_Apps.lua runs it with --new at every login: on a fresh install that
# is every image; after an installer re-run, the images it brought (all of
# them on a machine installed before the art existed); otherwise nothing, and
# nothing opens. art/.made lists the images done, so a piece you delete from
# art/ is not made again. Run it by hand, without --new, after changing
# monitors or the foot font. A different <name>.txt already there is kept as
# <name>.txt.backup-<date-time> (Screensaver.sh only reads *.txt).

dir="$HOME/.local/share/screensaver"
art_dir="$dir/art"
# The images whose art has been made, one name per line.
made="$art_dir/.made"

fail() {
  notify-send "Screensaver art" "$1"
  echo "$1" >&2
  exit 1
}

mark_made() {
  grep -qxF -- "$1" "$made" 2>/dev/null || echo "$1" >>"$made"
}

shopt -s nullglob nocaseglob
new=false
if [[ ${1-} == --new ]]; then
  new=true
  shift
fi
srcs=("$@")
((${#srcs[@]})) || srcs=("$dir/images"/*.{png,jpg,jpeg,webp})
if $new; then
  # An image with a <name>.txt but no line in .made had its art made before
  # the list existed, or by hand: counted as done and left alone.
  pick=()
  for src in "${srcs[@]}"; do
    name=$(basename "${src%.*}")
    grep -qxF -- "$name" "$made" 2>/dev/null && continue
    if [[ -f $art_dir/$name.txt ]]; then
      mark_made "$name"
      continue
    fi
    pick+=("$src")
  done
  ((${#pick[@]})) || exit 0
  srcs=("${pick[@]}")
fi
((${#srcs[@]})) || fail "No images in $dir/images"
for src in "${srcs[@]}"; do
  [[ -f $src ]] || fail "No image at $src"
done
command -v foot >/dev/null || fail "foot is not installed"

# The monitor the measuring window opens on, and its pixels as it shows them.
# Hyprland reports the mode's width and height, so on a monitor turned on its
# side (an odd transform: 90 or 270 degrees, flipped or not) they swap.
read -r mon_w mon_h mon_t < <(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.width) \(.height) \(.transform)"')
if [[ $mon_t =~ ^[0-9]+$ ]] && ((mon_t % 2)); then
  read -r mon_w mon_h <<<"$mon_h $mon_w"
fi

# A terminal's rows and columns can only be read from inside one: a
# fullscreen foot, black and opaque, for a moment. It opens at 80x24 and is
# resized once Hyprland has made it fullscreen, so wait for that first.
size_file=$(mktemp)
foot --fullscreen --app-id screensaver-measure -o colors-dark.alpha=1.0 \
  bash -c 'printf "\033[?25l"
    d=$((SECONDS + 3))
    while ((SECONDS < d)) && [[ $(stty size) == "24 80" ]]; do sleep 0.02; done
    sleep 0.2
    stty size > "$1"' _ "$size_file"
read -r rows cols <"$size_file"
rm -f "$size_file"
[[ $rows =~ ^[0-9]+$ && $cols =~ ^[0-9]+$ ]] && ((rows > 2 && cols > 2)) ||
  fail "Could not measure the terminal"

# A cell's height over its width: the monitor's pixels over the terminal's
# rows and columns (foot has no padding here). C locale: a decimal comma
# would not parse as --cell-aspect.
aspect=$(LC_ALL=C awk -v w="$mon_w" -v h="$mon_h" -v c="$cols" -v r="$rows" \
  'BEGIN { if (w > 0 && h > 0) printf "%.3f", (h / r) / (w / c); else print 2.4 }')
echo "${cols}x${rows} terminal, cell aspect $aspect"

mkdir -p "$art_dir"
# Writes $tmp from $src, prints its width in columns.
make_art() {
  "$HOME/.config/hypr/scripts/ImgToText.py" "$src" "$tmp" --rows "$1" \
    --mode block --cell-aspect "$aspect" | sed -nE 's/.*: ([0-9]+) cols.*/\1/p'
}

failed=()
for src in "${srcs[@]}"; do
  name=$(basename "${src%.*}")
  out="$art_dir/$name.txt"
  tmp="$out.tmp"
  r=$((rows - 2))
  width=$(make_art "$r")
  if [[ -n $width ]] && ((width > cols - 2)); then
    r=$((r * (cols - 2) / width))
    width=$(make_art "$r")
  fi
  if [[ -z $width ]]; then
    rm -f "$tmp"
    failed+=("$name")
    echo "  $name: ImgToText.py failed" >&2
    continue
  fi

  if [[ -f $out ]] && cmp -s "$tmp" "$out"; then
    rm -f "$tmp"
    mark_made "$name"
    echo "  $name: unchanged (${width}x${r})"
    continue
  fi
  [[ -f $out ]] && cp -p "$out" "$out.backup-$(date +%Y%m%d-%H%M%S)"
  mv -f "$tmp" "$out"
  mark_made "$name"
  echo "  $name: ${width}x${r}"
done

((${#failed[@]})) && fail "ImgToText.py failed on: ${failed[*]}"
exit 0
