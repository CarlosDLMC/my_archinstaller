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
#   L    #00AAAA    6    6    light blue (Estonia, Greece, Luxembourg, San Marino)
#   Q    #FF55FF   13    -    orange (Ireland, Cyprus)
#   S    #AAAAAA    7    7    silver - the console's own light grey, unchanged
#
# start.sh redefines five console palette slots on ly's VT, which is what
# these become on screen: slot 8 (D) and slot 5 (N) to near-black #141414,
# slot 3 (O) to gold #FFD700, slot 6 (L) to light blue #2F80D0, slot 13 (Q)
# to orange #FF8C2A. Nothing else on the login screen uses them. O exists for
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
    "L": (6, 6),
    "Q": (13, None),
    "S": (7, 7),
}
FORMAT_256 = {"germany", "russianempire", "southkorea"}

# Flags with small emblems (stars, trigrams) are sampled 4x4 per pixel and
# take the majority, so a 4-pixel star is a star and not whichever colour
# one point in the middle of each pixel happened to land on.
FINE = {"china", "vietnam", "northkorea", "southkorea", "israel"}

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


def israel(u, v):
    """White, two blue stripes (15+25 in from each edge, of 160), and the
    Star of David between them: two triangle outlines, outer vertices at
    0.24 of the height from the centre, so it nearly fills the white band
    (0.25 each way) as on the real flag. The official line is 5.5/160 of the
    height, about a pixel and a half here, so it is drawn a little heavier,
    at 1/25 - any heavier and the star fills in."""
    x, y = (u - 0.5) * ASPECT, v - 0.5
    line = 1 / 25
    ri = 0.24 / 2                                # inradius = half the circumradius

    def inside(normals, d):
        return all(x * math.cos(a) + y * math.sin(a) <= d for a in normals)
    for normals in ((90, 210, 330), (270, 30, 150)):   # pointing up, down
        n = [math.radians(a) for a in normals]
        if inside(n, ri) and not inside(n, ri - line):
            return "B"
    return bands(v, (15 / 160, 40 / 160, 120 / 160, 145 / 160), "WBWBW")


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
    "israel": lambda u, v: israel(u, v),
}

# --- Europe ----------------------------------------------------------------
# The rest of Europe: the UN's list, plus Kosovo and Cyprus. All of these are
# written in the 256-colour format, for the extra colours below. Andorra,
# Serbia and San Marino are their civil flags, without arms (as Spain is);
# every other coat of arms is a small hand-drawn emblem, which at 15-25 art
# pixels can only be a likeness.

def mirror(left):
    """A symmetric bitmap from its left half, centre column included."""
    return [row + row[-2::-1] for row in left]


def bitmap(x, y, rows, cx, cy, h, recolour=None):
    """The tag of bitmap `rows` drawn h tall, centred on (cx, cy) in height
    units, at (x, y) - or None outside it or on a '.'."""
    bh, bw = len(rows), len(rows[0])
    w = h * bw / bh
    lx, ly = (x - cx) / w + 0.5, (y - cy) / h + 0.5
    if not (0 <= lx < 1 and 0 <= ly < 1):
        return None
    ch = rows[int(ly * bh)][int(lx * bw)]
    if ch == ".":
        return None
    return recolour.get(ch, ch) if recolour else ch


def with_emblem(field, *emblems):
    """A flag: emblems (functions of x, y returning a tag or None) over a
    field (a function of u, v)."""
    def paint(u, v):
        x, y = u * ASPECT, v
        for e in emblems:
            tag = e(x, y)
            if tag:
                return tag
        return field(u, v)
    return paint


def stripes_h(tags, widths=None):
    widths = widths or [1] * len(tags)
    total = sum(widths)
    edges = [sum(widths[:i + 1]) / total for i in range(len(widths))]
    return lambda u, v: bands(v, edges, tags)


def stripes_v(tags, widths=None):
    widths = widths or [1] * len(tags)
    total = sum(widths)
    edges = [sum(widths[:i + 1]) / total for i in range(len(widths))]
    return lambda u, v: bands(u, edges, tags)


EAGLE = mirror([                      # double-headed: Albania, Montenegro
    ".....NN....",
    "....NNNN...",
    "...NN.NNN..",
    "N.......NN.",
    "NN.......NN",
    "NNN.....NNN",
    "NNNN...NNNN",
    ".NNNN.NNNNN",
    "..NNNNNNNNN",
    "...NNNNNNNN",
    ".....NNNNNN",
    ".......NNNN",
    "......NN.NN",
    ".....NN..N.",
    "........NNN",
    ".......NN.N",
])

MOLDOVA = mirror([                    # eagle with cross, shield on its chest
    "......R",
    ".....RR",
    "......R",
    "R...RRR",
    "RR.RRRR",
    "RRRRBBB",
    ".RRRBBB",
    "..RRBBB",
    "...RRBB",
    "....RRR",
    ".....RR",
    "....R.R",
])

SLOVAKIA = [                          # double cross on three hills
    "WWWWWWWWWWW",
    "WRRRRWRRRRW",
    "WRRWWWWWRRW",
    "WRRRRWRRRRW",
    "WRWWWWWWWRW",
    "WRRRRWRRRRW",
    "WRRRRWRRRRW",
    "WRRRBBBRRRW",
    "WRBBBBBBBRW",
    "WBBBBBBBBBW",
    ".WBBBBBBBW.",
    "..WBBBBBW..",
    "....WWW....",
]

