#!/usr/bin/env bash
# Interface size from the pixel density of the screens, so a new machine with
# any monitor looks like the screens this desktop was made on: a 24" 2560x1440
# (~123 PPI) and a 14" 1920x1080 laptop panel (~157 PPI, read from closer).
#
# Two things are decided, per login:
#
#  1. The monitor scale, for screens with SMALL pixels (4K and the like). Each
#     output gets the scale from 1, 1.25, 1.5, 1.75, 2 that brings its PPI
#     closest to the target (123 for a monitor, 155 for a laptop panel): a 27"
#     4K gets 1.25, a 24" 4K 1.5, a 14" 4K laptop 2. Never below 1 - scaling
#     down (0.8 on a 27" 1080p) made text uneven. The scales are written as
#     monitor_rule lines to ~/.config/mango/monitors.conf, between two marker
#     lines, and only while that file has no rules of its own: with anything
#     else in it (your layout, a monitor profile) the scales are left to you.
#
#  2. The font sizes, for a main screen with BIG pixels: below 100 PPI after
#     scaling (a 27" 1920x1080 is ~81) everything goes to 80%, otherwise to
#     its normal size:
#       - GTK text scaling (LibreWolf follows it) and the qt5ct/qt6ct fonts;
#       - the notifications: a drop-in, dunst/dunstrc.d/90-display-density.conf,
#         made from dunstrc with its widths, paddings and font sizes scaled
#         (dunstrc itself is not changed; the drop-in is removed for normal);
#       - the rofi menus: RofiCompact.sh keeps a copy of ~/.config/rofi with
#         every pixel and font size scaled, and the /usr/local/bin/rofi
#         wrapper sends rofi to it.
#     The main screen is the physically widest external output; without one,
#     the widest output. foot is not touched (dpi-aware=yes sizes its font
#     from the real DPI) and neither is the bar (it does the same per output,
#     bar.rs density).
#
# A screen that reports no physical size (some TVs, projectors) gets scale 1
# and the normal sizes.
#
# Runs at login (mango/startup.conf). After swapping monitors in a session,
# run it again (Quick Settings > «Размер интерфейса»); apps that are already
# open keep their old font size until restarted.
#
# Usage: DisplayDensity.sh [--login] [normal|compact]
#          --login: notify only when something changed (startup.conf); without
#          it (the menu) it always says what it chose. A profile name forces
#          the font sizes and leaves the scales alone.
#        DisplayDensity.sh --plan [FILE]
#          Print what would be decided and change nothing. FILE: outputs to
#          decide for instead of the connected ones, one per line, tab
#          separated: name, physical width in mm, mode width in px.

COMPACT_BELOW_PPI=100
TARGET_PPI_MONITOR=123
TARGET_PPI_PANEL=155
SCALES="1 1.25 1.5 1.75 2"

# profile: GTK text scale, Qt general, Qt fixed
NORMAL=(1.0 14 12)
COMPACT=(0.8 11 10)
# what the compact profile does to the notifications (RofiCompact.sh has its own)
COMPACT_FACTOR=0.8

iDIR="$HOME/.config/hypr/notify/images"
state="$HOME/.cache/display-density"
monitors="$HOME/.config/mango/monitors.conf"
STOCK_RULE='monitor_rule=name:.*,vrr:1'
BEGIN='# DisplayDensity.sh begin (generated: the scales for this machine'"'"'s screens)'
END='# DisplayDensity.sh end'

# name, physical width in mm, mode width in px - one line per enabled output
connected() {
  # for tests: DISPLAY_DENSITY_OUTPUTS=FILE stands in for the connected outputs
  [[ -n $DISPLAY_DENSITY_OUTPUTS ]] && { cat "$DISPLAY_DENSITY_OUTPUTS"; return; }
  wlr-randr --json 2>/dev/null | jq -r '.[] | select(.enabled)
    | [.name, .physical_size.width, (.modes[] | select(.current) | .width)] | @tsv'
}

