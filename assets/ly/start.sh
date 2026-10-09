#!/bin/sh
# Set larger font for ly login screen with Cyrillic support
/usr/bin/setfont latarcyrheb-sun32
# Console palette slots the flags need, on ly's VT only (soviet-flag.py,
# COLOURS_256). Nothing else on the login screen uses them. start_cmd's
# stdout is ly's tty, so these land.
#   8 dark grey #555555 -> near-black #141414: black as a foreground (Germany,
#     Russian Empire). True black is the screen itself and would vanish.
#   3 brown #AA5500 -> gold #FFD700: a yellow that can be a background
#     (Russian Empire, whose gold sits between black and white).
#   5 magenta #AA00AA -> near-black #141414: black as a background (South
#     Korea's trigrams sit directly on white).
#   6 cyan #00AAAA -> light blue #2F80D0 (Estonia, Greece, Luxembourg, San
#     Marino), as foreground and background.
#   13 bright magenta #FF55FF -> orange #FF8C2A (Ireland, Cyprus), foreground.
printf '\033]P8141414'
printf '\033]P3ffd700'
printf '\033]P5141414'
printf '\033]P62f80d0'
printf '\033]Pdff8c2a'