SLOVENIA = [                          # Triglav, two waves, three stars
    "RRRRRRRRRRR",
    "RBBOBBBOBBR",
    "RBBBBOBBBBR",
    "RBBBBBBBBBR",
    "RBBBBWBBBBR",
    "RBBBWWWBBBR",
    "RBWBWWWBWBR",
    "RBWWWWWWWBR",
    "RWBWBWBWBWR",
    "RBWBWBWBWBR",
    ".RBBBBBBBR.",
    "..RRBBBRR..",
    "....RRR....",
]

CROWN = mirror([                      # Liechtenstein
    ".....O",
    "....OO",
    ".....O",
    "..OOOO",
    ".OO.OO",
    "OO.OOO",
    "O.OOOO",
    "OOOOOO",
])


KOSOVO = [
    "...OOOO.....",
    "..OOOOOOO...",
    ".OOOOOOOOO..",
    "OOOOOOOOOOO.",
    "OOOOOOOOOOOO",
    ".OOOOOOOOOOO",
    "..OOOOOOOOO.",
    "...OOOOOOO..",
    "....OOOOO...",
    ".....OO.....",
]

CYPRUS = [                            # the island over two olive branches
    "..................QQ",
    "...............QQQQ.",
    "....QQQQQQQQQQQQQ...",
    ".QQQQQQQQQQQQQQQ....",
    "QQQQQQQQQQQQQQ......",
    ".QQQQQQQQQQQQ.......",
    "...QQQQQQQQ.........",
    ".....QQQQ...........",
    "....................",
    "..GG............GG..",
    "...GGG........GGG...",
    ".....GGGGGGGGGG.....",
]

GEORGE_CROSS = [                      # Malta
    "..RRRRR..",
    "..RSSSR..",
    "RRRSSSRRR",
    "RSSSSSSSR",
    "RSSSSSSSR",
    "RSSSSSSSR",
    "RRRSSSRRR",
    "..RSSSR..",
    "..RRRRR..",
]


def croatia_shield(x, y):
    """Red-and-white chequy, 5x5 from red, round at the foot, under a crown
    of five small blue shields."""
    cx, top, w, h = ASPECT / 2, 0.3, 0.3, 0.38
    lx, ly = (x - cx) / (w / 2), (y - top) / h      # -1..1 across, 0..1 down
    if -1 <= lx <= 1 and -0.22 <= ly < 0:
        return "L" if int((lx + 1) / 2 * 5) % 2 == 0 else "B"
    if not (-1 <= lx <= 1 and 0 <= ly <= 1):
        return None
    if ly > 0.6 and lx * lx + ((ly - 0.6) / 0.4) ** 2 > 1:
        return None
    i, j = int((lx + 1) / 2 * 5), int(ly * 5)
    return "R" if (i + j) % 2 == 0 else "W"


def portugal_arms(x, y):
    """The armillary sphere as a gold ring, with the shield - red border,
    white inside, five blue escutcheons - over it, on the green-red line."""
    cx, cy = ASPECT * 2 / 5, 0.5
    dx, dy = x - cx, y - cy
    if abs(dx) <= 0.11 and -0.13 <= dy <= 0.11 and dx * dx + max(0, dy) ** 2 * 1.5 <= 0.11 ** 2 * 1.6:
        inner = abs(dx) <= 0.075 and -0.095 <= dy <= 0.08
        if not inner:
            return "R"
        for qx, qy in ((0, -0.05), (-0.04, 0), (0, 0), (0.04, 0), (0, 0.05)):
            if abs(dx - qx) <= 0.013 and abs(dy - qy) <= 0.017:
                return "B"
        return "W"
    if 0.17 <= math.hypot(dx, dy) <= 0.21:
        return "O"
    return None


def north_macedonia(u, v):
    """Red; a gold sun, ringed red, with eight rays widening to the edges
    and corners."""
    x, y = u * ASPECT - ASPECT / 2, v - 0.5
    r = math.hypot(x, y)
    if r < 0.12:
        return "O"
    if r < 0.145:
        return "R"
    if r < 0.17:
        return "O"
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1),
                   (ASPECT / 2, 0.5), (-ASPECT / 2, 0.5), (ASPECT / 2, -0.5), (-ASPECT / 2, -0.5)):
        n = math.hypot(dx, dy)
        s = (x * dx + y * dy) / n                # along the ray
        t = abs(x * dy - y * dx) / n             # off it
        if s > 0 and t < 0.012 + 0.11 * s:
            return "O"
    return "R"


def union_jack(u, v):
    """Blue; white saltire with the red one counterchanged (offset to the
    same side of each arm, turning round the centre); red cross on white.
    Widths in 30ths of the height, as in the official 30x60."""
    x, y = u * ASPECT - ASPECT / 2, v - 0.5
    if abs(x) < 3 / 30 or abs(y) < 3 / 30:
        return "R"
    if abs(x) < 5 / 30 or abs(y) < 5 / 30:
        return "W"
    dx, dy = math.copysign(ASPECT / 2, x), math.copysign(0.5, y)
    n = math.hypot(dx, dy)
    # Signed distance off the arm. The same formula on all four arms turns
    # the red round the centre: below the white in the hoist's top quarter,
    # above it in the fly's - the "broad white uppermost at the hoist" rule.
    t = (x * dy - y * dx) / n
    if 0 < t < 2 / 30:
        return "R"
    if abs(t) < 3 / 30:
        return "W"
    return "B"