# stdin: the outputs. stdout, per output: name, PPI, scale, PPI after scaling
# (0 0-PPI lines for a screen with no size); the main screen's line is last
# and starts with "main".
decide() {
  awk -F'\t' -v scales="$SCALES" -v tm="$TARGET_PPI_MONITOR" -v tp="$TARGET_PPI_PANEL" '
    function abs(x) { return x < 0 ? -x : x }
    {
      name = $1; mm = $2; px = $3
      panel = (name ~ /^(eDP|LVDS|DSI)/)
      ppi = 0; scale = 1
      if (mm > 0) {
        ppi = px * 25.4 / mm
        target = panel ? tp : tm
        n = split(scales, s, " ")
        for (i = 1; i <= n; i++)
          if (abs(ppi / s[i] - target) < abs(ppi / scale - target)) scale = s[i]
      }
      printf "%s\t%d\t%s\t%d\n", name, ppi, scale, ppi / scale
      # the main screen: the widest external one, else the widest panel,
      # else one with no size
      rank = mm > 0 ? (panel ? 1 : 2) : 0
      if (main == "" || rank > mainrank || rank == mainrank && mm > mainmm) {
        main = name; mainmm = mm; mainrank = rank; maineff = ppi / scale
      }
    }
    END { if (main != "") printf "main\t%s\t%d\n", main, maineff }'
}

# The monitor rules for these decisions: one rule for each scaled output and
# a catch-all for the rest. Exactly one rule may match an output (mango takes
# the first match when an output appears and the last on a reload), hence the
# catch-all that leaves the scaled ones out.
rules() {
  local scaled
  scaled=$(awk -F'\t' '$1 != "main" && $3 != 1 { print $1 "\t" $3 }' <<<"$1")
  if [[ -z $scaled ]]; then
    echo "$STOCK_RULE"
    return
  fi
  echo "$BEGIN"
  awk -F'\t' '{ printf "monitor_rule=name:^%s$,scale:%s,vrr:1\n", $1, $2 }' <<<"$scaled"
  echo "monitor_rule=name:^(?!($(cut -f1 <<<"$scaled" | paste -sd'|'))\$).*\$,vrr:1"
  echo "$END"
}

# Write the rules into monitors.conf - only when the file has no rules but the
# stock catch-all or an earlier generated block. Prints "changed" if it wrote.
write_rules() {
  [[ -f $monitors ]] || return
  local new="$1" own cur
  # what the file says outside a generated block, comments and blanks aside
  own=$(sed "/^# DisplayDensity.sh begin/,/^# DisplayDensity.sh end/d" "$monitors" | grep -vE '^\s*(#|$)')
  if grep -q '^# DisplayDensity.sh begin' "$monitors"; then
    [[ -n $own ]] && return
    cur=$(sed -n "/^# DisplayDensity.sh begin/,/^# DisplayDensity.sh end/p" "$monitors")
  else
    [[ $own == "$STOCK_RULE" ]] || return
    cur=$STOCK_RULE
  fi
  [[ $cur == "$new" ]] && return
  local tmp
  tmp=$(mktemp)
  {
    # everything but the old rules, then the new ones
    sed "/^# DisplayDensity.sh begin/,/^# DisplayDensity.sh end/d" "$monitors" | grep -vxF "$STOCK_RULE"
    echo "$new"
  } >"$tmp"
  cat "$tmp" >"$monitors"   # in place: mango watches this file
  rm -f "$tmp"
  echo changed
}

if [[ $1 == --plan ]]; then
  if [[ -n $2 ]]; then outputs=$(cat "$2"); else outputs=$(connected); fi
  plan=$(decide <<<"$outputs")
  echo "output / PPI / scale / PPI after scaling:"
  grep -v '^main' <<<"$plan" | column -t -s$'\t'
  IFS=$'\t' read -r _ name eff <<<"$(grep '^main' <<<"$plan")"
  profile=normal
  (( eff > 0 && eff < COMPACT_BELOW_PPI )) && profile=compact
  echo "main screen: ${name:-none} (${eff:-0} PPI) -> $profile fonts"
  echo "monitor rules:"
  rules "$plan"
  exit 0
fi

login=0
[[ $1 == --login ]] && { login=1; shift; }
profile="$1"
scales_changed=""
if [[ -z $profile ]]; then
  plan=$(decide <<<"$(connected)")
  scales_changed=$(write_rules "$(rules "$plan")")
  IFS=$'\t' read -r _ name eff <<<"$(grep '^main' <<<"$plan")"
  ppi=$eff
  profile=normal
  (( eff > 0 && eff < COMPACT_BELOW_PPI )) && profile=compact
