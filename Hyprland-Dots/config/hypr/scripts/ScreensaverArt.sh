#!/usr/bin/env bash
# Screensaver art for this screen: ~/.local/share/screensaver/art.txt, made
# from an image by ImgToText.py as tall as a fullscreen foot minus 2 rows -
# and narrower, if it would come within 2 columns of the sides.
#
#   ScreensaverArt.sh [IMAGE]   default: ~/.local/share/screensaver/mosfilm_logo.png
#
# initial-boot.sh runs it once, at the first login. Run it again by hand after
# changing monitors or the foot font. A different art.txt already there is
# kept as art.txt.backup-<date-time>.

dir="$HOME/.local/share/screensaver"
src="${1:-$dir/mosfilm_logo.png}"
out="$dir/art.txt"

fail() {
  notify-send "Screensaver art" "$1"
  echo "$1" >&2
  exit 1
}

[[ -f $src ]] || fail "No image at $src"
command -v foot >/dev/null || fail "foot is not installed"

# The monitor the measuring window opens on, and its pixels.
read -r mon_w mon_h < <(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.width) \(.height)"')

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

tmp="$out.tmp"
mkdir -p "$dir"
# Writes $tmp, prints its width in columns.
make_art() {
  "$HOME/.config/hypr/scripts/ImgToText.py" "$src" "$tmp" --rows "$1" \
    --mode block --cell-aspect "$aspect" | sed -nE 's/.*: ([0-9]+) cols.*/\1/p'
}

r=$((rows - 2))
width=$(make_art "$r")
[[ -n $width ]] || fail "ImgToText.py failed on $src"
if ((width > cols - 2)); then
  r=$((r * (cols - 2) / width))
  width=$(make_art "$r")
  [[ -n $width ]] || fail "ImgToText.py failed on $src"
fi

if [[ -f $out ]] && cmp -s "$tmp" "$out"; then
  rm -f "$tmp"
  echo "$out is already this art (${width}x${r} for a ${cols}x${rows} terminal)"
  exit 0
fi
[[ -f $out ]] && cp -p "$out" "$out.backup-$(date +%Y%m%d-%H%M%S)"
mv -f "$tmp" "$out"
echo "$out: ${width}x${r} for a ${cols}x${rows} terminal (cell aspect $aspect)"
