#!/usr/bin/env bash
# Interface size from the pixel density of the screen you look at.
#
# The default sizes were made on screens with small pixels (a 24" 2560x1440
# at ~123 PPI, a 14" 1920x1080 laptop at ~157 PPI). On a screen with big pixels
# (a 27" 1920x1080 is ~81 PPI) the same pixel sizes look about 1.5x larger.
# Lowering the monitor scale instead (0.8) blurs text, so this changes the
# font sizes and keeps the scale at 1.
#
# The deciding screen is the physically widest external output; without one,
# the widest output (the laptop panel, or a desktop's only monitor). Below
# COMPACT_BELOW_PPI it applies the compact sizes, otherwise the normal ones.
# A screen that reports no physical size (some TVs, projectors) gets normal.
#
# Changed by it: GTK text scaling (LibreWolf follows it too), qt5ct/qt6ct
# fonts, the rofi font and the dunst font. foot is not touched: with
# dpi-aware=yes it already sizes its font from the monitor's real DPI.
#
# Runs at login (mango/startup.conf). After swapping monitors in a session,
# run it again (Quick Settings > «Размер интерфейса»); apps that are already
# open keep their old size until restarted.
#
# Usage: DisplayDensity.sh [--login] [normal|compact]   (no profile: decide by PPI)
#   --login: notify only when the profile changed (startup.conf); without it
#   (the menu) it always says what it chose.

COMPACT_BELOW_PPI=100

# profile: GTK text scale, Qt general, Qt fixed, rofi, dunst
NORMAL=(1.0 14 12 16 16)
COMPACT=(0.8 11 10 13 13)

iDIR="$HOME/.config/hypr/notify/images"
state="$HOME/.cache/display-density"

login=0
[[ $1 == --login ]] && { login=1; shift; }
profile="$1"
if [[ -z $profile ]]; then
  # name, physical width in mm, current mode width in px, one line per enabled output
  outputs=$(wlr-randr --json 2>/dev/null | jq -r '.[] | select(.enabled)
    | [.name, .physical_size.width, (.modes[] | select(.current) | .width)] | @tsv')
  pick=$(awk -F'\t' '$2 > 0 && $1 !~ /^(eDP|LVDS|DSI)/' <<<"$outputs" | sort -t$'\t' -k2,2nr | head -1)
  [[ -z $pick ]] && pick=$(awk -F'\t' '$2 > 0' <<<"$outputs" | sort -t$'\t' -k2,2nr | head -1)

  profile=normal
  if [[ -n $pick ]]; then
    IFS=$'\t' read -r name mm px <<<"$pick"
    ppi=$(( px * 254 / (mm * 10) ))
    (( ppi < COMPACT_BELOW_PPI )) && profile=compact
  fi
fi

case $profile in
  normal) v=("${NORMAL[@]}") ;;
  compact) v=("${COMPACT[@]}") ;;
  *) echo "usage: $0 [normal|compact]" >&2; exit 2 ;;
esac

# GTK (and LibreWolf, which takes its scale from it)
gsettings set org.gnome.desktop.interface text-scaling-factor "${v[0]}"

# Qt: the size is the second field of the font string
for f in "$HOME/.config/qt5ct/qt5ct.conf" "$HOME/.config/qt6ct/qt6ct.conf"; do
  [[ -f $f ]] || continue
  sed -i -E "s/^(general=\"[^,]*,)[0-9]+,/\1${v[1]},/; s/^(fixed=\"[^,]*,)[0-9]+,/\1${v[2]},/" "$f"
done

# rofi: every "font: ... N" line in the shared font file
f="$HOME/.config/rofi/0-shared-fonts.rasi"
[[ -f $f ]] && sed -i -E "s/^(font: \"[^\"]* )[0-9]+\";/\1${v[3]}\";/" "$f"

# dunst: the global font line
f="$HOME/.config/dunst/dunstrc"
if [[ -f $f ]] && ! grep -qE "^\s*font = .* ${v[4]}\s*$" "$f"; then
  sed -i -E "s/^(\s*font = .* )[0-9]+\s*$/\1${v[4]}/" "$f"
  pidof dunst >/dev/null && dunstctl reload
fi

# At login, say so only when the profile changed; from the menu, always.
last=$(cat "$state" 2>/dev/null)
echo "$profile" >"$state"
if (( ! login )) || [[ $profile != "$last" ]]; then
  case $profile in
    compact) label="компактный" ;;
    *) label="обычный" ;;
  esac
  notify-send -u low -i "$iDIR/note.png" "Размер интерфейса: $label" \
    "${name:+$name, ${ppi} PPI. }Открытые приложения изменятся после перезапуска."
fi
exit 0