def greece(u, v):
    """Nine blue and white stripes; a blue canton five stripes square with
    a white cross one stripe wide."""
    x = u * ASPECT
    s = 1 / 9
    if x < 5 * s and v < 5 * s:
        return "W" if (2 * s <= x < 3 * s or 2 * s <= v < 3 * s) else "L"
    return "LWLWLWLWL"[min(8, int(v * 9))]


def switzerland(u, v):
    """Red; the white cross, arms 6/32 wide and 20/32 across, centred."""
    x, y = u * ASPECT - ASPECT / 2, v - 0.5
    a, b = 3 / 32, 10 / 32
    return "W" if (abs(x) < a and abs(y) < b) or (abs(y) < a and abs(x) < b) else "R"


def bosnia(u, v):
    """Blue; a gold right triangle, legs as long as the flag is tall, and
    white stars down its long side."""
    x, y = u * ASPECT, v
    x1 = (ASPECT - 1) / 2 + 0.05
    for k in range(9):
        s = k / 8
        if in_star(x, y, x1 + s - 0.085, s + 0.085, 0.055):
            return "W"
    if x <= x1 + 1 and x - x1 >= y:
        return "O"
    return "B"


def vatican_arms(x, y):
    """The tiara - gold, two silver bands, a small cross - over the crossed
    keys, gold and silver, drawn as shapes: as a 1-pixel bitmap they fell
    apart once the cloth waved."""
    cx, cy = ASPECT * 3 / 4, 0.5
    dx, dy = x - cx, y - (cy - 0.15)             # tiara origin: its base
    if abs(dx) <= 0.012 and -0.2 <= dy < -0.15:
        return "O"
    if (dy < 0 and (dx / 0.08) ** 2 + (dy / 0.15) ** 2 <= 1) or (0 <= dy <= 0.04 and abs(dx) <= 0.08):
        return "S" if -0.07 <= dy < -0.045 or 0 <= dy < 0.025 else "O"
    kx, ky = x - cx, y - (cy + 0.12)             # keys: crossing point
    for sign, tag in ((1, "O"), (-1, "S")):
        # shaft from the bow (lower) to the bit (upper), crossing at 0,0
        ax, ay = -0.14 * sign, 0.14              # bow end
        bx, by = 0.14 * sign, -0.14              # bit end
        if math.hypot(kx - ax, ky - ay) <= 0.045 and math.hypot(kx - ax, ky - ay) >= 0.02:
            return tag                           # the bow, a ring
        t = max(0, min(1, ((kx - ax) * (bx - ax) + (ky - ay) * (by - ay)) / ((bx - ax) ** 2 + (by - ay) ** 2)))
        if math.hypot(kx - (ax + t * (bx - ax)), ky - (ay + t * (by - ay))) <= 0.02:
            return tag                           # the shaft
        if abs(kx - (bx - 0.03 * sign)) <= 0.03 and abs(ky - (by + 0.05)) <= 0.025:
            return tag                           # the bit
    return None


def czechia(u, v):
    return "B" if u < 0.5 * (1 - abs(2 * v - 1)) else ("W" if v < 0.5 else "R")


def montenegro(u, v):
    x = u * ASPECT
    if x < 0.05 or x > ASPECT - 0.05 or v < 0.05 or v > 0.95:
        return "O"
    return bitmap(x, v, EAGLE, ASPECT / 2, 0.5, 0.6, {"N": "O"}) or "R"


def kosovo_stars(x, y):
    for k in range(6):
        a = math.radians(205 + 26 * k)
        if in_star(x, y, ASPECT / 2 + 0.42 * math.cos(a), 0.68 + 0.42 * math.sin(a), 0.04):
            return "W"
    return None


