#!/usr/bin/env python3
"""Kvantum - the Qt apps' theme - in the wallpaper's colours.

The GTK side (Wallust-A/B) is GTK's own dark Adwaita with the wallpaper's
accent where Adwaita paints blue. KvGnomeDark is Kvantum's copy of that same
dark Adwaita, so this does the same to it: every blue it paints - selections,
pressed and toggled items, focus frames, progress bars, sliders, links - takes
the hue and saturation of the colour the bar's console cards are lit in
(wallust's accent, read from the bar's own palette file, as IconsWallust.py
does) and keeps its own lightness. Qt and GTK apps then share the greys and
the accent.

The result is ~/.config/Kvantum/Wallust, which kvantum.kvconfig selects.
Kvantum's own palette wins over the one qt5ct/qt6ct name, so those need no
change. Qt apps read their theme once, at start, so one already open keeps
the old colours until it is restarted.

Run by WallustSwww.sh and WallpaperEffects.sh after every `wallust run`. Does
nothing when the colours have not changed.
"""
import colorsys
import json
import os
import re
import sys

HOME = os.path.expanduser("~")
SRC_NAME = "KvGnomeDark"
NAME = "Wallust"
SRC = os.path.join("/usr/share/Kvantum", SRC_NAME)
DST = os.path.join(HOME, ".config", "Kvantum", NAME)
PALETTE = os.path.join(HOME, ".config", "rust-bar", "wallust-colors.json")

# Every saturated colour KvGnomeDark carries except one: Adwaita's blues, plus
# the red it gives visited links (GTK draws those in the accent too). The
# purple (#b74aff) is left alone - it only sits in the menu and tooltip
# shadow pieces, where it never shows.
BLUES = ("15539e", "1b6acb", "3584e4", "3a90eb", "3daee9", "2eb8e6", "ff6666")
# The selection blue. White text sits on it, so it must keep 4.5:1 to white
# whatever hue it ends up in - a yellow or green accent at Adwaita's own
# lightness would not.
SELECTION = "15539e"
PATTERN = re.compile(r"#(" + "|".join(BLUES) + r")\b", re.IGNORECASE)


def rgb(hexstr):
    return tuple(int(hexstr[i:i + 2], 16) / 255 for i in (0, 2, 4))


def hexof(r, g, b):
    return "%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))


def luminance(r, g, b):
    def channel(v):
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def table():
    """Each blue -> the accent's hue and saturation at that blue's lightness."""
    with open(PALETTE, encoding="utf-8") as f:
        accent = json.load(f)["accent"].lstrip("#")
    h, _l, s = colorsys.rgb_to_hls(*rgb(accent))
    out = {}
    for blue in BLUES:
        lightness = colorsys.rgb_to_hls(*rgb(blue))[1]
        colour = colorsys.hls_to_rgb(h, lightness, s)
        if blue == SELECTION:
            while lightness > 0.10 and 1.05 / (luminance(*colour) + 0.05) < 4.5:
                lightness -= 0.02
                colour = colorsys.hls_to_rgb(h, lightness, s)
        out[blue] = hexof(*colour)
    return out


def write(path, text):
    """Replace the file only when it changes, and never leave it half-written:
    a Qt app starting meanwhile reads either the old theme or the new one."""
    try:
        with open(path, encoding="utf-8") as f:
            if f.read() == text:
                return
    except FileNotFoundError:
        pass
    with open(path + ".tmp", "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(path + ".tmp", path)


def main():
    if not os.path.isfile(os.path.join(SRC, SRC_NAME + ".kvconfig")):
        return 0          # kvantum is not installed: nothing to recolour
    try:
        swap = table()
    except (OSError, ValueError, KeyError):
        return 0          # no palette yet (wallust has not run): keep what is there

    os.makedirs(DST, exist_ok=True)
    for ext in (".kvconfig", ".svg"):
        with open(os.path.join(SRC, SRC_NAME + ext), encoding="utf-8") as f:
            text = f.read()
        text = PATTERN.sub(lambda m: "#" + swap[m.group(1).lower()], text)
        write(os.path.join(DST, NAME + ext), text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
