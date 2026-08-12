#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# Quick Cheat Sheet — generated LIVE from the actual Hyprland keybind configs,
# so it never drifts out of date. Every descriptive bind (bindd/binded/bindlnd/
# bindmd/...) is listed; non-descriptive binds (bind/binde) are picked up from
# their trailing "# comment". Add a keybind -> it shows here automatically.

# GDK BACKEND. Change to either wayland or x11 if having issues
BACKEND=wayland

# Kill any running rofi/yad instance
pidof rofi >/dev/null && pkill rofi
pidof yad  >/dev/null && pkill yad

hypr_dir="$HOME/.config/hypr"

# Keybind files in source order (see hyprland.conf), as "path:section label"
files=(
  "$hypr_dir/configs/Keybinds.conf:Default keybinds"
  "$hypr_dir/configs/Laptops.conf:Laptop keys (default)"
  "$hypr_dir/UserConfigs/Laptops.conf:Laptop keys (user)"
  "$hypr_dir/UserConfigs/UserKeybinds.conf:Your keybinds"
)

# Glyph shown in place of the SUPER modifier (Nerd Font "penguin", U+EBC6)
super_glyph=$''

# Emit "keys<TAB>action" for every bind in a file
parse() {
  awk -v sk="$super_glyph" '
    function trim(s){ gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /^[ \t]*bind[a-z]*[ \t]*=/ {
      line=$0
      # header token (e.g. "bindd") -> flags after "bind"; a "d" flag = has description
      hdr=line; sub(/[ \t]*=.*$/, "", hdr); sub(/^[ \t]*/, "", hdr)
      flags=hdr; sub(/^bind/, "", flags)
      hasdesc = (flags ~ /d/)
      # peel a trailing " # comment" (Hyprland inline comment) for non-descriptive binds
      comment=""
      if (match(line, /[ \t]#/)) { comment=trim(substr(line, RSTART+2)); line=substr(line,1,RSTART-1) }
      n=split(line, a, ",")
      mods=a[1]; sub(/^[ \t]*bind[a-z]*[ \t]*=[ \t]*/, "", mods); mods=trim(mods)
      key=trim(a[2])
      if (hasdesc) { desc=trim(a[3]); cs=4 } else { desc=comment; cs=3 }
      # fall back to the dispatcher/command when there is no description at all
      if (desc=="") { cmd=""; for(i=cs;i<=n;i++) cmd=cmd (i>cs?",":"") a[i]; desc=trim(cmd) }
      gsub(/\$mainMod/, sk, mods)
      keys = (mods=="" ? key : mods " " key)
      printf "%s\t%s\n", keys, desc
    }
  ' "$1"
}

rows=( "ESC" "close this cheat sheet" )
rows+=( "SUPER SHIFT K" "searchable keybinds (rofi)" )

for entry in "${files[@]}"; do
  f="${entry%%:*}"; label="${entry#*:}"
  [ -f "$f" ] || continue
  mapfile -t parsed < <(parse "$f")
  [ "${#parsed[@]}" -eq 0 ] && continue
  rows+=( "──────────" "$label" )
  for l in "${parsed[@]}"; do
    IFS=$'\t' read -r k d <<< "$l"
    rows+=( "$k" "$d" )
  done
done

rows+=( "──────────" "wiki: github.com/JaKooLit/Hyprland-Dots/wiki" )

GDK_BACKEND=$BACKEND yad \
    --width=1100 --height=1000 \
    --center \
    --title="KooL Quick Cheat Sheet" \
    --no-buttons \
    --list \
    --column=Keys: \
    --column=Action: \
    "${rows[@]}"