EUROPE = {
    "albania": with_emblem(lambda u, v: "R",
                           lambda x, y: bitmap(x, y, EAGLE, ASPECT / 2, 0.5, 0.7)),
    "andorra": stripes_v("BOR", (8, 9, 8)),
    "austria": stripes_h("RWR"),
    "belgium": stripes_v("NOR"),
    "bosnia": bosnia,
    "bulgaria": stripes_h("WGR"),
    "croatia": with_emblem(stripes_h("RWB"), croatia_shield),
    "cyprus": with_emblem(lambda u, v: "W",
                          lambda x, y: bitmap(x, y, CYPRUS, ASPECT / 2, 0.5, 0.5)),
    "czechia": czechia,
    "estonia": stripes_h("LNW"),
    "france": stripes_v("BWR"),
    "greece": greece,
    "hungary": stripes_h("RWG"),
    # 7+1+2+1+14 by 7+1+2+1+7, as Norway
    "iceland": nordic("B", "R", (8 / 25, 2 / 25), (8 / 18, 2 / 18),
                      "W", (7 / 25, 4 / 25), (7 / 18, 4 / 18)),
    "ireland": stripes_v("GWQ"),
    "kosovo": with_emblem(lambda u, v: "B", kosovo_stars,
                          lambda x, y: bitmap(x, y, KOSOVO, ASPECT / 2, 0.6, 0.42)),
    "latvia": stripes_h("RWR", (2, 1, 2)),
    "liechtenstein": with_emblem(stripes_h("BR"),
                                 lambda x, y: bitmap(x, y, CROWN, 0.38, 0.25, 0.3)),
    "lithuania": stripes_h("OGR"),
    "luxembourg": stripes_h("RWL"),
    "malta": with_emblem(stripes_v("WR"),
                         lambda x, y: bitmap(x, y, GEORGE_CROSS, 0.25, 0.22, 0.26)),
    "moldova": with_emblem(stripes_v("BOR"),
                           lambda x, y: bitmap(x, y, MOLDOVA, ASPECT / 2, 0.5, 0.5)),
    "monaco": stripes_h("RW"),
    "montenegro": montenegro,
    "netherlands": stripes_h("RWB"),
    "northmacedonia": north_macedonia,
    "portugal": with_emblem(stripes_v("GR", (2, 3)), portugal_arms),
    "romania": stripes_v("BOR"),
    "sanmarino": stripes_h("WL"),
    "serbia": stripes_h("RBW"),
    "slovakia": with_emblem(stripes_h("WBR"),
                            lambda x, y: bitmap(x, y, SLOVAKIA, 0.55, 0.5, 0.52)),
    "slovenia": with_emblem(stripes_h("WBR"),
                            lambda x, y: bitmap(x, y, SLOVENIA, 0.45, 0.36, 0.42)),
    "switzerland": switzerland,
    "unitedkingdom": union_jack,
    "vatican": with_emblem(stripes_v("OW"), vatican_arms),
}
FLAGS.update(EUROPE)
FORMAT_256.update(EUROPE)
FINE.update(EUROPE)


# --- beyond Europe ---------------------------------------------------------

MAPLE = mirror([                      # Canada
    ".......R",
    "......RR",
    "...R..RR",
    "...RR.RR",
    "R..RRRRR",
    "RR.RRRRR",
    "RRRRRRRR",
    ".RRRRRRR",
    "..RRRRRR",
    "RRRRRRRR",
    ".RRRRRRR",
    "..RRRRRR",
    "....RRRR",
    ".......R",
    ".......R",
    ".......R",
])


def usa(u, v):
    """Thirteen stripes from red; a blue canton seven stripes tall and 0.76
    of the height wide, with the 50 stars on their 6/5 rows. A star is a
    dot here - each is barely a pixel across."""
    x, y = u * ASPECT, v
    ch, cw = 7 / 13, 0.76
    if x < cw and y < ch:
        for r in range(9):
            sy = ch * (r + 1) / 10
            for c in range(6 if r % 2 == 0 else 5):
                sx = cw * (2 * c + (1 if r % 2 == 0 else 2)) / 12
                if (x - sx) ** 2 + (y - sy) ** 2 <= 0.021 ** 2:
                    return "W"
        return "B"
    return "RW"[min(12, int(v * 13)) % 2]


def argentina_sun(x, y):
    """The Sun of May: a gold disc and sixteen rays. The rays are wider
    than the real ones: thin, they lost the 4x4 vote at 768p and the sun
    shrank to a sliver."""
    dx, dy = x - ASPECT / 2, y - 0.5
    r = math.hypot(dx, dy)
    if r < 0.08:
        return "O"
    if r < 0.145 and math.cos(16 * math.atan2(dy, dx)) > -0.3:
        return "O"
    return None


def burgundy(u, v):
    """The Cross of Burgundy: a red saltire of two ragged branches, knots
    standing off each side in turn, on white."""
    x, y = u * ASPECT - ASPECT / 2, v - 0.5
    half = 0.045                                 # half the branch width
    for dx, dy in ((ASPECT / 2, 0.5), (ASPECT / 2, -0.5)):
        n = math.hypot(dx, dy)
        s = (x * dx + y * dy) / n                # along the branch
        t = (x * dy - y * dx) / n                # across it
        if abs(s) > 0.82 * n:
            continue
        if abs(t) <= half:
            return "R"
        k = round(s / 0.09)                      # nearest knot
        side = 1 if k % 2 == 0 else -1
        if abs(s - k * 0.09) <= 0.018 and 0 < t * side <= half + 0.04:
            return "R"
    return "W"


MORE = {
    "usa": usa,
    "canada": with_emblem(stripes_v("RWR", (1, 2, 1)),
                          lambda x, y: bitmap(x, y, MAPLE, ASPECT / 2, 0.5, 0.6)),
    "argentina": with_emblem(stripes_h("LWL"), argentina_sun),
    "spanishempire": burgundy,
    "germanempire": stripes_h("NWR"),
}
FLAGS.update(MORE)
FORMAT_256.update(MORE)
FINE.update(MORE)


def in_star_n(x, y, cx, cy, r, ri, n, up=-math.pi / 2):
    """Like in_star, for n points with inner radius ri (Malaysia's 14)."""
    dx, dy = x - cx, y - cy
    rho = math.hypot(dx, dy)
    if rho > r:
        return False
    if rho <= ri:
        return True
    a = (math.atan2(dy, dx) - up) % (2 * math.pi / n)
    b = abs(a - math.pi / n)
    px, py = rho * math.cos(b), rho * math.sin(b)
    tx, ty = r * math.cos(math.pi / n), r * math.sin(math.pi / n)
    return (tx - ri) * py - ty * (px - ri) >= 0


