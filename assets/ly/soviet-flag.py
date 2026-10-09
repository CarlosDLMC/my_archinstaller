#!/usr/bin/env python3
# Generate the 8-bit flags that ly draws behind its login screen.
# Writes durdraw .dur files (gzipped JSON) from one traced art table: a waving
# version and a single still frame of it, cut for each panel the repo supports
# (<flag>-flag-{animated,static}-{768p,900p,1080p,1440p,2160p}.dur). The
# Soviet flag is the traced art itself; the others in FLAGS repaint its cloth
# and keep its pole, outline and wave. Run with no arguments to write all of
# them, or name panels and/or flags to write just those.
#
# There is a cut per panel because ly draws a .dur at its native cell size and
# never scales it: a canvas smaller than the console grid leaves a black
# margin, which is what a 120x33 flag did on a 1440p screen. ly_config.sh
# measures the panel and installs the matching pair under the fixed names
# config.ini points at, so config.ini never changes.
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

# The flag sits left of centre so ly's login box - a fixed ~45 cells wide,
# centred - lands on the bare half of the cloth instead of over the emblem
# (art pixels 10..27). It used to be done with dur_x_offset = -16 in
# config.ini, which was fine while the movie was smaller than the screen, but
# a canvas that IS the screen cannot be shifted: ly would slide it off one
# edge and leave 16 blank columns at the other. So the shift moves in here,
# into where the art is placed on the canvas, and config.ini now offsets by 0.
# 16 cells is right for every panel because the box does not scale with the
# screen - it is the same 45 cells at 1080p and at 4K.
X_SHIFT = 16

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

# --- the other flags -------------------------------------------------------
# Same cloth, same pole, same wave - only the colours change. Each flag is a
# pattern over the cloth: u runs 0..1 from the hoist to the fly, v 0..1 from
# the cloth's top edge to its bottom edge IN THAT COLUMN, so stripes and
# crosses follow the traced curve of the cloth instead of cutting across it.
#
# The palette is the Linux console's: ly sends truecolour, and the kernel
# rounds a foreground to the 16 VGA colours and a background to the 8 dim
# ones (read back from /dev/vcsa on a spare VT). So white and yellow exist
# only as foregrounds, while red, blue and green have a dim foreground that is
# exactly their background. Every flag below only ever stacks two colours in
# a cell where at least one can be the background, which is what makes them
# drawable at all. The indices are dur's, run through ly's own tables.
# Background indices avoid the bold entries the Soviet flag's red (12) uses.
#
#   tag  colour   fg  bg
#   R    #AA0000   5   4
#   B    #0000AA   2   1
#   G    #00AA00   3   2
#   W    #FFFFFF  16   -
#   A    #FFFF55  15   -    yellow cloth; 'Y' stays the pole, which never waves
COLOURS = {
    "R": (5, 4),
    "B": (2, 1),
    "G": (3, 2),
    "W": (16, None),
    "A": (15, None),
    "Y": (15, None),
}

# The 16-colour table above has no grey at all, and black is the screen
# itself, so a black stripe drawn black simply is not there. dur's 256-colour
# format reaches one more console colour: a grey at or under 0x55 per channel
# is shown as the console's dark grey (#555555), as a foreground only. Flags
# that need it are written in that format (ly accepts it with full_color =
# true, which config.ini sets). Its indices 0-15 go straight to ly's colour
# table, with no remapping and no +1 on the background.
#
#   tag  colour   fg   bg
#   R    #AA0000    1    1
#   D    #555555  239    -    stands in for black
#   A    #FFFF55   11    -
#   O    #AA5500    3    3    gold: dim yellow, the one yellow with a background
#   N    #AA00AA    5    5    black with a background (South Korea's trigrams)
#
# start.sh redefines three console palette slots on ly's VT, which is what
# these become on screen: slot 8 (D) and slot 5 (N) to near-black #141414,
# slot 3 (O) to gold #FFD700. Nothing else on the login screen uses them. O exists for
# the Russian Empire's black-gold-white, where every pair of neighbours
# would otherwise be two foreground-only colours that no cell can hold.
COLOURS_256 = {
    "R": (1, 1),
    "B": (4, 4),
    "G": (2, 2),
    "W": (15, None),
    "A": (11, None),
    "Y": (11, None),
    "D": (239, None),
    "O": (3, 3),
    "N": (5, 5),
}
FORMAT_256 = {"germany", "russianempire", "southkorea"}

