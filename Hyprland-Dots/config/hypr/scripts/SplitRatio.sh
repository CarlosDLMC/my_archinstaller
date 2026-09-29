#!/usr/bin/env bash
# SUPER+M: split ratio 0.3 on either layout.
#
# The bind used to be hl.dsp.layout("splitratio 0.3"), commented "works on
# either layout" - but each layout has its own messages and splitratio is
# dwindle's: after SUPER+ALT+L switched to master, SUPER+M did nothing
# ("Unknown master layoutmsg"). Master has no ratio message in 0.56; its ratio
# is the master.mfact option, set at runtime the same way ChangeLayout.sh
# switches layouts (a config reload goes back to SystemSettings.lua's value).

LAYOUT=$(hyprctl -j getoption general.layout | jq -r '.str')

case "$LAYOUT" in
"master") hyprctl eval 'hl.config({ master = { mfact = 0.3 } })' >/dev/null ;;
*)        hyprctl dispatch 'hl.dsp.layout("splitratio 0.3")' >/dev/null ;;
esac
