#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# For Searching via web browsers

# The search engine lives in UserConfigs/01-UserDefaults.lua. It is a plain Lua
# table (no hl.* calls), so the stock `lua` interpreter can read it.
defaults_file="$HOME/.config/hypr/UserConfigs/01-UserDefaults.lua"

if [[ ! -f "$defaults_file" ]]; then
    echo "Error: $defaults_file not found!"
    exit 1
fi

Search_Engine=$(DEFAULTS="$defaults_file" lua -e 'print(dofile(os.getenv("DEFAULTS")).search_engine or "")')

if [[ -z "$Search_Engine" ]]; then
    echo "Error: search_engine is not set in $defaults_file!"
    exit 1
fi

# Rofi theme and message
rofi_theme="$HOME/.config/rofi/config-search.rasi"
msg='‼️ **note** ‼️ search via default web browser'

# Kill Rofi if already running before execution
if pgrep -x "rofi" >/dev/null; then
    pkill rofi
fi

# Open Rofi and pass the selected query to xdg-open for Google search
echo "" | rofi -dmenu -config "$rofi_theme" -mesg "$msg" | xargs -I{} xdg-open $Search_Engine