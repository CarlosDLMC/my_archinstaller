#!/usr/bin/env python3
"""Silhouette image -> text art for the terminal, e.g. the screensaver's
(~/.local/share/screensaver/art.txt, drawn by Screensaver.sh).

  ImgToText.py IMAGE OUT --rows N [--mode block|braille] [--cell-aspect 2.4]
                                  [--threshold 50] [--invert]

ImageMagick trims, scales and thresholds the image to a 1-bit bitmap, the way
omarchy's transcode-ascii does; then each character takes a few of its pixels:

  block    1 x 2 pixels per character: half blocks, solid
  braille  2 x 4 pixels per character: braille dots, finer but lighter

Dark pixels are the shape unless --invert. --cell-aspect is a terminal cell's
height / width (both modes assume 2); foot's JetBrains Mono 10 on 2560x1440 is
10 x 24 px, so 2.4. For the screensaver:

  ImgToText.py logo.png ~/.local/share/screensaver/art.txt --rows 50 --mode block --cell-aspect 2.4
"""
import argparse
import subprocess

p = argparse.ArgumentParser()
p.add_argument("image")
p.add_argument("out")
p.add_argument("--rows", type=int, required=True)
p.add_argument("--mode", choices=["block", "braille"], default="block")
p.add_argument("--threshold", type=int, default=50)
p.add_argument("--invert", action="store_true")
p.add_argument("--cell-aspect", type=float, default=2.0)
a = p.parse_args()

px_per_row = 2 if a.mode == "block" else 4
cmd = ["magick", a.image, "-auto-orient", "-alpha", "remove", "-alpha", "off", "-colorspace", "Gray"]
if not a.invert:
    cmd += ["-negate"]                     # shape -> white
# Threshold before trimming: an off-white background (say #E8E8E8) is not
# "empty" to -trim until it is pure black.
cmd += ["-threshold", "%d%%" % a.threshold,
        "-bordercolor", "black", "-border", "1", "-trim", "+repage",
        # height decides the size; width follows the aspect ratio
        "-resize", "x%d" % (a.rows * px_per_row),
        # widen by cell aspect / 2, so the shape keeps its proportions on screen
        "-resize", "%.4f%%x100%%" % (a.cell_aspect / 2 * 100),
        # scaling blurs the edges grey again
        "-threshold", "%d%%" % a.threshold,
        "-compress", "none", "pbm:-"]
pbm = subprocess.run(cmd, check=True, capture_output=True, text=True).stdout

tokens = [t for line in pbm.splitlines() for t in line.split("#")[0].split()]
assert tokens[0] == "P1", tokens[0]
w, h = int(tokens[1]), int(tokens[2])
bits = "".join(tokens[3:])
# PBM: 1 = black. The shape was made white, so the shape is 0.
on = lambda x, y: 0 <= x < w and 0 <= y < h and bits[y * w + x] == "0"

rows = []
if a.mode == "block":
    for y in range(0, h, 2):
        row = ""
        for x in range(w):
            t, b = on(x, y), on(x, y + 1)
            row += "█" if t and b else "▀" if t else "▄" if b else " "
        rows.append(row.rstrip())
else:
    dots = [(0, 0, 0x01), (0, 1, 0x02), (0, 2, 0x04), (1, 0, 0x08),
            (1, 1, 0x10), (1, 2, 0x20), (0, 3, 0x40), (1, 3, 0x80)]
    for y in range(0, h, 4):
        row = ""
        for x in range(0, w, 2):
            m = sum(bit for dx, dy, bit in dots if on(x + dx, y + dy))
            row += chr(0x2800 + m) if m else " "
        rows.append(row.rstrip())

while rows and not rows[-1]:
    rows.pop()
with open(a.out, "w") as f:
    f.write("\n".join(rows) + "\n")
print("%s: %d cols x %d rows, %d filled cells" % (
    a.out, max(len(r) for r in rows), len(rows), sum(c != " " for r in rows for c in r)))