def crescent(x, y, cx, cy, r, shift, r2):
    """A disc of radius r less one of radius r2 moved `shift` to the fly."""
    return (math.hypot(x - cx, y - cy) <= r
            and math.hypot(x - cx - shift, y - cy) > r2)


IRAN = mirror([                       # the emblem, a tulip of crescents
    ".....R",
    "..R..R",
    ".RR..R",
    "RR..RR",
    "R..R.R",
    "R.RR.R",
    "R.R..R",
    "R.R..R",
    "RR..RR",
    ".RR..R",
    "..RRRR",
    "....RR",
])


def iran(u, v):
    """Green, white, red; the red emblem in the middle; the takbir - 11
    times along each edge of the white - as a row of white marks inside the
    green and the red, its script being far below a pixel."""
    x, y = u * ASPECT, v
    e = bitmap(x, y, IRAN, ASPECT / 2, 0.5, 0.26)
    if e:
        return e
    k = (u * 11) % 1
    if 0.3 < k < 0.7 and (1 / 3 - 0.05 <= v < 1 / 3 - 0.02 or 2 / 3 + 0.02 <= v < 2 / 3 + 0.05):
        return "W"
    return bands(v, (1 / 3, 2 / 3), "GWR")


def mozambique(u, v):
    """Green, black, yellow, edged white; a red triangle from the hoist with
    the yellow star, and on it the book (white) under the rifle and hoe,
    crossed (black)."""
    x, y = u * ASPECT, v
    apex = 0.46 * ASPECT
    if x < apex * (1 - abs(2 * v - 1)):
        sx, sy = apex * 0.36, 0.5
        dx, dy = x - sx, y - sy
        if in_star(x, y, sx, sy, 0.17):
            if abs(dy - 0.035) <= 0.025 and abs(dx) <= 0.07:
                return "W"                       # the book
            if abs(abs(dx) - (0.02 - dy)) <= 0.012 and abs(dx) <= 0.08 and dy <= 0.02:
                return "N"                       # rifle and hoe, crossed
            return "O"
        return "R"
    return bands(v, (6 / 20, 7 / 20, 13 / 20, 14 / 20), "GWNWO")


def chile(u, v):
    """White over red; a square blue canton the white's height, its white
    star half the canton across."""
    x = u * ASPECT
    if x < 0.5 and v < 0.5:
        return "W" if in_star(x, v, 0.25, 0.25, 0.125) else "B"
    return "W" if v < 0.5 else "R"


def singapore(u, v):
    """Red over white; in the red, a white crescent and five stars in a
    ring."""
    x = u * ASPECT
    if v < 0.5:
        if crescent(x, v, 0.27, 0.25, 0.155, 0.055, 0.15):
            return "W"
        for k in range(5):
            a = -math.pi / 2 + 2 * math.pi * k / 5
            # larger than the real stars, which at 0.035 were single dots
            if in_star(x, v, 0.40 + 0.095 * math.cos(a), 0.25 + 0.095 * math.sin(a), 0.048):
                return "W"
        return "R"
    return "W"


def malaysia(u, v):
    """Fourteen stripes from red; a blue canton eight stripes tall and half
    the length, with the gold crescent and the 14-pointed star."""
    x = u * ASPECT
    if x < ASPECT / 2 and v < 8 / 14:
        cy = 4 / 14
        if crescent(x, v, 0.34, cy, 0.21, 0.06, 0.185):
            return "O"
        if in_star_n(x, v, 0.68, cy, 0.17, 0.07, 14):
            return "O"
        return "B"
    return "RW"[min(13, int(v * 14)) % 2]


MORE2 = {
    "iran": iran,
    "mozambique": mozambique,
    "chile": chile,
    "singapore": singapore,
    "malaysia": malaysia,
}
FLAGS.update(MORE2)
FORMAT_256.update(MORE2)
FINE.update(MORE2)


# --- the rest of the post-Soviet states --------------------------------------

KZ_EAGLE = mirror([                   # Kazakhstan's steppe eagle
    "O......",
    "OO.....",
    ".OOO...",
    "..OOOO.",
    "...OOOO",
    ".....OO",
])

KZ_ORNAMENT = [                       # one repeat of the hoist ornament
    "O...O",
    ".O.O.",
    "..O..",
    ".O.O.",
    "O...O",
    "OO.OO",
]

TJ_CROWN = [
    "....O....",
    ".O..O..O.",
    ".OOOOOOO.",
    "OOOOOOOOO",
]


def georgia(u, v):
    """White; the red St George's cross, a fifth of the height wide; a red
    Bolnisi cross in each quarter, drawn as a plain cross at this size."""
    x, y = u * ASPECT, v
    if abs(x - ASPECT / 2) < 0.1 or abs(y - 0.5) < 0.1:
        return "R"
    for cx in (ASPECT / 4 - 0.02, ASPECT * 3 / 4 + 0.02):
        for cy in (0.22, 0.78):
            dx, dy = abs(x - cx), abs(y - cy)
            if (dx < 0.028 and dy < 0.085) or (dy < 0.028 and dx < 0.085):
                return "R"
    return "W"


