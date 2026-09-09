#!/usr/bin/env python3
"""Generate an 8-bit waving Soviet flag as a durdraw .dur for ly.

A cell on the Linux console is 16x32 px, so one square "pixel" is 2 cells
wide by 1 row tall. The flag is drawn on a pixel grid and expanded to cells
on output, which is what keeps it from looking stretched.

Colour is carried by each cell's BACKGROUND, with a space as the character:
every console font has a space, so nothing depends on block glyphs being
present in latarcyrheb-sun32.
"""
import gzip, json, math, sys

# --- artwork ---------------------------------------------------------------
# Traced from ~/Downloads/soviet_pixel_flag.svg, supplied by the user. That
# file was already pixel art (501 <rect> on a 12px grid = a 100x100 canvas),
# so the emblem was lifted by connected-component search over its yellow
# cells rather than by tracing a photo. Its star is an outline, so the
# interior was flood-filled, then area-downsampled to 7x7.
#
# The hammer and sickle is kept at its NATIVE 18x17. Downsampling it to 15x14
# destroyed the sickle's 1px blade and it went back to reading as a blob, so
# the flag's height is budgeted around this size instead.
#
# Earlier attempts at generating the emblem all failed at this resolution: an
# arc segment reads as a hook, a lune reads as an ANCHOR, and a hammer head
# rotated to the shaft's own angle merely extends it into an arrow.

STAR = [
    "...#...",
    "...#...",
    "#######",
    ".#####.",
    "..###..",
    ".#####.",
    ".#...#.",
]

HAMMER_SICKLE = [
    "...........##.....",
    ".............#....",
    "..............#...",
    "..............#...",
    ".......#####...#..",
    "......#####....#..",
    ".....#####.....#..",
    "....#######....#..",
    ".....#######...#..",
    "......#..####.#...",
    "..........#####...",
    "...........####...",
    "...#############..",
    "..###.#####..####.",
    ".###..........####",
    "###............##.",
    ".#................",
]

# ly's dur palette is its own, and foreground and background use DIFFERENT
# tables. Read off the real framebuffer with labelled test cards (indices
# 4..11 render black in both tables, which is why guessing never worked):
#
#   background: 0 #000000  1 #0000AA  2 #00AA00  3 #00AAAA
#               12 #AA0000  13 #AA00AA  14 #AA5500  15 #AAAAAA
#   foreground: 2 #0000AA  3 #00AA00  12 #55FFFF
#               13 #FF5555  14 #FF55FF  15 #FFFF55
#
# So: red field from bg 12, highlights from fg 13, and yellow ONLY from fg 15
# (bg 15 is grey). Anything drawn in a foreground colour needs a glyph, hence
# the block and shade characters - all present in latarcyrheb-sun32, the font
# ly loads via /etc/ly/start.sh.
#
# ly also snaps its own `bg`/`fg` config values to this palette, so setting
# bg = 0x00AA0000 in config.ini lands exactly on the field colour. That makes
# the bigclock's gaps - which ly paints with bg - disappear into the cloth,
# and is why the flag now fills the screen: with a red background there is no
# longer anywhere for a transparent edge to sit.
RED_BG = 12        # #AA0000, the field
LIT_FG = 13        # #FF5555 - a lighter red. NOT used: shading the
                   # field with several reds was tried and rejected,
                   # the flag reads better as one flat red.
DARK_FG = 4        # #000000 - likewise unused, see LIT_FG.
GOLD_FG = 15       # #FFFF55, the emblem
VOID_BG = 0        # #000000, outside the cloth - matches ly's bg
BLOCK = "\u2588"   # full block
SHADE = "\u2591"   # light shade, for the shadow dither

def emblem_mask():
    """Gold mask: star, a gap, then the hammer and sickle. They live in
    separate blocks because drawn together the blade's top edge ran into the
    star. Returns (mask, width, height)."""
    gap = 1
    w = len(HAMMER_SICKLE[0])
    star_w = len(STAR[0])
    h = len(STAR) + gap + len(HAMMER_SICKLE)
    m = [[False] * w for _ in range(h)]
    sx0 = (w - star_w) // 2
    for j, row in enumerate(STAR):
        for i, ch in enumerate(row):
            if ch == "#":
                m[j][sx0 + i] = True
    top = len(STAR) + gap
    for j, row in enumerate(HAMMER_SICKLE):
        for i, ch in enumerate(row):
            if ch == "#":
                m[top + j][i] = True
    return m, w, h


