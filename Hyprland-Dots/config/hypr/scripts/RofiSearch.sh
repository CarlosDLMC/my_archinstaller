#!/usr/bin/env bash
# For Searching via web browsers

# The search engine lives in mango's defaults.conf (var=search_engine,...).
defaults_file="$HOME/.config/mango/defaults.conf"

if [[ ! -f "$defaults_file" ]]; then
    echo "Error: $defaults_file not found!"
    exit 1
fi

Search_Engine=$(sed -n 's/^var=search_engine,//p' "$defaults_file" | tail -n 1)

if [[ -z "$Search_Engine" ]]; then
    echo "Error: search_engine is not set in $defaults_file!"
    exit 1
fi

# Rofi theme and message
rofi_theme="$HOME/.config/rofi/config-search.rasi"
msg='Поиск откроется в браузере по умолчанию'

# Kill Rofi if already running before execution
if pgrep -x "rofi" >/dev/null; then
    pkill rofi
fi

# Open Rofi and pass the selected query to xdg-open for Google search
echo "" | rofi -dmenu -config "$rofi_theme" -mesg "$msg" | xargs -I{} xdg-open $Search_Engine