fi

case $profile in
  normal) v=("${NORMAL[@]}") ;;
  compact) v=("${COMPACT[@]}") ;;
  *) echo "usage: $0 [--login] [normal|compact] | --plan [FILE]" >&2; exit 2 ;;
esac

# GTK (and LibreWolf, which takes its scale from it)
gsettings set org.gnome.desktop.interface text-scaling-factor "${v[0]}"

# Qt: the size is the second field of the font string
for f in "$HOME/.config/qt5ct/qt5ct.conf" "$HOME/.config/qt6ct/qt6ct.conf"; do
  [[ -f $f ]] || continue
  sed -i -E "s/^(general=\"[^,]*,)[0-9]+,/\1${v[1]},/; s/^(fixed=\"[^,]*,)[0-9]+,/\1${v[2]},/" "$f"
done

# rofi: the compact copy of its configs, on or off
rofi_compact="$HOME/.config/hypr/scripts/RofiCompact.sh"
if [[ -x $rofi_compact ]]; then
  if [[ $profile == compact ]]; then "$rofi_compact" on; else "$rofi_compact" off; fi
fi

# dunst: a drop-in with dunstrc's sizes scaled - the card's width, height and
# offset, its paddings and gap, the progress bar, the body font and the font
# of every format's stamp (font_desc='... N'), each under its own section.
dunstrc="$HOME/.config/dunst/dunstrc"
dropin="$HOME/.config/dunst/dunstrc.d/90-display-density.conf"
dunst_new=""
if [[ $profile == compact && -f $dunstrc ]]; then
  dunst_new=$(F=$COMPACT_FACTOR perl -ne '
    BEGIN { $f = $ENV{F}; print "# Generated by DisplayDensity.sh from dunstrc (compact profile): do not edit.\n" }
    sub sc { my $n = shift; return $n if $n == 0; my $r = sprintf("%.0f", $n * $f); abs($r) < 1 ? ($n < 0 ? -1 : 1) : $r }
    sub emit { if ($sec ne $last) { print "\n[$sec]\n"; $last = $sec } print "    $_[0]\n" }
    if (/^\s*\[(.+)\]\s*$/) { $sec = $1; next }
    next if /^\s*[#;]/ || !defined $sec;
    if (/^\s*(width|height|offset|padding|horizontal_padding|gap_size|progress_bar_height|progress_bar_min_width|progress_bar_max_width|text_icon_padding|min_icon_size|max_icon_size)\s*=\s*(.*?)\s*$/) {
      my ($k, $v) = ($1, $2); $v =~ s/(-?\d+)/sc($1)/ge; emit("$k = $v");
    } elsif (/^\s*font\s*=\s*(.*\D)\s(\d+(?:\.\d+)?)\s*$/) {
      emit("font = $1 " . sc($2));
    } elsif (/^\s*format\s*=/ && /font_desc=/) {
      (my $l = $_) =~ s/^\s+|\s+$//g; $l =~ s/(font_desc=\x27[^\x27]*?\s)(\d+(?:\.\d+)?)\x27/$1 . sc($2) . "\x27"/ge; emit($l);
    }' "$dunstrc")
fi
if [[ $dunst_new != "$(cat "$dropin" 2>/dev/null)" ]]; then
  if [[ -n $dunst_new ]]; then
    mkdir -p "${dropin%/*}"
    echo "$dunst_new" >"$dropin"
  else
    rm -f "$dropin"
  fi
  pidof dunst >/dev/null && dunstctl reload
fi

# At login, say so only when something changed; from the menu, always.
last=$(cat "$state" 2>/dev/null)
echo "$profile" >"$state"
if (( ! login )) || [[ $profile != "$last" || -n $scales_changed ]]; then
  case $profile in
    compact) label="компактный" ;;
    *) label="обычный" ;;
  esac
  notify-send -u low -i "$iDIR/note.png" "Размер интерфейса: $label" \
    "${name:+$name, ${ppi} PPI. }${scales_changed:+Масштаб мониторов обновлён. }Открытые приложения изменятся после перезапуска."
fi
exit 0