# Flags with small emblems (stars, trigrams) are sampled 4x4 per pixel and
# take the majority, so a 4-pixel star is a star and not whichever colour
# one point in the middle of each pixel happened to land on.
FINE = {"china", "vietnam", "northkorea", "southkorea"}

# The cloth is 67x40 art pixels; emblems are laid out in units of its height
# with x stretched by this, so circles and stars come out round, not wide.
ASPECT = 67 / 40


def bands(t, edges, tags):
    """The tag of the band t falls in; edges are the band widths' running
    totals, as fractions."""
    for edge, tag in zip(edges, tags):
        if t < edge:
            return tag
    return tags[-1]


def nordic(field, cross, h, v, border=None, bh=None, bv=None):
    """A Nordic cross. h and v are (before, width) of the vertical and
    horizontal arms as fractions of the flag; border likewise, for Norway's
    white fimbriation around its blue cross."""
    def paint(u, w):
        if h[0] <= u < h[0] + h[1] or v[0] <= w < v[0] + v[1]:
            return cross
        if border and (bh[0] <= u < bh[0] + bh[1] or bv[0] <= w < bv[0] + bv[1]):
            return border
        return field
    return paint


def belarus(u, v):
    """Red over green, 2+1, with the white hoist band (1/9 of the length)
    carrying the red ornament. The real ornament is far finer than this
    cloth, so it is drawn as a column of red diamonds, each as tall as the
    band is wide (67x40 cloth: 1/9 of 67 px is 7.4 px, 0.19 of 40)."""
    band = 1 / 9
    if u >= band:
        return bands(v, (2 / 3,), "RG")
    period = band * 67 / 40
    x = abs(u / band * 2 - 1)                     # 0 at the band's centre
    y = abs((v / period) % 1 * 2 - 1)             # 0 at a diamond's centre
    return "R" if x + y < 0.75 else "W"


def in_star(x, y, cx, cy, r, toward=None):
    """Is (x, y) inside a five-pointed star of outer radius r at (cx, cy)?
    One point faces up, or towards `toward` (a point) when given. All in
    height units, x already stretched by ASPECT."""
    dx, dy = x - cx, y - cy
    if dx * dx + dy * dy > r * r:
        return False
    up = -math.pi / 2
    if toward:
        up = math.atan2(toward[1] - cy, toward[0] - cx)
    # Fold into one point's wedge: b is 0 on a valley's ray, pi/5 on a tip's.
    a = (math.atan2(dy, dx) - up) % (2 * math.pi / 5)
    b = abs(a - math.pi / 5)
    rho = math.hypot(dx, dy)
    px, py = rho * math.cos(b), rho * math.sin(b)
    # Inside if on the centre's side of the edge from the valley (inner
    # radius 0.382 r, the regular star's) to the tip.
    vx, vy = r * 0.382, 0.0
    tx, ty = r * math.cos(math.pi / 5), r * math.sin(math.pi / 5)
    return (tx - vx) * (py - vy) - (ty - vy) * (px - vx) >= 0 or rho <= vx


def china(u, v):
    """Red, the big star and four small ones in the canton, on the official
    30x20 grid (units of 1/20 of the height); each small star points at the
    big one."""
    x, y = u * ASPECT * 20, v * 20
    big = (5, 5)
    if in_star(x, y, *big, 3):
        return "A"
    for c in ((10, 2), (12, 4), (12, 7), (10, 9)):
        if in_star(x, y, *c, 1, toward=big):
            return "A"
    return "R"


def vietnam(u, v):
    """Red, one yellow star in the middle reaching 3/10 of the height."""
    x, y = u * ASPECT, v
    return "A" if in_star(x, y, ASPECT / 2, 0.5, 0.3) else "R"


def northkorea(u, v):
    """Blue, white, red, white, blue at 6+1+15+1+6, and a white disc with a
    red star on the red, towards the hoist."""
    x, y = u * ASPECT, v
    cx, cy, r = 0.55, 0.5, 0.2
    if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
        return "R" if in_star(x, y, cx, cy, r * 0.95) else "W"
    return bands(v, (6 / 29, 7 / 29, 22 / 29, 23 / 29), "BWRWB")


