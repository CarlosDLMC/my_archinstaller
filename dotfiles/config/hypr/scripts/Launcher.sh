#!/usr/bin/env bash
# The app launcher (SUPER+D). A script because the command is longer than a
# mango config value may be (255 bytes).
#
# ФАЙЛЫ tab = RofiFiles.sh (fd under ~ or /). glob matching makes "*part*" a
# pattern; without a * it matches anywhere in the name.
# config-launcher.rasi adds the match count and the full-name line.
# ROFI_KEYBOARD_ON_DEMAND: the patched rofi (pkgbuilds/rofi) lets a click on a
# window take the keyboard while the launcher stays open - the preview beside
# it (Shift+Enter in ФАЙЛЫ) can be used. Stock rofi ignores it.
# -on-selection-changed hands every row the cursor moves to to RofiFiles.sh
# --hover, which opens it while preview mode is on. rofi pastes {entry} into
# the command before splitting it, hence the quotes; the patched rofi escapes
# the " and \ in a name for them, so every row arrives whole.
S="$HOME/.config/hypr/scripts"

pkill rofi || true
ROFI_KEYBOARD_ON_DEMAND=1 exec rofi -config ~/.config/rofi/config-launcher.rasi -show drun \
    -modi "drun,files:$S/RofiFiles.sh,run,window" -matching glob \
    -on-selection-changed "$S/RofiFiles.sh --hover \"{entry}\""
