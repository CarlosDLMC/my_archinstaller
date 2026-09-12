#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# Quick Cheat Sheet — generated LIVE from `hyprctl binds`, i.e. the keybinds
# Hyprland has loaded right now, so it never drifts out of date. Add a keybind
# with a description in the Lua config -> it shows here automatically.

# GDK BACKEND. Change to either wayland or x11 if having issues
BACKEND=wayland

# Kill any running rofi/yad instance
pidof rofi >/dev/null && pkill rofi
pidof yad  >/dev/null && pkill yad

# Glyph shown in place of the SUPER modifier (Nerd Font "penguin", U+EBC6)
super_glyph=$''

rows=( "ESC" "close this cheat sheet" )
rows+=( "SUPER SHIFT K" "searchable keybinds (rofi)" )
rows+=( "──────────" "Keybinds (live)" )

# "keys<TAB>action" per bind; SUPER binds first, then by key
while IFS=$'\t' read -r k d; do
  rows+=( "$k" "$d" )
done < <(hyprctl -j binds | jq -r --arg sk "$super_glyph" '
  def mods: [ (if (.modmask / 64 | floor) % 2 == 1 then $sk    else empty end),
              (if (.modmask / 4  | floor) % 2 == 1 then "CTRL"  else empty end),
              (if (.modmask / 8  | floor) % 2 == 1 then "ALT"   else empty end),
              (if (.modmask % 2) == 1              then "SHIFT" else empty end) ];
  def keyname: if .keycode > 0 then
                 (if .keycode >= 10 and .keycode <= 18 then (.keycode - 9 | tostring)
                  elif .keycode == 19 then "0" else "code:\(.keycode)" end)
               else .key end;
  def action: if .has_description and .description != "" then .description
              elif .dispatcher == "__lua" then "(no description)"
              else "\(.dispatcher) \(.arg)" end;
  [ .[] | select(.submap == "")
        | { sort: [ (if (.modmask / 64 | floor) % 2 == 1 then 0 else 1 end), .modmask, keyname ],
            line: "\((mods + [keyname]) | join(" "))\t\(action)" } ]
  | unique_by(.line) | sort_by(.sort) | .[].line
')

rows+=( "──────────" "wiki: wiki.hypr.land/Configuring/Core/Binds" )

GDK_BACKEND=$BACKEND yad \
    --width=1100 --height=1000 \
    --center \
    --title="KooL Quick Cheat Sheet" \
    --no-buttons \
    --list \
    --column=Keys: \
    --column=Action: \
    "${rows[@]}"
