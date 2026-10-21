#!/usr/bin/env python3
"""Emit the configured xkb layouts as JSON for the layout switcher.

Display names come from the xkb rules database rather than a hardcoded map,
so any layout added to mango's xkb_rules_layout gets a correct short code and
name with no code change. Short codes match what GNOME shows (us -> "en").

Output: {"layouts": [{"code","short","name"}, ...], "current": <index>}
"""
import json
import os
import subprocess
import xml.etree.ElementTree as ET

XKB_RULES = "/usr/share/X11/xkb/rules/evdev.xml"
CONFIG = os.path.expanduser("~/.config/mango/config.conf")


def config_values(path, key, seen=None):
    """Every value of `key` in mango's config and the files it sources, in
    mango's reading order (the last one is the one in effect)."""
    seen = set() if seen is None else seen
    path = os.path.realpath(path)
    if path in seen:
        return []
    seen.add(path)
    out = []
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                if line.startswith("#") or "=" not in line:
                    continue
                k, _, v = line.partition("=")
                k = k.strip()
                v = v.split(" #", 1)[0].strip()
                if k in ("source", "source_optional"):
                    if v.startswith("./"):
                        v = os.path.join(os.path.dirname(CONFIG), v[2:])
                    out += config_values(os.path.expanduser(v), key, seen)
                elif k == key:
                    out.append(v)
    except OSError:
        pass
    return out


def configured_codes():
    values = config_values(CONFIG, "xkb_rules_layout")
    raw = values[-1] if values else "us"
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
    """The layout in effect, by its XKB name ("English (US)")."""
    try:
        out = subprocess.run(["mmsg", "get", "keyboardlayout"],
                             capture_output=True, text=True, timeout=3).stdout
        return json.loads(out).get("layout")
    except Exception:
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
