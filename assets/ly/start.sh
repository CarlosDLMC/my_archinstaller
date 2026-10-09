#!/bin/sh
# Set larger font for ly login screen with Cyrillic support
/usr/bin/setfont latarcyrheb-sun32
# Palette slot 8 (dark grey, #555555) as near-black #141414, on ly's VT only.
# It stands in for black in the German flag (soviet-flag.py, COLOURS_256):
# true black is the screen itself and would vanish. Nothing else on the
# login screen uses slot 8. start_cmd's stdout is ly's tty, so this lands.
printf '\033]P8141414'
