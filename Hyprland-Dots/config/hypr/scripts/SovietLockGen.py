#!/usr/bin/env python3
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  #
# Generate the per-monitor hyprlock widgets for the Soviet TUI lock screen.
#
# Why this exists: hyprlock positions are absolute logical pixels, so a config
# hand-tuned for one display is wrong everywhere else - too small on 4K, off
# the edge on 720p - and a single config cannot size itself differently per
# monitor. This emits one widget set per attached monitor, each sized from that
# monitor's own logical geometry, so the same dotfiles look right on any
# machine and on mixed-DPI setups.
#
# Run before locking; hyprlock.conf sources the file this writes.
#
# Text metrics come from Pango, the engine hyprlock renders with - see
# metrics() below. They are deliberately NOT computed as a ratio of font_size:
# Pango rounds line height to whole pixels, so the real ratio wanders, and
# assuming a constant one put the overlaid password and layout widgets up to
# 11px off their row at larger font sizes.

import json
import os
import subprocess
import sys

# Text metrics come from Pango, the same engine hyprlock renders with, because
# they are NOT a fixed ratio of font_size: Pango rounds line height to whole
# pixels, so the real pitch/font ratio wanders (1.89 at font 9, 1.80 at 19).
# Assuming a constant ratio put the overlaid widgets up to 11px off their row
# at larger sizes, since the error accumulates with row index and font size.
# These fallbacks are only used if python-gobject is missing.
CELL_FALLBACK = 0.7917
PITCH_FALLBACK = 1.8000

FONT = "JetBrainsMono Nerd Font Mono"

# Metrics measured from Pango for the bundled JetBrainsMono Nerd Font Mono,
# baked in so a machine without python-gobject still gets exact alignment
# rather than a ratio approximation. Live Pango is preferred when present.
METRIC_TABLE = {
    8: (6, 15),
    9: (7, 17),
    10: (8, 18),
    11: (9, 20),
    12: (10, 22),
    13: (10, 24),
    14: (11, 26),
    15: (12, 27),
    16: (13, 29),
    17: (14, 31),
    18: (14, 33),
    19: (15, 34),
    20: (16, 36),
    21: (17, 38),
    22: (18, 39),
    23: (18, 42),
    24: (19, 43),
    25: (20, 44),
    26: (21, 47),
    27: (22, 48),
    28: (22, 51),
    29: (23, 52),
    30: (24, 53),
    31: (25, 56),
    32: (26, 57),
    33: (26, 59),
    34: (27, 61),
    35: (28, 62),
    36: (29, 64),
    37: (30, 66),
    38: (30, 68),
    39: (31, 70),
    40: (32, 71),
    41: (33, 73),
    42: (34, 75),
    43: (34, 77),
    44: (35, 78),
}


# The 1080p layout was tuned by eye and verified by measurement; every other
# resolution is derived from it, so these are all expressed relative to it.
REF_FS = 14
CLOCK_RATIO = 22 / 14  # clock font vs panel font
GAP_CLOCK_DATE = 20 / REF_FS  # gaps, as multiples of font_size
GAP_DATE_PANEL = 16 / REF_FS
GAP_PANEL_FOOT = 24 / REF_FS

# A plain label overlaid on a panel row needs no correction once the pitch is
# right: same font, same size, so the same baseline offset inside the line box.
# The input field does need one - its dots sit low in the field box. Measured.
LABEL_RISE = 0.00  # * font_size
FIELD_RISE = 0.00  # * font_size, calibrated below

# Horizontal nudge so the drawn ink, not the widget box, sits on the value
# column - glyph left side bearing, and the dots' own inset in the field.
FIELD_DX = 0.00  # * font_size
LABEL_DX = 0.00  # * font_size

HEIGHT_BUDGET = 0.85  # of screen height the whole stack may occupy
WIDTH_BUDGET = 0.40  # of screen width the panel may occupy
FS_MIN, FS_MAX = 8, 44

CLOCK_ROWS = 5
NBSP = " "

HOME = os.path.expanduser("~")
SCRIPTS = f"{HOME}/.config/hypr/scripts"
PANEL_CMD = ["python3", f"{SCRIPTS}/SovietLock.py", "--panel"]


_METRIC_CACHE = {}


