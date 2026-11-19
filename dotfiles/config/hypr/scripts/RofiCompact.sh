#!/usr/bin/env bash
# The compact copy of the rofi configs: ~/.cache/rofi-compact holds every
# file of ~/.config/rofi with its pixel sizes and font sizes at FACTOR (0.8).
# rofi has no scale of its own below 1 and the themes are in pixels
# (height: 452px, "Terminess Nerd Font 20"), so on a screen with big pixels
# (DisplayDensity.sh's compact profile) the menus were as oversized as
# everything else. The files in ~/.config/rofi stay as they are.
#
# The wrapper /usr/local/bin/rofi (assets/rofi-compact/rofi in the repo) sends
# rofi to the copy while ~/.cache/rofi-compact/.on exists, and runs this again
# first when a file in ~/.config/rofi is newer than the copy - a theme picked
# in the theme selector, an edit.
#
#   RofiCompact.sh on     build the copy and switch the menus to it
#   RofiCompact.sh off    back to ~/.config/rofi (the copy stays)
#   RofiCompact.sh build  build the copy only (what the wrapper runs)
#
# The wallust colours are not copied: the copy's wallust/ is a link to the
# live folder, so a wallpaper change reaches the compact menus too.

FACTOR=0.8
src="$HOME/.config/rofi"
dst="$HOME/.cache/rofi-compact"

build() {
  [[ -d $src ]] || return
  local tmp="$dst.new"
  rm -rf "$tmp"
  mkdir -p "$tmp"
  # everything but the wallust colours and backups
  (cd "$src" && find . -mindepth 1 -maxdepth 1 ! -name wallust ! -name '*.bak*' -exec cp -a {} "$tmp/" \;)
  ln -s "$src/wallust" "$tmp/wallust"
  # Sizes: every "<n>px" and the size at the end of a font name. A size that
  # is not 0 stays at least 1 px; a font at least 6. Paths: a .rasi under
  # ~/.config/rofi is the one in the copy, except the wallust colours.
  find "$tmp" -type f -name '*.rasi' -print0 | FACTOR=$FACTOR DST="$dst" xargs -0 -r perl -pi -e '
    BEGIN { $f = $ENV{FACTOR}; $dst = $ENV{DST}; ($tilde = $dst) =~ s/^\Q$ENV{HOME}\E/~/; }
    sub px { my $n = shift; return $n if $n == 0; my $r = sprintf("%.0f", $n * $f); $r = 1 if $r < 1; $r }
    s/(?<![\w.])(\d+(?:\.\d+)?)px\b/px($1)."px"/ge;
    s/(font:\s*"[^"]*?\s)(\d+(?:\.\d+)?)"/my $s = sprintf("%.0f", $2 * $f); $s = 6 if $s < 6; $1.$s."\""/ge;
    s{~/\.config/rofi/(?!wallust/)([^"\x27\s]*\.rasi)}{$tilde/$1}g;
    s{\Q$ENV{HOME}\E/\.config/rofi/(?!wallust/)([^"\x27\s]*\.rasi)}{$dst/$1}g;
  '
  # keep the switch across a rebuild
  [[ -e $dst/.on ]] && touch "$tmp/.on"
  touch "$tmp/.stamp"
  rm -rf "$dst.old"
  [[ -e $dst ]] && mv "$dst" "$dst.old"
  mv "$tmp" "$dst"
  rm -rf "$dst.old"
}

case $1 in
  on) build; touch "$dst/.on" ;;
  off) rm -f "$dst/.on" ;;
  build) build ;;
  *) echo "usage: $0 on|off|build" >&2; exit 2 ;;
esac