def azerbaijan(u, v):
    """Light blue, red, green; in the red, a white crescent and 8-pointed
    star."""
    x = u * ASPECT
    if 1 / 3 <= v < 2 / 3:
        if crescent(x, v, ASPECT / 2 - 0.04, 0.5, 0.12, 0.035, 0.1):
            return "W"
        if in_star_n(x, v, ASPECT / 2 + 0.105, 0.5, 0.08, 0.045, 8):
            return "W"
    return bands(v, (1 / 3, 2 / 3), "LRG")


def kazakhstan(u, v):
    """Sky blue; a gold sun and the steppe eagle under it; the gold
    ornament down the hoist."""
    x, y = u * ASPECT, v
    if 0.06 <= x < 0.15:
        tag = bitmap(x, ((y * 6) % 1) * 0.15 + 0.5, KZ_ORNAMENT, 0.105, 0.575, 0.15)
        return tag or "L"
    dx, dy = x - ASPECT / 2, y - 0.4
    r = math.hypot(dx, dy)
    if r < 0.1 or (r < 0.165 and math.cos(32 * math.atan2(dy, dx)) > -0.3):
        return "O"
    return bitmap(x, y, KZ_EAGLE, ASPECT / 2, 0.66, 0.13) or "L"


def kyrgyzstan(u, v):
    """Red; a gold sun of 40 rays with the tunduk - the yurt's crown - in
    red on it, as a ring crossed by a plus."""
    x, y = u * ASPECT - ASPECT / 2, v - 0.5
    r = math.hypot(x, y)
    if r < 0.13:
        if 0.07 <= r < 0.092 or (r < 0.07 and (abs(x) < 0.016 or abs(y) < 0.016)):
            return "R"
        return "O"
    if r < 0.26 and math.cos(40 * math.atan2(y, x)) > -0.3:
        return "O"
    return "R"


def tajikistan(u, v):
    """Red, white, green at 2+3+2; in the white, the gold crown under an
    arc of seven stars."""
    x, y = u * ASPECT, v
    tag = bitmap(x, y, TJ_CROWN, ASPECT / 2, 0.55, 0.12)
    if tag:
        return tag
    for k in range(7):
        a = math.radians(200 + 140 * k / 6)
        if in_star(x, y, ASPECT / 2 + 0.2 * math.cos(a), 0.62 + 0.2 * math.sin(a), 0.042):
            return "O"
    return bands(v, (2 / 7, 5 / 7), "RWG")


def turkmenistan(u, v):
    """Green; the red carpet band near the hoist with five guls stacked in
    it; a white crescent and five stars beside it."""
    x, y = u * ASPECT, v
    if 0.16 <= x < 0.38:
        cx = 0.27
        for k in range(5):
            cy = 0.1 + 0.2 * k
            d = abs(x - cx) / 0.09 + abs(y - cy) / 0.085
            if d <= 1:
                return "O" if d > 0.62 else ("W" if d < 0.3 else "N")
        return "R"
    if crescent(x, y, 0.6, 0.22, 0.11, 0.04, 0.1):
        return "W"
    for k in range(5):
        a = math.radians(-60 + 30 * k)
        if in_star(x, y, 0.6 + 0.16 * math.cos(a), 0.22 + 0.16 * math.sin(a), 0.042):
            return "W"
    return "G"


def uzbekistan(u, v):
    """Light blue, white, green, edged red; in the blue, a white crescent
    and twelve stars in rows of 3, 4 and 5."""
    x, y = u * ASPECT, v
    if v < 10 / 32:
        if crescent(x, y, 0.25, 0.155, 0.1, 0.04, 0.09):
            return "W"
        for row, n in enumerate((3, 4, 5)):
            for k in range(n):
                sx, sy = 0.78 - 0.075 * k, 0.065 + 0.08 * row
                if (x - sx) ** 2 + (y - sy) ** 2 <= 0.022 ** 2:
                    return "W"
    return bands(v, (10 / 32, 11 / 32, 21 / 32, 22 / 32), "LRWRG")


POST_SOVIET = {
    "armenia": stripes_h("RBO"),
    "azerbaijan": azerbaijan,
    "georgia": georgia,
    "kazakhstan": kazakhstan,
    "kyrgyzstan": kyrgyzstan,
    "tajikistan": tajikistan,
    "turkmenistan": turkmenistan,
    "uzbekistan": uzbekistan,
}
FLAGS.update(POST_SOVIET)
FORMAT_256.update(POST_SOVIET)
FINE.update(POST_SOVIET)


# --- Vikings and Crusaders ---------------------------------------------------

RAVEN = [                             # wings up, head and beak to the fly
    "..N.........N....",
    "..NN.......NN....",
    "...NN.....NNN....",
    "...NNN...NNNN....",
    "....NNN.NNNN.....",
    "....NNNNNNNN.....",
    ".....NNNNNNN..NN.",
    ".....NNNNNNNNNNNN",
    "....NNNNNNNNNNN..",
    "..NNNNNNNNNNN....",
    "NNNN.NNNNNNN.....",
    "N....NN..NN......",
    ".....N....N......",
    "....NN...NN......",
]


def raven(u, v):
    """The Raven Banner as a pennant: a white quarter-round from the hoist,
    fringed red along its curve, with the black raven. Outside the quarter
    is 'K', which is left as screen black - the cloth still waves, only the
    pennant shows."""
    r = math.hypot(u, v)
    if r > 1:
        return "K"
    if r > 0.9:
        return "R" if math.cos(30 * math.atan2(v, u)) > 0 else "K"
    return bitmap(u * ASPECT, v, RAVEN, 0.6, 0.37, 0.52) or "W"