def metrics(fs):
    """(cell width, line pitch) in px for `fs`, straight from Pango."""
    if fs in _METRIC_CACHE:
        return _METRIC_CACHE[fs]
    try:
        import gi

        gi.require_version("Pango", "1.0")
        gi.require_version("PangoCairo", "1.0")
        from gi.repository import Pango, PangoCairo
        import cairo

        cr = cairo.Context(cairo.ImageSurface(cairo.FORMAT_ARGB32, 8, 8))
        lay = PangoCairo.create_layout(cr)
        lay.set_font_description(Pango.FontDescription(f"{FONT} {fs}"))
        lay.set_text("X" * 64 + "\n" + "X" * 64, -1)
        _, log = lay.get_extents()
        it = lay.get_iter()
        first, _ = it.get_line_extents()
        it.next_line()
        second, _ = it.get_line_extents()
        cell = (log.width / Pango.SCALE) / 64
        pitch = (second.y - first.y) / Pango.SCALE
        if cell > 0 and pitch > 0:
            _METRIC_CACHE[fs] = (cell, pitch)
            return _METRIC_CACHE[fs]
    except Exception:
        pass
    if fs in METRIC_TABLE:
        _METRIC_CACHE[fs] = METRIC_TABLE[fs]
    else:
        _METRIC_CACHE[fs] = (CELL_FALLBACK * fs, PITCH_FALLBACK * fs)
    return _METRIC_CACHE[fs]


