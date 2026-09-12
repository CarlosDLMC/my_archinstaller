#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# Searchable keybinds using rofi.
#
# The list comes from `hyprctl binds`, i.e. the binds Hyprland actually has
# loaded right now - the Lua config builds binds in loops and helper functions,
# so parsing the config files by hand would miss half of them. A bind shows its
# description; give every hl.bind() one, or it lists as "(no description)".

# kill yad to not interfere with these binds
pkill yad || true

if pidof rofi > /dev/null; then
  pkill rofi
fi

rofi_theme="$HOME/.config/rofi/config-keybinds.rasi"
msg='☣️ NOTE ☣️: Clicking with Mouse or Pressing ENTER will have NO function'

# MODS+KEY — DESCRIPTION, one per bind, deduplicated, SUPER first
display_keybinds=$(hyprctl -j binds | jq -r '
  def mods: [ (if (.modmask / 64 | floor) % 2 == 1 then "SUPER" else empty end),
              (if (.modmask / 4  | floor) % 2 == 1 then "CTRL"  else empty end),
              (if (.modmask / 8  | floor) % 2 == 1 then "ALT"   else empty end),
              (if (.modmask % 2) == 1              then "SHIFT" else empty end) ];
  # keycodes 10..19 are the digit row 1..9,0
  def keyname: if .keycode > 0 then
                 (if .keycode >= 10 and .keycode <= 18 then (.keycode - 9 | tostring)
                  elif .keycode == 19 then "0" else "code:\(.keycode)" end)
               else .key end;
  def combo: (mods + [keyname]) | join("+");
  def action: if .has_description and .description != "" then .description
              elif .dispatcher == "__lua" then "(no description)"
              else "\(.dispatcher) \(.arg)" end;
  [ .[] | select(.submap == "") | "\(combo) — \(action)" ] | unique | .[]
')

if [[ -z "$display_keybinds" ]]; then
  echo "no keybinds found."
  exit 1
fi

printf '%s\n' "$display_keybinds" | rofi -dmenu -i -config "$rofi_theme" -mesg "$msg"
