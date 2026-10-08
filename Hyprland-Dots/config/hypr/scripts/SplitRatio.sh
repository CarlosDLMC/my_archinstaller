#!/usr/bin/env bash
# SUPER+M: split ratio 0.3 on either layout.
#
# The bind used to be hl.dsp.layout("splitratio 0.3"), commented "works on
# either layout" - but each layout has its own messages and splitratio is
# dwindle's: after SUPER+ALT+L switched to master, SUPER+M did nothing
# ("Unknown master layoutmsg").
#
# Both with "exact". A bare number is a delta in 0.56 - dwindle's "splitratio
# 0.3" added 0.3 per press (1.0 -> 1.3 -> 1.6 -> 1.9, then nothing, and no way
# back with the same key) - and setting the master.mfact option only changed
# what a NEW master layout starts with, never the master already on screen.
# "mfact exact" sets the current master's width itself.

LAYOUT=$(hyprctl -j getoption general.layout | jq -r '.str')

case "$LAYOUT" in
"master") hyprctl dispatch 'hl.dsp.layout("mfact exact 0.3")' >/dev/null ;;
*)        hyprctl dispatch 'hl.dsp.layout("splitratio 0.3 exact")' >/dev/null ;;
esac
