#!/usr/bin/env bash
# Handy (offline speech-to-text) session autostart.
#
# Handy needs a model before it can transcribe anything, and the model is picked
# in its GUI. So on a machine that has never chosen one, start it visible; once
# selected_model is set, start it hidden and let the Hyprland keybind
# (SUPER + CTRL + F8, UserKeybinds.conf) drive it from the background.
#
# Note that Handy's own "Shortcut" field does not work under Hyprland: Wayland
# does not let an application register a global shortcut. The keybind is what
# actually fires the toggle.

settings="$HOME/.local/share/com.pais.handy/settings_store.json"

command -v handy >/dev/null 2>&1 || exit 0

selected_model=""
if [ -r "$settings" ]; then
    # settings_store.json nests everything under a "settings" key. Fall back to
    # an empty string on unparseable or partially written JSON, which starts
    # Handy visible - the recoverable direction.
    selected_model=$(python3 - "$settings" <<'PY' 2>/dev/null
import json, sys
try:
    with open(sys.argv[1]) as f:
        print(json.load(f).get("settings", {}).get("selected_model") or "")
except Exception:
    print("")
PY
)
fi

if [ -n "$selected_model" ]; then
    exec handy --start-hidden
else
    notify-send -t 8000 -i audio-input-microphone "Handy" \
        "Pick a model to enable speech-to-text (Parakeet V3 recommended)." 2>/dev/null
    exec handy
fi
