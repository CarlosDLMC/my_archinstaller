#!/usr/bin/env bash
# Pin Handy's paste settings before Handy starts.
#
# Paste method "External Script", the script being handy-type.sh next to this
# file: it waits 700 ms, then types the transcript with wtype. Handy's own
# "Direct" method types at once - its paste delay only applies to the clipboard
# methods - and with SUPER/CTRL still held from the CTRL+SUPER+F8 stop, typed
# letters fire binds. See handy-type.sh.
#
# Only edits settings_store.json while Handy is NOT running (a running Handy
# writes its in-memory settings back over the file), and only once the file
# exists (Handy creates it on first start). Called by the keybind
# (UserKeybinds.lua) and by handy-start.sh.

settings="$HOME/.local/share/com.pais.handy/settings_store.json"
type_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/handy-type.sh"

[ -w "$settings" ] || exit 0
[ -x "$type_script" ] || exit 0
pgrep -x handy >/dev/null 2>&1 && exit 0

python3 - "$settings" "$type_script" <<'PY' 2>/dev/null
import json, os, sys
path, script = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        data = json.load(f)
    s = data["settings"]
except Exception:
    sys.exit(0)  # unparseable or unexpected layout: leave it to Handy
changed = False
if s.get("paste_method") != "external_script":
    s["paste_method"] = "external_script"
    changed = True
if s.get("external_script_path") != script:
    s["external_script_path"] = script
    changed = True
if changed:
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, path)
PY
exit 0