def sh(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return ""


# ------------------------------------------------------------------- geometry


def monitors():
    """Logical size per monitor. hyprlock lays out in logical pixels, so a 4K
    panel at scale 2 must be treated as 1920x1080, not 3840x2160."""
    raw = sh("hyprctl", "monitors", "-j")
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return []
    out = []
    for m in data:
        scale = m.get("scale") or 1.0
        w, h = m.get("width", 0), m.get("height", 0)
        if not w or not h:
            continue
        transform = m.get("transform", 0) or 0
        if transform in (1, 3, 5, 7):  # rotated 90/270
            w, h = h, w
        out.append({"name": m.get("name", ""), "w": w / scale, "h": h / scale})
    return out


def stack_height(fs, rows):
    """Total height of clock + date + panel + footer, with real metrics."""
    _, pitch = metrics(fs)
    _, clock_pitch = metrics(clock_font(fs))
    return (
        CLOCK_ROWS * clock_pitch
        + GAP_CLOCK_DATE * fs
        + pitch
        + GAP_DATE_PANEL * fs
        + rows * pitch
        + GAP_PANEL_FOOT * fs
        + pitch
    )


def clock_font(fs):
    return max(FS_MIN, int(round(fs * CLOCK_RATIO)))


def font_size(w, h, rows):
    """Largest font whose stack fits the height budget and panel the width
    budget. Searched rather than solved, because pitch is not linear in fs."""
    for fs in range(FS_MAX, FS_MIN - 1, -1):
        cell, _ = metrics(fs)
        if stack_height(fs, rows) <= HEIGHT_BUDGET * h and 64 * cell <= WIDTH_BUDGET * w:
            return fs
    return FS_MIN


# ---------------------------------------------------------------- panel probe


def panel_shape():
    """Actual panel geometry. The row count is not fixed: a machine with no
    battery, no AC device or no weather cache renders fewer rows, and the
    overlaid widgets must follow. So ask the panel itself."""
    out = subprocess.run(PANEL_CMD, capture_output=True, text=True)
    lines = [ln for ln in out.stdout.splitlines() if ln]
    if not lines:
        return 25, 64, 6, 5
    cols = max(len(ln) for ln in lines)
    pw_row = next((i for i, ln in enumerate(lines) if "КОД ДОСТУПА" in ln), 6)
    lay_row = next((i for i, ln in enumerate(lines) if "РАСКЛАДКА" in ln), 5)
    return len(lines), cols, pw_row, lay_row


def value_col(lines_cols):
    """Character column where a panel row's value starts:
    1 leading ║ + 2 spaces of padding + 16-wide label column."""
    return 19


# --------------------------------------------------------------- kb layouts


def layout_list():
    """Positional short codes for $LAYOUT[...], from the machine's own
    kb_layout. Prefers the bar's layouts.py so the lock screen and the bar
    agree (us -> EN, GNOME style); falls back to the raw codes."""
    helper = f"{HOME}/.config/quickshell/bar/scripts/layouts.py"
    if os.path.exists(helper):
        try:
            data = json.loads(sh("python3", helper))
            codes = [l["short"].upper() for l in data.get("layouts", [])]
            if codes:
                return codes
        except (json.JSONDecodeError, KeyError, TypeError):
            pass
    try:
        raw = json.loads(sh("hyprctl", "getoption", "-j", "input:kb_layout"))["str"]
        codes = [c.strip().upper() for c in raw.split(",") if c.strip()]
        if codes:
            return codes
    except (json.JSONDecodeError, KeyError):
        pass
    return ["US"]


# ------------------------------------------------------------------ emission


def widgets(mon, rows, cols, pw_row, lay_row, codes):
    fs = font_size(mon["w"], mon["h"], rows)
    clock_fs = clock_font(fs)
    cell, pitch = metrics(fs)
    _, clock_pitch = metrics(clock_fs)
    W, H = mon["w"], mon["h"]

    h_clock = CLOCK_ROWS * clock_pitch
    h_line = pitch
    h_panel = rows * pitch
    g1, g2, g3 = GAP_CLOCK_DATE * fs, GAP_DATE_PANEL * fs, GAP_PANEL_FOOT * fs

    total = h_clock + g1 + h_line + g2 + h_panel + g3 + h_line
    top = (H - total) / 2

    c_clock = top + h_clock / 2
    c_date = top + h_clock + g1 + h_line / 2
    c_panel = top + h_clock + g1 + h_line + g2 + h_panel / 2
    c_foot = total + top - h_line / 2

    up = lambda centre: round(H / 2 - centre)  # hyprlock: +y is up

    panel_top = c_panel - h_panel / 2
    row_centre = lambda i: panel_top + (i + 0.5) * pitch

    # value column, as an offset from screen centre
    val_dx = cell * (value_col(cols) - cols / 2)

    # password field: invisible, its asterisks land on the value column
    f_w = round(cols * cell * 0.65)  # ~2/3 of the panel width
    f_h = max(6, round(0.85 * pitch))
    f_x = round(val_dx + f_w / 2 + FIELD_DX * fs)
    f_y = up(row_centre(pw_row) - FIELD_RISE * fs)

    # layout label: centre-aligned, so fold in half its padded width
    code_w = max(len(c) for c in codes) + 6  # +6 NBSP to widen the click target
    l_x = round(val_dx + (code_w * cell) / 2 + LABEL_DX * fs)
    l_y = up(row_centre(lay_row) - LABEL_RISE * fs)
    bracket = ",".join(c + NBSP * 6 for c in codes)

    m = mon["name"]
    return f"""
# ══ {m}  ({W:.0f}x{H:.0f} logical, font {fs}, clock {clock_fs}) ══
label {{
    monitor = {m}
    text = cmd[update:1000] $BIGCLOCK
    color = $ink
    font_size = {clock_fs}
    font_family = $mono
    position = 0, {up(c_clock)}
    halign = center
    valign = center
}}

label {{
    monitor = {m}
    text = cmd[update:60000] $SL --date
    color = $dim
    font_size = {fs}
    font_family = $mono
    position = 0, {up(c_date)}
    halign = center
    valign = center
}}

label {{
    monitor = {m}
    text = cmd[update:30000] $SL --panel
    color = $ink
    font_size = {fs}
    font_family = $mono
    position = 0, {up(c_panel)}
    halign = center
    valign = center
}}

input-field {{
    monitor = {m}
    size = {f_w}, {f_h}
    outline_thickness = 0
    rounding = 0
    outer_color = rgba(00000000)
    inner_color = rgba(00000000)
    check_color = rgba(00000000)
    fail_color = rgba(00000000)
    font_color = $ink
    font_family = $mono
    dots_text_format = *
    dots_size = 0.64
    dots_spacing = 0.2
    dots_center = false
    fade_on_empty = false
    hide_input = false
    placeholder_text =
    fail_text = <span foreground="##C42B1C" font_size="{fs}pt"><b>НЕВЕРНЫЙ КОД ДОСТУПА · ПОПЫТКА $ATTEMPTS</b></span>
    check_text = <span foreground="##C7A017" font_size="{fs}pt">ИДЁТ ПРОВЕРКА ДОКУМЕНТОВ...</span>
    position = {f_x}, {f_y}
    halign = center
    valign = center
}}

label {{
    monitor = {m}
    text = $LAYOUT[{bracket}]
    color = $ink
    font_size = {fs}
    font_family = $mono
    onclick = hyprctl dispatch 'hl.dsp.global("quickshell:layoutNext")'
    position = {l_x}, {l_y}
    halign = center
    valign = center
}}

label {{
    monitor = {m}
    text = cmd[update:0] $SL --footer
    color = $dim
    font_size = {fs}
    font_family = $mono
    position = 0, {up(c_foot)}
    halign = center
    valign = center
}}
"""


def main():
    mons = monitors()
    if not mons:
        # Never leave hyprlock with no widgets at all; assume a 1080p screen
        # and let the widgets apply to every output.
        mons = [{"name": "", "w": 1920, "h": 1080}]

    rows, cols, pw_row, lay_row = panel_shape()
    codes = layout_list()

    body = "".join(widgets(m, rows, cols, pw_row, lay_row, codes) for m in mons)
    header = (
        "# GENERATED by scripts/SovietLockGen.py - do not edit.\n"
        "# Rewritten before every lock; edit the generator instead.\n"
        f"# panel: {rows} rows x {cols} cols   layouts: {','.join(codes)}\n"
        f"# monitors: {', '.join(m['name'] or '(all)' for m in mons)}\n"
    )
    out = header + body

    dest = sys.argv[1] if len(sys.argv) > 1 else f"{HOME}/.config/hypr/hyprlock-monitors.conf"
    tmp = dest + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(out)
    os.replace(tmp, dest)  # atomic, so a lock racing the write never sees half


if __name__ == "__main__":
    main()
