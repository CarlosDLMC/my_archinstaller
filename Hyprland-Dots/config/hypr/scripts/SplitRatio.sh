#!/usr/bin/env bash
# SUPER+M: split ratio 0.3 for the focused window's split, on either layout.
#
# The ratio is Hyprland's: 1.0 is an even split and the first (left or top)
# side gets ratio/2 of the space, so 0.3 gives it 15%. On the master layout it
# is the master's width instead (30%).
#
# mango has no "set this split's ratio" for dwindle - its split ratio option
# only shapes new splits - so the split is found from the window geometry and
# the window resized by the difference. The split tree is rebuilt from the
# tiles: the cut nearest the middle of a box is taken as the one made first.

layout=$(mmsg get all-monitors | jq -r '.monitors[] | select(.active) | .layout_symbol')
case "$layout" in
T | RT | VT | CT)
    # setmfact with a value of 1 or more sets it absolutely: 1.3 -> 0.3.
    exec mmsg dispatch setmfact,1.3 >/dev/null
    ;;
esac

exec python3 - <<'PY'
import json
import subprocess


def mmsg(*args):
    out = subprocess.run(["mmsg", *args], capture_output=True, text=True).stdout
    return json.loads(out or "{}")


me = mmsg("get", "focusing-client")
if not me.get("id") or me.get("is_floating") or me.get("is_fullscreen"):
    raise SystemExit(0)
tiles = [
    c for c in mmsg("get", "all-clients").get("clients", [])
    if c["monitor"] == me["monitor"] and c["is_visible"]
    and not c["is_floating"] and not c["is_fullscreen"]
]


def box(rs):
    x0 = min(r["x"] for r in rs)
    y0 = min(r["y"] for r in rs)
    x1 = max(r["x"] + r["width"] for r in rs)
    y1 = max(r["y"] + r["height"] for r in rs)
    return x0, y0, x1, y1


def split(rs):
    """(axis, first, second) of the cut nearest the middle, or None."""
    x0, y0, x1, y1 = box(rs)
    best = None
    for axis, lo, hi, start, size in (("x", x0, x1, "x", "width"), ("y", y0, y1, "y", "height")):
        for cut in sorted({r[start] + r[size] for r in rs}):
            first = [r for r in rs if r[start] + r[size] <= cut]
            second = [r for r in rs if r[start] >= cut]
            if first and second and len(first) + len(second) == len(rs):
                off = abs(cut - (lo + hi) / 2)
                if best is None or off < best[0]:
                    best = (off, axis, first, second)
    return best[1:] if best else None


def parent_of(rs, target):
    """The split whose one side is the target window alone."""
    s = split(rs)
    if not s:
        return None
    axis, first, second = s
    for side in (first, second):
        if len(side) == 1 and side[0]["id"] == target:
            return axis, first, second
    for side in (first, second):
        if any(r["id"] == target for r in side):
            return parent_of(side, target)
    return None


p = parent_of(tiles, me["id"])
if not p:
    raise SystemExit(0)
axis, first, second = p
x0, y0, x1, y1 = box(first + second)
size = "width" if axis == "x" else "height"
whole = (x1 - x0) if axis == "x" else (y1 - y0)
want_first = whole * 0.3 / 2
if first[0]["id"] == me["id"] and len(first) == 1:
    delta = want_first - me[size]
else:
    delta = (whole - want_first) - me[size]
delta = int(round(delta))
if delta:
    dx, dy = (delta, 0) if axis == "x" else (0, delta)
    subprocess.run(["mmsg", "dispatch", f"resizewin,{dx:+d},{dy:+d}"], capture_output=True)
PY