def build(px_w=56, px_h=28, frames=8, pad=2, emb_x=1, emb_y=1):
    """One frame per phase.

    The flag is smaller than the console so its top and bottom edges can
    undulate against ly's background, which is black. Colour comes from the
    palette measured off the framebuffer: bg 12 field, fg 13 crest, a black
    dither for the trough, fg 15 emblem.
    """
    mask, emb_w, emb_h = emblem_mask()
    rows_total = px_h + pad * 2
    out = []
    for f in range(frames):
        phase = 2 * math.pi * f / frames
        grid = [[None] * px_w for _ in range(rows_total)]
        for x in range(px_w):
            t = 2 * math.pi * x / px_w
            # the cloth rises and falls
            shift = int(round(1.6 * math.sin(t - phase)
                              + 0.7 * math.sin(2 * t - phase * 1.7)))
            for y in range(px_h):
                ty = y + pad + shift
                if not (0 <= ty < rows_total):
                    continue
                ex, ey = x - emb_x, y - emb_y
                if 0 <= ex < emb_w and 0 <= ey < emb_h and mask[ey][ex]:
                    grid[ty][x] = (BLOCK, GOLD_FG, RED_BG)
                else:
                    grid[ty][x] = (" ", GOLD_FG, RED_BG)
        out.append(grid)
    return out, px_w, rows_total


def to_dur(grids, px_w, rows, framerate=8.0):
    cell_w = px_w * 2                      # 2 cells per square pixel
    frames = []
    for n, g in enumerate(grids, 1):
        contents = []
        for y in range(rows):
            contents.append("".join(
                (g[y][cx // 2] or (" ", GOLD_FG, VOID_BG))[0]
                for cx in range(cell_w)))
        # colourMap is [x][y] -> [fg, bg]
        cmap = []
        for cx in range(cell_w):
            col = []
            for y in range(rows):
                c = g[y][cx // 2]
                col.append([GOLD_FG, VOID_BG] if c is None
                           else [c[1], c[2]])
            cmap.append(col)
        frames.append({"frameNumber": n, "delay": 0,
                       "contents": contents, "colorMap": cmap})
    return {"DurMovie": {
        "formatVersion": 7, "colorFormat": "16", "preferredFont": "fixed",
        "encoding": "utf-8", "name": "soviet-flag", "artist": "",
        "framerate": framerate, "sizeX": cell_w, "sizeY": rows,
        "extra": None, "frames": frames}}


if __name__ == "__main__":
    grids, w, rows = build()
    dur = to_dur(grids, w, rows)
    out = sys.argv[1] if len(sys.argv) > 1 else "soviet-flag.dur"
    # mtime=0 so regenerating identical art produces an identical file, and
    # the repo does not show a diff just because gzip stamped the time.
    # Write through a file object with mtime=0: GzipFile embeds both a
    # timestamp AND, if given a filename, that name - either makes the output
    # differ run to run and churns the repo for no reason.
    with open(out, "wb") as raw:
        with gzip.GzipFile(fileobj=raw, mode="wb", compresslevel=9, mtime=0) as fh:
            fh.write(json.dumps(dur).encode())
    print(f"wrote {out}: {dur['DurMovie']['sizeX']}x{dur['DurMovie']['sizeY']} cells, "
          f"{len(dur['DurMovie']['frames'])} frames")
    # text preview of frame 0
    for y in range(rows):
        print("".join(
            "·" if grids[0][y][x] is None
            else ("@" if grids[0][y][x][0] != " " else "▒")
            for x in range(w)))


# --- preview ---------------------------------------------------------------
def write_ppm(grid, px_w, rows, path, cw=16, ch=32):
    """Preview using the RGBs actually measured off ly's framebuffer, so this
    matches the console rather than approximating it. The shade glyph is a
    dither, so it is previewed as its blended average."""
    RGB = {
        (BLOCK, GOLD_FG): (0xFF, 0xFF, 0x55),   # emblem
        (BLOCK, LIT_FG): (0xFF, 0x55, 0x55),    # fold crest
        (SHADE, DARK_FG): (0x80, 0x00, 0x00),   # trough: black dithered on red
        (" ", GOLD_FG): (0xAA, 0x00, 0x00),     # the field
    }
    W, H = px_w * 2 * cw, rows * ch
    hdr = f"P6\n{W} {H}\n255\n".encode()
    out = []
    for y in range(rows):
        line = bytearray()
        for cx in range(px_w * 2):
            cell = grid[y][cx // 2]
            if cell is None:
                line += bytes((20, 20, 20)) * cw
                continue
            ch_, fg, _ = cell
            line += bytes(RGB.get((ch_, fg), (0xAA, 0, 0))) * cw
        out.append(bytes(line) * ch)
    open(path, "wb").write(hdr + b"".join(out))
