#!/usr/bin/env python3
"""Emit the configured xkb layouts as JSON for the layout switcher.

Display names come from the xkb rules database rather than a hardcoded map,
so any layout added to input:kb_layout gets a correct short code and name
with no code change. Short codes match what GNOME shows (us -> "en").

Output: {"layouts": [{"code","short","name"}, ...], "current": <index>}
"""
import json
import subprocess
import xml.etree.ElementTree as ET

XKB_RULES = "/usr/share/X11/xkb/rules/evdev.xml"


def hyprctl(*args):
    return subprocess.run(["hyprctl", *args], capture_output=True, text=True).stdout


def configured_codes():
    raw = json.loads(hyprctl("getoption", "-j", "input:kb_layout"))["str"]
    return [c.strip() for c in raw.split(",") if c.strip()]


def xkb_names():
    """code -> (shortDescription, description)"""
    out = {}
    try:
        root = ET.parse(XKB_RULES).getroot()
    except Exception:
        return out
    for layout in root.iter("layout"):
        ci = layout.find("configItem")
        if ci is None:
            continue
        code = ci.findtext("name")
        if not code:
            continue
        out[code] = (
            ci.findtext("shortDescription") or code,
            ci.findtext("description") or code,
        )
    return out


def active_display_name():
    try:
        devices = json.loads(hyprctl("devices", "-j"))
    except Exception:
        return None
    for kb in devices.get("keyboards", []):
        if kb.get("main"):
            return kb.get("active_keymap")
    return None


names = xkb_names()
codes = configured_codes()
layouts = [
    {"code": c, "short": names.get(c, (c, c))[0], "name": names.get(c, (c, c))[1]}
    for c in codes
]

active = active_display_name()
current = next((i for i, l in enumerate(layouts) if l["name"] == active), 0)

print(json.dumps({"layouts": layouts, "current": current}))
