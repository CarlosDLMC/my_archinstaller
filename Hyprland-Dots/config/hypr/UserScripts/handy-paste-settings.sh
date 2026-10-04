#!/usr/bin/env bash
# Pin Handy's paste settings before Handy starts.
#
# Handy types the transcript with wtype ("direct"): Ctrl+V paste does not work
# in terminals. wtype sends keys through its own keymap, and Hyprland matches
# binds by keycode against the US layout - so with SUPER/CTRL still held from
# the CTRL+SUPER+F8 stop, letters fire binds ("a" -> SUPER+4, "t" -> SUPER+Q,
# "p" -> SUPER+CTRL+R). Waiting 700 ms before typing gives time to let go.
#
# Only edits settings_store.json while Handy is NOT running (a running Handy
# writes its in-memory settings back over the file), and only once the file
# exists (Handy creates it on first start). Called by the keybind
# (UserKeybinds.lua) and by handy-start.sh.

settings="$HOME/.local/share/com.pais.handy/settings_store.json"
min_delay_ms=700

[ -w "$settings" ] || exit 0
pgrep -x handy >/dev/null 2>&1 && exit 0

python3 - "$settings" "$min_delay_ms" <<'PY' 2>/dev/null
import json, os, sys
path, min_delay = sys.argv[1], int(sys.argv[2])
try:
    with open(path) as f:
        data = json.load(f)
    s = data["settings"]
except Exception:
    sys.exit(0)  # unparseable or unexpected layout: leave it to Handy
changed = False
if s.get("paste_method") != "direct":
    s["paste_method"] = "direct"
    changed = True
if not isinstance(s.get("paste_delay_ms"), int) or s["paste_delay_ms"] < min_delay:
    s["paste_delay_ms"] = min_delay
    changed = True
if changed:
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, path)
PY
exit 0
