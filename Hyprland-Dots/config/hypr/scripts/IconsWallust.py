#!/usr/bin/env python3
"""Flat-Remix in the wallpaper's colours.

Flat-Remix makes its colour variants by swapping two hexes: the variant's
colour (#367bf0 in Blue) and a darker shade of it (#2b62c0), used for the back
of a folder, the highlight of an action icon and so on. This does the same
swap with the colour the bar's console cards are lit in - wallust's accent,
read from the bar's own palette file - and so the folders in Thunar and the
icons in the launcher follow the wallpaper like everything else.

The result is ~/.icons/Flat-Remix-Wallust-Dark. It holds only the ~12,000
icons that carry the blue; it inherits the other ~28,000 from
Flat-Remix-Blue-Dark instead of keeping a second 319 MB copy of them.

Run by WallustSwww.sh and WallpaperEffects.sh after every `wallust run` (in
the background), by initial-boot.sh on the first login and by copy.sh after it
seeds the palette. Takes about a second; does nothing when the colours have not
changed.
"""
import colorsys
import fcntl
import json
import os
import re
import subprocess
import sys

HOME = os.path.expanduser("~")
SRC_NAME = "Flat-Remix-Blue-Dark"
NAME = "Flat-Remix-Wallust-Dark"
SRC = os.path.join(HOME, ".icons", SRC_NAME)
DST = os.path.join(HOME, ".icons", NAME)
PALETTE = os.path.join(HOME, ".config", "quickshell", "bar", "wallust-colors.json")

MANIFEST = os.path.join(DST, ".wallust-manifest")   # the icons that carry the blue
STATE = os.path.join(DST, ".wallust-colours")       # the colours they carry now
LOCK = os.path.join(HOME, ".icons", "." + NAME + ".lock")

BLUES = re.compile(rb"#(367bf0|2b62c0)", re.IGNORECASE)


def hls_hex(h, l, s):
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    return "%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))


def colours():
    """The accent and its darker shade, as bare lowercase hex.

    Lightness is held between 0.50 and 0.68. wallust's slots can come out
    near-black, and a near-black folder disappears into a dark file manager;
    they can also come out near-white, and a near-white folder has no colour
    left to show. Hue and saturation are wallust's, untouched. The shade keeps
    Flat-Remix's own ratio between its two blues (lightness x0.8).
    """
    with open(PALETTE, encoding="utf-8") as f:
        accent = json.load(f)["accent"].lstrip("#")
    r, g, b = (int(accent[i:i + 2], 16) / 255 for i in (0, 2, 4))
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    l = min(max(l, 0.50), 0.68)
    return hls_hex(h, l, s), hls_hex(h, l * 0.8, s * 0.85)


def manifest():
    """Every icon in the source theme that carries one of the two blues."""
    if os.path.exists(MANIFEST) and \
            os.path.getmtime(MANIFEST) >= os.path.getmtime(os.path.join(SRC, "index.theme")):
        with open(MANIFEST, encoding="utf-8") as f:
            return [line for line in f.read().split("\n") if line]
    found = []
    for root, _dirs, files in os.walk(SRC):
        for name in files:
            if not name.endswith(".svg"):
                continue
            path = os.path.join(root, name)
            with open(path, "rb") as f:
                if BLUES.search(f.read()):
                    found.append(os.path.relpath(path, SRC))
    found.sort()
    os.makedirs(DST, exist_ok=True)
    with open(MANIFEST, "w", encoding="utf-8") as f:
        f.write("\n".join(found) + "\n")
    return found