# South Korea's trigrams, from the hoist-top corner round: bars listed from
# the one nearest the centre outwards, True for a solid bar, False for broken.
TRIGRAMS = (
    ((-1, -1), (True, True, True)),         # geon, top left
    ((1, -1), (False, True, False)),        # gam, top right
    ((1, 1), (False, False, False)),        # gon, bottom right
    ((-1, 1), (True, False, True)),         # ri, bottom left
)


def southkorea(u, v):
    """White; the red-over-blue taegeuk, half the height across, its axis on
    the cloth's diagonal; a trigram in each corner on the same diagonals.

    The official bars are 1/24 of the height with gaps half that - under a
    pixel at this size - so they are drawn at 1/16 with 1/32 gaps, enough
    to stay three bars and not one black block."""
    x, y = (u - 0.5) * ASPECT, v - 0.5           # centre origin, height units
    R = 0.25
    dlen = math.hypot(ASPECT, 1)
    if x * x + y * y <= R * R:
        # axis along the top-left to bottom-right diagonal
        ax, ay = ASPECT / dlen, 1 / dlen
        s = x * ax + y * ay                      # along the axis
        t = x * ay - y * ax                      # positive = up and right
        if (s + R / 2) ** 2 + t * t <= (R / 2) ** 2:
            return "R"                           # red head, hoist side
        if (s - R / 2) ** 2 + t * t <= (R / 2) ** 2:
            return "B"                           # blue head, fly side
        return "R" if t > 0 else "B"
    bar, gap = 1 / 16, 1 / 32
    length = R                                   # bar length: half the disc
    for (sx, sy), bars in TRIGRAMS:
        # unit vector from the centre towards this corner
        cx, cy = sx * ASPECT / dlen, sy * 1 / dlen
        s = x * cx + y * cy                      # distance out along it
        t = x * cy - y * cx                      # across it, along the bars
        start = R + R / 2                        # a quarter-disc of white first
        for i, solid in enumerate(bars):
            lo = start + i * (bar + gap)
            if lo <= s < lo + bar and abs(t) <= length / 2:
                if solid or abs(t) >= gap:
                    return "N"
    return "W"


# Proportions are each flag's official ones, stretched onto the one cloth.
FLAGS = {
    "soviet": None,                                    # the traced art as is
    # 5+2+9 by 4+2+4
    "sweden": nordic("B", "A", (5 / 16, 2 / 16), (4 / 10, 2 / 10)),
    # 6+1+2+1+12 by 6+1+2+1+6
    "norway": nordic("R", "B", (7 / 22, 2 / 22), (7 / 16, 2 / 16),
                     "W", (6 / 22, 4 / 22), (6 / 16, 4 / 16)),
    # 12+4+21 long, but the arms are the same width in PIXELS: the cloth is
    # 67x40, not 37x28, so 4/28 of its height drew the horizontal arm a
    # quarter thinner than the vertical one. Both are 4/37 of 67 = 7.2 px.
    "denmark": nordic("R", "W", (12 / 37, 4 / 37),
                      (0.5 - 4 / 37 * 67 / 40 / 2, 4 / 37 * 67 / 40)),
    # Placed at 5+3+10 by 4+3+4, but the official arms (3/11 of the height)
    # looked too heavy at this size; 2 units each instead, ~7 px like Denmark.
    "finland": nordic("W", "B", (5.5 / 18, 2 / 18), (4.5 / 11, 2 / 11)),
    "russia": lambda u, v: bands(v, (1 / 3, 2 / 3), "WBR"),
    # the civil flag: 1+2+1, no coat of arms
    "spain": lambda u, v: bands(v, (1 / 4, 3 / 4), "RAR"),
    "italy": lambda u, v: bands(u, (1 / 3, 2 / 3), "GWR"),
    "poland": lambda u, v: bands(v, (1 / 2,), "WR"),
    "ukraine": lambda u, v: bands(v, (1 / 2,), "BA"),
    "belarus": lambda u, v: belarus(u, v),
    # black, red, gold - black drawn dark grey, see COLOURS_256
    "germany": lambda u, v: bands(v, (1 / 3, 2 / 3), "DRA"),
    # the 1858 black-gold-white; black and gold through start.sh's palette
    "russianempire": lambda u, v: bands(v, (1 / 3, 2 / 3), "DOW"),
    "china": lambda u, v: china(u, v),
    "vietnam": lambda u, v: vietnam(u, v),
    "northkorea": lambda u, v: northkorea(u, v),
    "southkorea": lambda u, v: southkorea(u, v),
}