def jerusalem(u, v):
    """Gold on white: a cross potent - each arm ending in a crossbar - and a
    small cross in each quarter."""
    x, y = u * ASPECT - ASPECT / 2, v - 0.5
    ax, ay = abs(x), abs(y)
    arm, reach = 0.055, 0.34
    if (ax <= arm and ay <= reach) or (ay <= arm and ax <= reach):
        return "O"
    if (reach - 0.065 <= ay <= reach and ax <= 0.15) or (reach - 0.065 <= ax <= reach and ay <= 0.15):
        return "O"
    for cx in (-0.2, 0.2):
        for cy in (-0.2, 0.2):
            dx, dy = abs(x - cx), abs(y - cy)
            if (dx <= 0.022 and dy <= 0.075) or (dy <= 0.022 and dx <= 0.075):
                return "O"
    return "W"


def templar(u, v):
    """White; a red cross pattée, arms flaring from narrow at the centre."""
    x, y = u * ASPECT - ASPECT / 2, v - 0.5
    ax, ay = abs(x), abs(y)
    if ax >= ay:
        return "R" if ax <= 0.42 and ay <= 0.04 + 0.4 * ax else "W"
    return "R" if ay <= 0.42 and ax <= 0.04 + 0.4 * ay else "W"


def hospitaller(u, v):
    """Red; a plain white cross to the edges."""
    x, y = u * ASPECT - ASPECT / 2, v - 0.5
    return "W" if abs(x) <= 0.1 or abs(y) <= 0.1 else "R"


HISTORIC = {
    "raven": raven,
    "jerusalem": jerusalem,
    "templar": templar,
    "hospitaller": hospitaller,
}
FLAGS.update(HISTORIC)
FORMAT_256.update(HISTORIC)
FINE.update(HISTORIC)


# --- crosses ---------------------------------------------------------------

ALPHA = [
    "..O..",
    ".O.O.",
    ".OOO.",
    "O...O",
    "O...O",
]

OMEGA = [
    ".OOO.",
    "O...O",
    "O...O",
    ".O.O.",
    "OO.OO",
]

FIRESTEEL = [                         # the Byzantine "B", facing the fly
    "OOO.",
    "O..O",
    "OOO.",
    "O..O",
    "OOO.",
]

SANTIAGO = [                          # the sword-cross of St James
    "....RRR....",
    "...R.R.R...",
    "....RRR....",
    ".....R.....",
    ".R...R...R.",
    "R.R.RRR.R.R",
    "RRRRRRRRRRR",
    "R.R.RRR.R.R",
    ".R...R...R.",
    ".....R.....",
    "....RRR....",
    "....RRR....",
    "....RRR....",
    "....RRR....",
    "....RRR....",
    ".....R.....",
    ".....R.....",
]


def asturias(u, v):
    """Blue; the gold Victory Cross, a Latin cross with flared ends, with
    Alpha and Omega hanging from its arms."""
    x, y = u * ASPECT - ASPECT / 2, v
    ax = abs(x)
    vert = ax <= (0.05 if 0.17 < y < 0.84 else 0.08) and 0.1 <= y <= 0.9
    horiz = abs(y - 0.33) <= (0.05 if ax < 0.22 else 0.08) and ax <= 0.28
    if vert or horiz:
        return "O"
    return (bitmap(x, y, ALPHA, -0.2, 0.5, 0.12)
            or bitmap(x, y, OMEGA, 0.2, 0.5, 0.12) or "L")


def christian(u, v):
    """White; a blue canton, half the height tall, with the red Latin
    cross."""
    x, y = u * ASPECT, v
    if x < 0.7 and y < 0.5:
        if (abs(x - 0.35) <= 0.035 and 0.07 <= y <= 0.44) or (abs(y - 0.2) <= 0.035 and abs(x - 0.35) <= 0.16):
            return "R"
        return "B"
    return "W"


def byzantine(u, v):
    """Red; a gold cross to the edges and a gold firesteel in each quarter,
    the two at the hoist turned to face away from the cross."""
    x, y = u * ASPECT - ASPECT / 2, v - 0.5
    if abs(x) <= 0.05 or abs(y) <= 0.05:
        return "O"
    fly = [row for row in FIRESTEEL]
    hoist = [row[::-1] for row in FIRESTEEL]
    for cx, rows in ((-ASPECT / 4, hoist), (ASPECT / 4, fly)):
        for cy in (-0.25, 0.25):
            if bitmap(x, y, rows, cx, cy, 0.28):
                return "O"
    return "R"


CROSSES = {
    "asturias": asturias,
    "christian": christian,
    "byzantine": byzantine,
    "santiago": with_emblem(lambda u, v: "W",
                            lambda x, y: bitmap(x, y, SANTIAGO, ASPECT / 2, 0.5, 0.78)),
}
FLAGS.update(CROSSES)
FORMAT_256.update(CROSSES)
FINE.update(CROSSES)


# --- Rome, and Russia before 1858 ----------------------------------------------

