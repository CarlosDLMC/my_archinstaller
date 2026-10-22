#!/usr/bin/env bash
# SUPER+CTRL+F8: toggle Handy dictation (with the paste settings applied
# first). A script because the command does not fit a mango bind line.
"$HOME/.config/hypr/UserScripts/handy-paste-settings.sh"
notify-send -t 1500 -i audio-input-microphone "Handy" "Переключение диктовки" &&
    exec handy --toggle-transcription
