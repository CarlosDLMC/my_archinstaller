#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# Clipboard Manager. This script uses cliphist, rofi, and wl-copy.

# Variables
rofi_theme="$HOME/.config/rofi/config-clipboard.rasi"
msg='👀 **note**  CTRL DEL = cliphist del (entry)   or   ALT DEL - cliphist wipe (all)'
# Actions:
# CTRL Del to delete an entry
# ALT Del to wipe clipboard contents

# Check if rofi is already running
if pidof rofi > /dev/null; then
  pkill rofi
fi

# After picking an entry, paste it straight into the window that had focus
# before rofi opened, so Enter both copies and pastes. Terminals take
# Ctrl+Shift+V, everything else Ctrl+V. wtype types through Hyprland's
# virtual-keyboard protocol; the short sleep lets focus return to the window
# after rofi closes, otherwise the keystroke lands nowhere.
paste_into_active_window() {
    command -v wtype >/dev/null 2>&1 || return 0
    sleep 0.15
    local class
    class=$(hyprctl -j activewindow 2>/dev/null | jq -r '.class // ""')
    case "$class" in
        foot|footclient|kitty|Alacritty|com.mitchellh.ghostty|org.wezfurlong.wezterm|xterm|st|st-256color|konsole|org.kde.konsole|Gnome-terminal|org.gnome.Terminal)
            wtype -M ctrl -M shift -k v -m shift -m ctrl ;;
        "")
            ;;  # nothing focused - leave it in the clipboard
        *)
            wtype -M ctrl -k v -m ctrl ;;
    esac
}

while true; do
    result=$(
        rofi -i -dmenu \
            -kb-custom-1 "Control-Delete" \
            -kb-custom-2 "Alt-Delete" \
            -config $rofi_theme < <(cliphist list) \
			-mesg "$msg" 
    )

    case "$?" in
        1)
            exit
            ;;
        0)
            case "$result" in
                "")
                    continue
                    ;;
                *)
                    cliphist decode <<<"$result" | wl-copy
                    paste_into_active_window
                    exit
                    ;;
            esac
            ;;
        10)
            cliphist delete <<<"$result"
            ;;
        11)
            cliphist wipe
            ;;
    esac
done