AQUILA = [                            # the legionary eagle
    "O.............O",
    "OO...........OO",
    "OOO....O....OOO",
    ".OOO..OOO..OOO.",
    "..OOOOOOOOOOO..",
    "...OOOOOOOOO...",
    ".....OOOOO.....",
    "......OOO......",
    ".....O.O.O.....",
    "....OOOOOOO....",
]

SPQR = [
    "OOO.OOO.OOO.OO.",
    "O...O.O.O.O.O.O",
    "OOO.OOO.O.O.OO.",
    "..O.O...OOO.O.O",
    "OOO.O.....O.O.O",
]


def roman(u, v):
    """A red vexillum: the gold eagle over SPQR, and a gold fringe along the
    foot."""
    x, y = u * ASPECT, v
    if y > 0.93:
        return "O" if math.cos(60 * u) > 0 else "K"
    return (bitmap(x, y, AQUILA, ASPECT / 2, 0.33, 0.36)
            or bitmap(x, y, SPQR, ASPECT / 2, 0.72, 0.18) or "R")


def standrew(u, v):
    """White; the blue saltire of St Andrew, corner to corner - the Russian
    Navy's ensign from 1712."""
    x, y = u * ASPECT - ASPECT / 2, v - 0.5
    for dx, dy in ((ASPECT / 2, 0.5), (ASPECT / 2, -0.5)):
        if abs(x * dy - y * dx) / math.hypot(dx, dy) <= 0.07:
            return "B"
    return "W"


OLD_RUSSIA = {
    "roman": roman,
    # 1693, Peter the Great: the first tricolour, the double eagle in gold
    "tsarofmoscow": with_emblem(stripes_h("WBR"),
                                lambda x, y: bitmap(x, y, EAGLE, ASPECT / 2, 0.5, 0.62, {"N": "O"})),
    "standrew": standrew,
    # 1742: the Tsar's standard, a black double eagle on gold
    "tsarstandard": with_emblem(lambda u, v: "O",
                                lambda x, y: bitmap(x, y, EAGLE, ASPECT / 2, 0.5, 0.72)),
}
FLAGS.update(OLD_RUSSIA)
FORMAT_256.update(OLD_RUSSIA)
FINE.update(OLD_RUSSIA)


# --- the Palaestinalied ----------------------------------------------------------
# Not a historical flag: a banner for Walther von der Vogelweide's
# Palaestinalied (c. 1228) - "Nu alrerst lebe ich mir werde, sit min sundic
# ouge siht daz here lant". Frederick II's crusade won Jerusalem back by
# treaty and he was crowned its king in 1229, so his two arms side by side:
# the Empire at the hoist, the Holy Land at the fly.

REICHSADLER = [                       # head to the hoist, wings spread
    "......NN.......",
    ".....NNN.......",
    "....NN.N.......",
    "......NN.......",
    "NNNN..NNN..NNNN",
    "NNNNNNNNNNNNNNN",
    ".NNNNNNNNNNNNN.",
    "..NNNNNNNNNNN..",
    "N.N.N.NNN.N.N.N",
    "....N.NNN.N....",
    "...NN.NNN.NN...",
    ".....NNNNN.....",
    "....NN.N.NN....",
    "...N..N.N..N...",
]


def palaestinalied(u, v):
    x, y = u * ASPECT, v
    if u < 0.5:
        return bitmap(x, y, REICHSADLER, ASPECT / 4, 0.5, 0.66) or "O"
    dx, dy = x - ASPECT * 3 / 4, y - 0.5
    ax, ay = abs(dx), abs(dy)
    arm, reach, bar = 0.04, 0.26, 0.11
    if (ax <= arm and ay <= reach) or (ay <= arm and ax <= reach):
        return "O"
    if (reach - 0.05 <= ay <= reach and ax <= bar) or (reach - 0.05 <= ax <= reach and ay <= bar):
        return "O"
    for cx in (-0.15, 0.15):
        for cy in (-0.15, 0.15):
            ex, ey = abs(dx - cx), abs(dy - cy)
            if (ex <= 0.02 and ey <= 0.06) or (ey <= 0.02 and ex <= 0.06):
                return "O"
    return "W"


FLAGS["palaestinalied"] = palaestinalied
FORMAT_256.add("palaestinalied")
FINE.add("palaestinalied")



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
        # Divided, not multiplied by du/dv: the two differ in the last bit,
        # and stripe and cross edges that land exactly on a pixel centre
        # (Finland's, at 1440p) would flip with it.
        u = (x - x0 + 0.5) / (x1 - x0 + 1)
        for y in ys:
            v = (y - y0 + 0.5) / (y1 - y0 + 1)
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
    # Two foreground-only colours (white and orange, say): no cell holds
    # both, so it takes one whole, the one that is not white - an emblem
    # edge is a cell coarser there rather than missing.
    return (BLOCK, colours[bottom if top == "W" else top][0], VOID_BG)


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
           "L": (0x2F, 0x80, 0xD0), "Q": (0xFF, 0x8C, 0x2A), "S": (0xAA, 0xAA, 0xAA),
           "W": (0xFF, 0xFF, 0xFF), None: (20, 20, 20)}
    W, H = px_w * px, rows * px
    out = []
    for y in range(rows):
        line = bytearray()
        for x in range(px_w):
            line += bytes(RGB[grid[y][x]]) * px
        out.append(bytes(line) * px)
    open(path, "wb").write(f"P6\n{W} {H}\n255\n".encode() + b"".join(out))
