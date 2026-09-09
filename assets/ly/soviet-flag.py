#!/usr/bin/env python3
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  #
# Generate the 8-bit Soviet flag that ly draws behind its login screen.
# Writes two durdraw .dur files (gzipped JSON) from the same traced art:
# soviet-flag-animated.dur, where the cloth waves, and soviet-flag-static.dur,
# a single still frame of it. config.ini sets animation = dur_file and points
# dur_file_path at one of them; ly_config.sh installs both to /etc/ly, so
# switching is a one-line config edit. Run with no arguments to write both, or
# name a variant to write just that one.
#
# RESOLUTION
# A console cell is 16x32 px. latarcyrheb-sun32 - the font ly loads via
# /etc/ly/start.sh - offers exactly ONE way to subdivide a cell: the upper and
# lower half blocks. It has no left/right halves, no quadrants, no braille and
# no sextants; all were checked against the font's 546 mapped codepoints. So
# the finest SQUARE pixel obtainable is 16x16: one cell wide, half a row tall.
# That gives a 120x66 art grid on a 120x33 console - 7920 pixels, 4.6x what a
# whole-cell grid allows, and the practical maximum without changing the font.
#
# The cost: a cell has one foreground and one background, so each vertically
# adjacent PAIR of art pixels must be expressible as one such pair. With three
# colours - red field, yellow emblem, black outside the cloth - all nine
# combinations work out, which is what makes this viable at all.
#
# COLOUR
# ly's dur palette is its own, and foreground and background use DIFFERENT
# tables. Both were read off the real framebuffer using labelled test cards
# (indices 4..11 render black in both, which is why guessing never worked):
#
#   background: 0 #000000   12 #AA0000   14 #AA5500   15 #AAAAAA
#   foreground: 4 #000000   13 #FF5555   15 #FFFF55
#
# Red exists only as a BACKGROUND and yellow only as a FOREGROUND. That single
# fact dictates how every cell below is assembled.

import gzip
import json
import math
import os
import sys

# --- artwork ---------------------------------------------------------------
# The whole flag, traced from ~/Downloads/soviet_pixel_flag.svg at its own
# native resolution: pole, finial, cloth with its outline, and the emblem
# exactly where the artist put it. 72x66 tags - R field, Y emblem/pole,
# K the black outline, '.' empty.
#
# The outline is black and so is ly's background, so it does not read as an
# outline on screen; it simply insets the cloth by a pixel. It is kept
# because it is what the source draws, and it would show if the background
# were ever not black.
FLAG_ART = [
    ".KKKKK..................................................................",
    ".KYYYYKK................................................................",
    "KYYYYYYK................................................................",
    "KYYYYYYYK...............................................................",
    "KYYYYYYYK...............................................................",
    "KYYYYYYYK...............................................................",
    ".KYYYYYK...........................KKKKKKKKKKKKKKKKKKKK.................",
    "..KKKKK.......................KKKKKRRRRRRRRRRRRRRRRRRRRKKKKK............",
    "..KYKK.....................KKKRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRKKKKK.......",
    "..KYKK...................KKRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRKKKK...",
    "..KYKRK................KKRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRK..",
    "..KYKRRKK...........KKKRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRKK",
    "..KYKRRRKKK......KKKRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRKKKKKKKRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRRRRRRRYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRRRRRRRYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRRRRRRYRYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRRRRRRYRYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRYYYYYRRRYYYYYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRRYRRRRRRRRRYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRRRYYRRRRRYYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRRRRRYRRRYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRRRRYRRRRRYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRRRRYRRYRRYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRRRRYYYRYYYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRRRYYRRRRRYYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRRRYRRRRRRRYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRRRRRRRRYYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRRRRRRRRRRYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRRRRRRRRRRRYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRRRRRRRRRRRYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRRRRYYYYYRRRYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRRRYYYYYRRRRYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRRYYYYYRRRRRYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRYYYYYYYRRRRYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRRYYYYYYYRRRYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRRRYRRYYYYRYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRRRRRRRYYYYYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRRRRRRRRYYYYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRYYYYYYYYYYYYYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRYYYRYYYYYRRYYYYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRYYYRRRRRRRRRRYYYYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRYYYRRRRRRRRRRRRYYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRYRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRKKKKKKKKKKKKKKKKKKKKRRRRRRRRRRRRRRRRR",
    "..KYKRRRRRRRRRRRRRRRRRRRRRRRRRKKKKK....................KKKKKRRRRRRRRRRRR",
    "..KYKKRRRRRRRRRRRRRRRRRRRRRKKK..............................KKKKKRRRRRRR",
    "..KYKKRRRRRRRRRRRRRRRRRRRKK......................................KKKKRRR",
    "..KYK.KRRRRRRRRRRRRRRRRKK............................................KRR",
    "..KYK..KKRRRRRRRRRRRKKK...............................................KK",
    "..KYK...KKKRRRRRRKKK....................................................",
    "..KYK.....KKKKKKK.......................................................",
    "..KYK...................................................................",
    "..KYK...................................................................",
    "..KYK...................................................................",
    "..KYK...................................................................",
    "..KYK...................................................................",
    "..KYK...................................................................",
    "..KYK...................................................................",
    "..KYK...................................................................",
    "..KYK...................................................................",
    "..KYK...................................................................",
    "..KYK...................................................................",
]

