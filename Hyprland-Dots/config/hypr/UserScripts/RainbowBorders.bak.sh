#!/usr/bin/env bash
# for rainbow borders animation. Rename to RainbowBorders.sh to turn it on
# (Startup_Apps.lua and RefreshNoWaybar.sh run it under that name), and set
# borderangle back to style "loop" in UserAnimations.lua to make it turn.
#
# Through `hyprctl eval 'hl.config(...)'`: the Lua config has no
# `hyprctl keyword`, so the old version did nothing at all. A gradient is a
# table of colours plus an angle.

random_hex() {
    printf '"0xff%s"' "$(openssl rand -hex 3)"
}

# Ten random colours, comma-separated for the Lua table.
random_colors() {
    local out="" _
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        out+="${out:+, }$(random_hex)"
    done
    printf '%s' "$out"
}

# rainbow colors only for active window
hyprctl eval "hl.config({ general = { col = { active_border = { colors = { $(random_colors) }, angle = 270 } } } })" >/dev/null

# rainbow colors for inactive window (uncomment to take effect)
#hyprctl eval "hl.config({ general = { col = { inactive_border = { colors = { $(random_colors) }, angle = 270 } } } })" >/dev/null