def paint_cloth(art, pattern, static_max_x, fine=False):
    """Repaint every cloth pixel of art with pattern(u, v).

    Cloth is the red field plus the emblem - anything R, or Y right of the
    pole. The black outline and the pole/finial are left exactly as traced."""
    def cloth(x, tag):
        return tag == "R" or (tag == "Y" and x > static_max_x)
    h, w = len(art), len(art[0])
    cols = [x for x in range(w) if any(cloth(x, art[y][x]) for y in range(h))]
    x0, x1 = cols[0], cols[-1]
    out = [list(row) for row in art]
    for x in cols:
        ys = [y for y in range(h) if cloth(x, art[y][x])]
        y0, y1 = ys[0], ys[-1]
        du, dv = 1 / (x1 - x0 + 1), 1 / (y1 - y0 + 1)
        u = (x - x0 + 0.5) * du
        for y in ys:
            v = (y - y0 + 0.5) * dv
            if not fine:
                out[y][x] = pattern(u, v)
                continue
            votes = {}
            for i in range(4):
                for j in range(4):
                    tag = pattern(u + (i - 1.5) / 4 * du, v + (j - 1.5) / 4 * dv)
                    votes[tag] = votes.get(tag, 0) + 1
            out[y][x] = max(votes, key=votes.get)
    return ["".join(row) for row in out]


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


def scale_art(art, scale):
    """Area-resample the tag grid (R/Y/K/.) by `scale`.

    shrink() above is for the '#'/'.' emblem masks. This one carries four
    tags rather than two, so each target pixel takes the tag that covers most
    of its footprint. On an integer scale that is exact pixel doubling; on a
    fractional one it is nearest-neighbour with the ties settled by area,
    which is the most a hard-edged 3-colour bitmap can be stretched without
    inventing colours the palette cannot render.

    Going DOWN (the sub-1080p cuts) plain majority is not enough: the emblem
    and the pole are one-pixel yellow lines, and a line that straddles two
    target pixels covers under half of each, so majority hands both to the
    red or black around it. That broke the star into fragments at 768p and
    erased the pole outright at 900p. Yellow is therefore kept once it covers
    scale/2 of the footprint: a straight 1px line splits between at most two
    target pixels and the larger share is always at least scale/2, so no line
    can vanish, and it only doubles where it straddles the two almost exactly.
    Checked by eye on previews of both small cuts: the star stays a closed
    star, the hammer and sickle stay separate, and the pole stays one pixel
    with its black gap to the cloth.
    """
    if scale == 1:
        return art                              # identity: byte-identical output
    h, w = len(art), len(art[0])
    nh, nw = round(h * scale), round(w * scale)
    out = []
    for y in range(nh):
        line = ""
        for x in range(nw):
            x0, x1 = x * w / nw, (x + 1) * w / nw
            y0, y1 = y * h / nh, (y + 1) * h / nh
            area = {}
            for sy in range(int(y0), min(h, int(y1) + 1)):
                for sx in range(int(x0), min(w, int(x1) + 1)):
                    ov = ((min(x1, sx + 1) - max(x0, sx))
                          * (min(y1, sy + 1) - max(y0, sy)))
                    if ov > 0:
                        area[art[sy][sx]] = area.get(art[sy][sx], 0.0) + ov
            if scale < 1 and area.get("Y", 0.0) >= scale / 2 * sum(area.values()):
                line += "Y"
            else:
                line += max(area, key=area.get) if area else "."
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


