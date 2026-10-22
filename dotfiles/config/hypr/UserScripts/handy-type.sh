#!/usr/bin/env bash
# Handy's paste step: types the transcript, 700 ms after transcription ends.
#
# handy-paste-settings.sh sets Handy's paste method to "External Script" with
# this file as the script. Handy runs it with the transcript as $1 and waits for
# it to finish.
#
# Why not Handy's "Direct" method: it types with wtype the moment transcription
# ends, and its paste delay setting only applies to the clipboard methods. wtype
# sends keys through its own keymap, and Hyprland matched binds by keycode
# against the US layout - so with SUPER/CTRL still held from the CTRL+SUPER+F8
# stop, letters fired binds ("a" -> SUPER+4, "t" -> SUPER+Q, "p" ->
# SUPER+CTRL+R). mango ignores binds from a virtual keyboard; the 700 ms wait
# stays anyway, so the keys of the bind are let go before the typing starts. Typing (not Ctrl+V)
# because a clipboard paste does not reach terminals.

[ -n "${1:-}" ] || exit 0
sleep 0.7
exec wtype -- "$1"