def write_index():
    """The source's index.theme under the new name, inheriting from it."""
    with open(os.path.join(SRC, "index.theme"), encoding="utf-8") as f:
        lines = f.read().split("\n")
    out = []
    for line in lines:
        if line.startswith("Name="):
            line = "Name=" + NAME
        elif line.startswith("Comment="):
            line = "Comment=Flat-Remix in the wallpaper's colours (IconsWallust.py)"
        elif line.startswith("Inherits="):
            line = "Inherits=" + SRC_NAME + "," + line[len("Inherits="):]
        out.append(line)
    text = "\n".join(out)
    path = os.path.join(DST, "index.theme")
    try:
        with open(path, encoding="utf-8") as f:
            if f.read() == text:
                return False
    except FileNotFoundError:
        pass
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    return True


def adopt():
    """Select this theme where the blue one is still selected.

    initial-boot.sh selects it on a fresh install, but it runs once: a machine
    that only re-syncs the dots (copy.sh) keeps Flat-Remix-Blue-Dark in
    gsettings while settings.ini and qt5ct/qt6ct name this one. Any other
    choice is left alone.
    """
    key = ["org.gnome.desktop.interface", "icon-theme"]
    try:
        current = subprocess.run(["gsettings", "get"] + key, capture_output=True,
                                 text=True, timeout=5).stdout.strip().strip("'")
        if current == SRC_NAME and os.path.isfile(os.path.join(DST, "index.theme")):
            subprocess.run(["gsettings", "set"] + key + [NAME], timeout=5)
    except (OSError, subprocess.SubprocessError):
        pass


def refresh():
    """Make running GTK apps reload their icons.

    GTK only re-reads a theme when the theme setting changes, so step it to
    the source theme and back. Only when this theme is the one in use.
    """
    key = ["org.gnome.desktop.interface", "icon-theme"]
    try:
        current = subprocess.run(["gsettings", "get"] + key, capture_output=True,
                                 text=True, timeout=5).stdout.strip().strip("'")
        if current != NAME:
            return
        subprocess.run(["gsettings", "set"] + key + [SRC_NAME], timeout=5)
        subprocess.run(["gsettings", "set"] + key + [NAME], timeout=5)
    except (OSError, subprocess.SubprocessError):
        pass


def main():
    if not os.path.isfile(os.path.join(SRC, "index.theme")):
        return 0          # Flat-Remix is not installed: nothing to recolour
    try:
        main_hex, dark_hex = colours()
    except (OSError, ValueError, KeyError):
        return 0          # no palette yet (wallust has not run): keep what is there

    os.makedirs(os.path.dirname(LOCK), exist_ok=True)
    with open(LOCK, "w") as lock:
        # Wallpapers can change faster than this runs. Each run waits for the
        # one before it and then reads the palette as it is NOW, so the last
        # one to finish always leaves the latest colours.
        fcntl.flock(lock, fcntl.LOCK_EX)

        files = manifest()
        new_index = write_index()
        want = main_hex + " " + dark_hex
        try:
            with open(STATE, encoding="utf-8") as f:
                have = f.read().strip()
        except FileNotFoundError:
            have = ""
        missing = [rel for rel in files if not os.path.exists(os.path.join(DST, rel))]
        if have == want and not missing and not new_index:
            adopt()
            return 0

        table = {b"367bf0": main_hex.encode(), b"2b62c0": dark_hex.encode()}
        created = False
        for rel in files:
            with open(os.path.join(SRC, rel), "rb") as f:
                data = f.read()
            data = BLUES.sub(lambda m: b"#" + table[m.group(1).lower()], data)
            out = os.path.join(DST, rel)
            if not os.path.exists(out):
                os.makedirs(os.path.dirname(out), exist_ok=True)
                created = True
            # Rewritten in place: the directories' mtimes stay put, so the
            # icon cache built below stays valid across recolours.
            with open(out, "wb") as f:
                f.write(data)

        if created or new_index:
            subprocess.run(["gtk-update-icon-cache", "-q", "-f", "-t", DST],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        with open(STATE, "w", encoding="utf-8") as f:
            f.write(want + "\n")

    adopt()
    refresh()
    return 0


if __name__ == "__main__":
    sys.exit(main())
