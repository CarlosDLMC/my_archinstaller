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

# ly's dur palette is NOT the xterm/ANSI palette, and its foreground and
# background tables do not even agree with each other. Established on this
# machine by putting labelled test cards in front of the real greeter:
#
#     background 12          -> RED      (what the field uses)
#     background 15          -> orange
#     foreground 15 + U+2588 -> YELLOW   (what the emblem uses)
#     colorFormat "256"      -> renders orange/grey, unusable
#
# So the emblem is painted as full-block glyphs with a FOREGROUND colour,
# never as a background fill. U+2588 is present in latarcyrheb-sun32 (glyph
# 216), which is the font ly loads via /etc/ly/start.sh.
#
# Only one red is confirmed, so the field is flat. The three-tone fold shading
# the 256 palette allowed is gone with it; to restore it, map two more red
# background indices with a test card and shade on those.
RED_BG = 12        # field
GOLD_FG = 15       # emblem, foreground only
BLOCK = "\u2588"
VOID_BG = 0        # outside the cloth


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
    mask, emb_w, emb_h = emblem_mask()
    rows_total = px_h + pad * 2
    out = []
    for f in range(frames):
        phase = 2 * math.pi * f / frames
        # colour per cell, indexed [y][x] in pixels
        grid = [[None] * px_w for _ in range(rows_total)]
        for x in range(px_w):
            t = 2 * math.pi * x / px_w
            # vertical displacement: one long wave plus a shorter ripple
            shift = int(round(1.6 * math.sin(t - phase)
                              + 0.7 * math.sin(2 * t - phase * 1.7)))
            for y in range(px_h):
                ty = y + pad + shift
                if not (0 <= ty < rows_total):
                    continue
                ex, ey = x - emb_x, y - emb_y
                on_emblem = 0 <= ex < emb_w and 0 <= ey < emb_h and mask[ey][ex]
                # emblem: block glyph in the foreground colour, because a
                # background fill of the same index renders orange.
                grid[ty][x] = ((BLOCK, GOLD_FG, RED_BG) if on_emblem
                               else (" ", GOLD_FG, RED_BG))
        out.append(grid)
    return out, px_w, rows_total

def to_dur(grids, px_w, rows, framerate=8.0):
    cell_w = px_w * 2                      # 2 cells per square pixel
    frames = []
    for n, g in enumerate(grids, 1):
        contents = []
        for y in range(rows):
            contents.append("".join(
                (g[y][cx // 2] or (" ", GOLD_FG, VOID_BG))[0] for cx in range(cell_w)))
        # colourMap is [x][y] -> [fg, bg]
        cmap = []
        for cx in range(cell_w):
            col = []
            for y in range(rows):
                c = g[y][cx // 2]
                col.append([GOLD_FG, VOID_BG] if c is None else [c[1], c[2]])
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
    with gzip.open(out, "wb", compresslevel=9) as fh:
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
    """Approximate preview. ly's palette is its own, so these RGBs are only
    close: the field reads as red and the emblem as yellow on the console."""
    RED_RGB, GOLD_RGB, VOID_RGB = (196, 0, 0), (255, 255, 85), (20, 20, 20)
    W, H = px_w * 2 * cw, rows * ch
    hdr = f"P6\n{W} {H}\n255\n".encode()
    rowbytes = []
    for y in range(rows):
        line = bytearray()
        for cx in range(px_w * 2):
            c = grid[y][cx // 2]
            if c is None:
                rgb = VOID_RGB
            elif c[0] != " ":
                rgb = GOLD_RGB
            else:
                rgb = RED_RGB
            line += bytes(rgb) * cw
        rowbytes.append(bytes(line) * ch)
    open(path, "wb").write(hdr + b"".join(rowbytes))