# The pole and finial must not wave. Holding a COLUMN RANGE static was wrong:
# the finial ball spans columns 0..8, so clamping only 0..4 sliced it and its
# right half bobbed - which read as the pole moving. Held as a region instead:
# every pole/finial pixel is yellow or black with x <= 8, and the emblem's
# leftmost yellow is at x = 14, so this separates them cleanly.
STATIC_MAX_X = 8

# ly's dur palette is its own thing, and fg and bg are indexed differently.
# Measured off /dev/fb0 with a probe frame (fg i as an upper half-block over
# bg 12): the fg table is shifted one step, so fg 0 and 1 are both #AAAAAA and
# there is NO black foreground at all. That rules out drawing the cloth's edge
# as black-on-red; fg 5 happens to be exactly the field red, so the edge cells
# are drawn red-on-black instead. Using a black fg here paints them cyan.
RED_BG = 12            # #AA0000, the field
RED_FG = 5             # #AA0000, same red as a foreground
GOLD_FG = 15           # #FFFF55, the emblem
VOID_BG = 0            # #000000, outside the cloth - matches ly's bg

BLOCK = "\u2588"       # full block
UPPER = "\u2580"       # upper half
LOWER = "\u2584"       # lower half

# 8 frames make one full wave, so this is also the cycle time.
FRAMERATE = 4.0


def shrink(rows, nw, thr=0.38):
    """Area-coverage downsample of a '#'/'.' bitmap to nw wide, keeping aspect."""
    h, w = len(rows), len(rows[0])
    if nw is None or nw >= w:
        return rows
    nh = max(1, round(h * nw / w))
    out = []
    for y in range(nh):
        line = ""
        for x in range(nw):
            x0, x1 = x * w / nw, (x + 1) * w / nw
            y0, y1 = y * h / nh, (y + 1) * h / nh
            tot = cov = 0.0
            for sy in range(int(y0), min(h, int(y1) + 1)):
                for sx in range(int(x0), min(w, int(x1) + 1)):
                    ov = ((min(x1, sx + 1) - max(x0, sx))
                          * (min(y1, sy + 1) - max(y0, sy)))
                    if ov <= 0:
                        continue
                    tot += ov
                    if rows[sy][sx] == "#":
                        cov += ov
            line += "#" if tot > 0 and cov / tot >= thr else "."
        out.append(line)
    return out


def emblem_mask():
    """Star, a gap, then the hammer and sickle. Separate blocks because drawn
    together the blade's top edge ran into the star."""
    hs = shrink(HAMMER_SICKLE, HS_WIDTH)
    star = shrink(STAR, STAR_WIDTH)
    gap = 2
    w = max(len(hs[0]), len(star[0]))
    h = len(star) + gap + len(hs)
    m = [[False] * w for _ in range(h)]
    sx0 = (w - len(star[0])) // 2
    for j, row in enumerate(star):
        for i, ch in enumerate(row):
            if ch == "#":
                m[j][sx0 + i] = True
    top = len(star) + gap
    for j, row in enumerate(hs):
        for i, ch in enumerate(row):
            if ch == "#":
                m[top + j][i] = True
    return m, w, h


def build(px_w=120, px_h=66, frames=8, amp=2.0):
    """Frames of a 120x66 grid of colour tags.

    The art is the traced flag at 1:1 - no scaling, so nothing is softened.
    It is 72 wide, centred in the 120-wide grid. Only the cloth columns are
    displaced; the pole and finial stay put, which is what makes it read as a
    flag on a pole rather than the whole picture sliding up and down.
    """
    art_w, art_h = len(FLAG_ART[0]), len(FLAG_ART)
    x_off = (px_w - art_w) // 2
    out = []
    for f in range(frames):
        phase = 2 * math.pi * f / frames
        grid = [[None] * px_w for _ in range(px_h)]
        for ax in range(art_w):
            t = 2 * math.pi * max(0, ax - STATIC_MAX_X) / (art_w - STATIC_MAX_X)
            wave = int(round(amp * math.sin(1.5 * t - phase)))
            for ay in range(art_h):
                tag = FLAG_ART[ay][ax]
                if tag == "." or tag == "K":
                    continue                      # black: leave as background
                # pole and finial stay put; the cloth waves
                static = tag == "Y" and ax <= STATIC_MAX_X
                ty = ay + (0 if static else wave)
                if 0 <= ty < px_h:
                    grid[ty][x_off + ax] = tag
        out.append(grid)
    return out, px_w, px_h