def build(px_w=120, px_h=66, frames=8, amp=2.0, flag="soviet"):
    """Frames of a px_w x px_h grid of colour tags.

    The art is the traced flag, 72x66, scaled to stand the full height of the
    grid and centred in its width. At the 120x66 default that is 1:1 - no
    scaling, so nothing is softened, and the output is the file the 1080p
    login screen has always had. A taller grid scales it up, so the flag keeps
    the same share of the screen on a bigger panel instead of shrinking into
    one corner of it; a shorter one (768p, 900p) scales it down, so the whole
    flag fits instead of ly clipping the 1080p cut at every edge.

    Only the cloth columns are displaced; the pole and finial stay put, which
    is what makes it read as a flag on a pole rather than the whole picture
    sliding up and down.
    """
    scale = px_h / len(FLAG_ART)
    # Snap a near-integer scale to the integer: exact pixel doubling beats a
    # 2.03x resample that would widen every 33rd column for nothing.
    if scale >= 1 and scale - int(scale) < 0.1:
        scale = int(scale)
    art = scale_art(FLAG_ART, scale)
    # Painted after scaling, not before: scale_art's rule for keeping thin
    # yellow lines is for the pole and emblem, and would fatten a yellow
    # band or cross that was already wide.
    if FLAGS[flag]:
        art = paint_cloth(art, FLAGS[flag], STATIC_MAX_X * scale,
                          fine=flag in FINE)
    art_w, art_h = len(art[0]), len(art)
    # Never negative. The 768p canvas is exactly wide enough for the full
    # X_SHIFT (this comes out at 0 there); one cell narrower and a negative
    # offset would index the grid from its END, wrapping the pole round to
    # the right edge of the screen. Clamped, the flag just sits at the edge.
    x_off = max(0, (px_w - art_w) // 2 - X_SHIFT)
    y_off = (px_h - art_h) // 2
    # The wave is measured in art pixels, so it has to grow with the art or a
    # scaled-up flag would ripple less than the original.
    amp = amp * scale
    static_max_x = STATIC_MAX_X * scale
    out = []
    for f in range(frames):
        phase = 2 * math.pi * f / frames
        grid = [[None] * px_w for _ in range(px_h)]
        for ax in range(art_w):
            t = 2 * math.pi * max(0, ax - static_max_x) / (art_w - static_max_x)
            wave = int(round(amp * math.sin(1.5 * t - phase)))
            for ay in range(art_h):
                tag = art[ay][ax]
                if tag == "." or tag == "K":
                    continue                      # black: leave as background
                # pole and finial stay put; the cloth waves
                static = tag == "Y" and ax <= static_max_x
                ty = ay + y_off + (0 if static else wave)
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


def pair_cell(top, bottom, colours=COLOURS, filler=GOLD_FG):
    """The cell for two stacked art pixels of the painted flags (None is
    the black outside the cloth). A colour with a background fills the cell
    from behind; the other is drawn as a half or full block over it."""
    if top == bottom:
        if top is None:
            return (" ", filler, VOID_BG)
        fg, bg = colours[top]
        return (" ", filler, bg) if bg is not None else (BLOCK, fg, VOID_BG)
    for upper, lower, glyph in ((top, bottom, UPPER), (bottom, top, LOWER)):
        bg = VOID_BG if lower is None else colours[lower][1]
        if upper is not None and bg is not None:
            return (glyph, colours[upper][0], bg)
    raise ValueError(f"no cell can show {top} over {bottom}")


def to_dur(grids, px_w, rows, framerate=None, flag="soviet"):
    """Pack each vertical pair of art rows into one console cell."""
    assert rows % 2 == 0, "art rows must be even to pair into cells"
    cell_rows = rows // 2
    # The Soviet flag keeps its own table, so its files stay byte-identical.
    wide = flag in FORMAT_256
    if flag == "soviet":
        cell = PAIRS.__getitem__
    elif wide:
        cell = lambda p: pair_cell(*p, colours=COLOURS_256, filler=11)
    else:
        cell = lambda p: pair_cell(*p)
    frames = []
    for n, g in enumerate(grids, 1):
        contents, cmap = [], []
        cells = []
        for cy in range(cell_rows):
            row = [cell((g[2 * cy][cx], g[2 * cy + 1][cx])) for cx in range(px_w)]
            cells.append(row)
        contents = ["".join(c[0] for c in row) for row in cells]
        cmap = [[[cells[cy][cx][1], cells[cy][cx][2]] for cy in range(cell_rows)]
                for cx in range(px_w)]
        frames.append({"frameNumber": n, "delay": 0,
                       "contents": contents, "colorMap": cmap})
    return {"DurMovie": {
        "formatVersion": 7, "colorFormat": "256" if wide else "16", "preferredFont": "fixed",
        "encoding": "utf-8", "name": f"{flag}-flag", "artist": "",
        "framerate": FRAMERATE if framerate is None else framerate,
        "sizeX": px_w, "sizeY": cell_rows,
        "extra": None, "frames": frames}}


# Two files per panel, so config.ini can point at either one without
# regenerating anything: the waving flag, and a single still frame of it. The
# still frame is just build() with the wave switched off, which keeps both in
# lockstep with FLAG_ART instead of letting a hand-placed copy drift out of
# sync.
VARIANTS = {
    "animated": {"frames": 8, "amp": 2.0, "framerate": FRAMERATE},
    "static": {"frames": 1, "amp": 0.0, "framerate": 1.0},
}

# One canvas per panel. ly draws a .dur at its native cell size and never
# scales it, so a canvas smaller than the console grid leaves a black margin -
# which is exactly what a 120x33 flag did on a 1440p screen. /etc/ly/start.sh
# loads latarcyrheb-sun32, a 16x32 cell, so the grid is width/16 x height/32
# whatever ly_config.sh put in vconsole.conf, and the art canvas is that grid
# with the rows doubled: two art pixels per cell, upper and lower half block.
#
#   1366x768  ->  85x24 cells ->  85x48 art   scale 0.73
#   1600x900  -> 100x28 cells -> 100x56 art   scale 0.85
#   1920x1080 -> 120x33 cells -> 120x66 art   scale 1      (unchanged)
#   2560x1440 -> 160x45 cells -> 160x90 art   scale 1.36
#   3840x2160 -> 240x67 cells -> 240x134 art  scale 2 (snapped), 1 row spare
#
# The two small cuts exist because the 1080p one used to be the floor, and on
# a 1366x768 panel (the base T480) ly clipped 35 columns and 9 rows off it -
# the finial, the pole and the hoist edge of the cloth. ly_config.sh picks
# the largest cut that fits the grid in BOTH directions, reading sizeX/sizeY
# straight out of these files, so a new entry here needs nothing more than a
# regeneration.
PANELS = {
    "768p": (85, 48),
    "900p": (100, 56),
    "1080p": (120, 66),
    "1440p": (160, 90),
    "2160p": (240, 134),
}


def write_dur(out, px_w, px_h, frames, amp, framerate, flag="soviet"):
    grids, w, rows = build(px_w=px_w, px_h=px_h, frames=frames, amp=amp,
                           flag=flag)
    dur = to_dur(grids, w, rows, framerate=framerate, flag=flag)
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
    for arg in sys.argv[1:]:
        if arg not in PANELS and arg not in FLAGS:
            sys.exit(f"unknown panel or flag {arg!r}; panels: {', '.join(PANELS)}"
                     f"; flags: {', '.join(FLAGS)}")
    panels = [a for a in sys.argv[1:] if a in PANELS] or list(PANELS)
    flags = [a for a in sys.argv[1:] if a in FLAGS] or list(FLAGS)
    for flag in flags:
        for panel in panels:
            px_w, px_h = PANELS[panel]
            for variant, opts in VARIANTS.items():
                write_dur(os.path.join(here, f"{flag}-flag-{variant}-{panel}.dur"),
                          px_w, px_h, flag=flag, **opts)


# --- preview ---------------------------------------------------------------
def write_ppm(grid, px_w, rows, path, px=16):
    """Preview at one screen pixel per art pixel, using the RGBs measured off
    ly's framebuffer."""
    RGB = {"R": (0xAA, 0x00, 0x00), "Y": (0xFF, 0xFF, 0x55), "A": (0xFF, 0xFF, 0x55),
           "B": (0x00, 0x00, 0xAA), "G": (0x00, 0xAA, 0x00), "D": (0x14, 0x14, 0x14),
           "O": (0xFF, 0xD7, 0x00), "N": (0x14, 0x14, 0x14),
           "W": (0xFF, 0xFF, 0xFF), None: (20, 20, 20)}
    W, H = px_w * px, rows * px
    out = []
    for y in range(rows):
        line = bytearray()
        for x in range(px_w):
            line += bytes(RGB[grid[y][x]]) * px
        out.append(bytes(line) * px)
    open(path, "wb").write(f"P6\n{W} {H}\n255\n".encode() + b"".join(out))