# Every pair of stacked art pixels, and the single cell that renders it.
# Cells that are part cloth and part void invert: they use the red foreground
# over the void background, because the palette has no black foreground.
PAIRS = {
    ("R", "R"): (" ", GOLD_FG, RED_BG),
    ("Y", "Y"): (BLOCK, GOLD_FG, RED_BG),
    (None, None): (" ", GOLD_FG, VOID_BG),
    ("Y", "R"): (UPPER, GOLD_FG, RED_BG),
    ("R", "Y"): (LOWER, GOLD_FG, RED_BG),
    (None, "R"): (LOWER, RED_FG, VOID_BG),
    ("R", None): (UPPER, RED_FG, VOID_BG),
    (None, "Y"): (LOWER, GOLD_FG, VOID_BG),
    ("Y", None): (UPPER, GOLD_FG, VOID_BG),
}


def to_dur(grids, px_w, rows, framerate=None):
    """Pack each vertical pair of art rows into one console cell."""
    assert rows % 2 == 0, "art rows must be even to pair into cells"
    cell_rows = rows // 2
    frames = []
    for n, g in enumerate(grids, 1):
        contents, cmap = [], []
        cells = []
        for cy in range(cell_rows):
            row = [PAIRS[(g[2 * cy][cx], g[2 * cy + 1][cx])] for cx in range(px_w)]
            cells.append(row)
        contents = ["".join(c[0] for c in row) for row in cells]
        cmap = [[[cells[cy][cx][1], cells[cy][cx][2]] for cy in range(cell_rows)]
                for cx in range(px_w)]
        frames.append({"frameNumber": n, "delay": 0,
                       "contents": contents, "colorMap": cmap})
    return {"DurMovie": {
        "formatVersion": 7, "colorFormat": "16", "preferredFont": "fixed",
        "encoding": "utf-8", "name": "soviet-flag", "artist": "",
        "framerate": FRAMERATE if framerate is None else framerate,
        "sizeX": px_w, "sizeY": cell_rows,
        "extra": None, "frames": frames}}


# Two files, so config.ini can point at either one without regenerating
# anything: the waving flag, and a single still frame of it. The still frame is
# just build() with the wave switched off, which keeps both in lockstep with
# FLAG_ART instead of letting a hand-placed copy drift out of sync.
VARIANTS = {
    "soviet-flag-animated.dur": {"frames": 8, "amp": 2.0, "framerate": FRAMERATE},
    "soviet-flag-static.dur": {"frames": 1, "amp": 0.0, "framerate": 1.0},
}


def write_dur(out, frames, amp, framerate):
    grids, w, rows = build(frames=frames, amp=amp)
    dur = to_dur(grids, w, rows, framerate=framerate)
    # Reproducible output: identical art must give a byte-identical file, or
    # every regeneration shows up as a phantom git diff. mtime=0 kills the
    # timestamp, and filename="" is required too - GzipFile infers the gzip
    # FNAME field from fileobj.name, so without it the output path itself ends
    # up inside the file.
    with open(out, "wb") as raw:
        with gzip.GzipFile(fileobj=raw, mode="wb", compresslevel=9, mtime=0,
                           filename="") as fh:
            fh.write(json.dumps(dur).encode())
    d = dur["DurMovie"]
    print(f"wrote {os.path.basename(out)}: {d['sizeX']}x{d['sizeY']} cells "
          f"({w}x{rows} art pixels), {len(d['frames'])} frames")


if __name__ == "__main__":
    # Written next to this script, not into the cwd, so the paths ly_config.sh
    # installs from are the same whatever directory this is run from.
    here = os.path.dirname(os.path.abspath(__file__))
    wanted = sys.argv[1:] or list(VARIANTS)
    for name in wanted:
        if name not in VARIANTS:
            sys.exit(f"unknown variant {name!r}; choose from {', '.join(VARIANTS)}")
        write_dur(os.path.join(here, name), **VARIANTS[name])


# --- preview ---------------------------------------------------------------
def write_ppm(grid, px_w, rows, path, px=16):
    """Preview at one screen pixel per art pixel, using the RGBs measured off
    ly's framebuffer."""
    RGB = {"R": (0xAA, 0x00, 0x00), "Y": (0xFF, 0xFF, 0x55), None: (20, 20, 20)}
    W, H = px_w * px, rows * px
    out = []
    for y in range(rows):
        line = bytearray()
        for x in range(px_w):
            line += bytes(RGB[grid[y][x]]) * px
        out.append(bytes(line) * px)
    open(path, "wb").write(f"P6\n{W} {H}\n255\n".encode() + b"".join(out))
