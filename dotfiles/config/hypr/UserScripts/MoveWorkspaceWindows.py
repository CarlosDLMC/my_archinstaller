#!/usr/bin/env python3
"""Move every window of one workspace into another, keeping the dwindle layout.

mango's IPC cannot read or write the dwindle tree, so the layout is recovered
from the window rectangles (they always form a guillotine/BSP partition) and
replayed in the target workspace: each window is moved next to the window it
was split from, with that window's split direction set first (mango's manual
split mode, its form of Hyprland's preselect), and the split ratios are then
restored by resizing.

Animations off and manual split on go into one runtime file applied with
`setoption,source`; one config reload at the end puts both back.

Usage: MoveWorkspaceWindows.py <target> [source] [--follow] [--simple]
  target/source  workspace number; source defaults to the shown workspace
  --follow       stay on the target workspace afterwards
  --simple       plain move, no layout reconstruction
"""

import json
import os
import subprocess
import sys
import time

SETTLE = 0.04          # seconds to let a dispatch land
EDGE_SLOP = 6          # px tolerance when recovering the split tree
RATIO_PASSES = 3       # resize sweeps used to restore split ratios


def mmsg(*args):
    # Timed out: the move turns animations off and manual split on, and a
    # reload in a finally puts them back. An mmsg that never returns would hang
    # before that finally is reached.
    try:
        out = subprocess.run(("mmsg", *args), capture_output=True,
                             text=True, timeout=5).stdout
    except Exception:
        return {}
    try:
        return json.loads(out or "{}")
    except json.JSONDecodeError:
        return {}


def dispatch(cmd, client=None):
    if client is None:
        mmsg("dispatch", cmd)
    else:
        mmsg("dispatch", cmd, f"client,{client}")
    time.sleep(SETTLE)


def clients():
    return mmsg("get", "all-clients").get("clients", [])


def focused_monitor():
    return next((m for m in mmsg("get", "all-monitors").get("monitors", [])
                 if m.get("active")), None)


def box(c):
    return (c["x"], c["y"], c["width"], c["height"])


# ---------------------------------------------------------------- BSP recovery

class Leaf:
    def __init__(self, win):
        self.win = win
        self.box = box(win)

    def rep(self):
        return self.win

    def leaves(self):
        return [self]


class Split:
    def __init__(self, axis, first, second):
        self.axis = axis          # 0 = side by side, 1 = stacked
        self.first = first
        self.second = second

    def rep(self):
        return self.first.rep()

    def leaves(self):
        return self.first.leaves() + self.second.leaves()


def cut(boxes, axis):
    """Find a straight cut splitting boxes into two non-empty groups."""
    lo, hi = axis, axis + 2
    for b in boxes:
        edge = b[lo] + b[hi]
        near = [o for o in boxes if o[lo] < edge - EDGE_SLOP]
        far = [o for o in boxes if o[lo] >= edge - EDGE_SLOP]
        if not near or not far:
            continue
        if all(o[lo] + o[hi] <= edge + EDGE_SLOP for o in near):
            return near, far
    return None


def build(wins):
    if len(wins) == 1:
        return Leaf(wins[0])
    by_box = {id(w): box(w) for w in wins}
    boxes = [by_box[id(w)] for w in wins]
    for axis in (0, 1):
        parts = cut(boxes, axis)
        if parts:
            near, far = parts
            pick = lambda group: [w for w in wins if by_box[id(w)] in group]
            return Split(axis, build(pick(near)), build(pick(far)))
    return None            # not a clean partition -> caller falls back


def plan(node, ops):
    """Pre-order insertion plan: (anchor, split direction, new window)."""
    if isinstance(node, Leaf):
        return
    ops.append((node.first.rep(), "horizontal" if node.axis == 0 else "vertical",
                node.second.rep()))
    plan(node.first, ops)
    plan(node.second, ops)


# ------------------------------------------------------------------- geometry

def bbox(boxes):
    x0 = min(b[0] for b in boxes)
    y0 = min(b[1] for b in boxes)
    x1 = max(b[0] + b[2] for b in boxes)
    y1 = max(b[1] + b[3] for b in boxes)
    return x0, y0, max(1, x1 - x0), max(1, y1 - y0)


def make_scaler(src_area, dst_area):
    sx0, sy0, sw, sh = src_area
    dx0, dy0, dw, dh = dst_area
    fx, fy = dw / sw, dh / sh

    def scale(b):
        x, y, w, h = b
        return (round(dx0 + (x - sx0) * fx), round(dy0 + (y - sy0) * fy),
                max(1, round(w * fx)), max(1, round(h * fy)))
    return scale


def focus_colour():
    """The focused border colour, for the split marker manual split draws."""
    path = os.path.expanduser("~/.config/mango/wallust/colors.conf")
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                if line.startswith("focus_color="):
                    return line.split("=", 1)[1].strip()
    except OSError:
        pass
    return "0x067263ff"


# ----------------------------------------------------------------------- move

def simple_move(ids, target):
    for i in ids:
        dispatch(f"tagsilent,{target}", i)


def main():
    target = source = None
    follow = simple = False
    for arg in sys.argv[1:]:
        if arg == "--follow":
            follow = True
        elif arg == "--simple":
            simple = True
        elif target is None:
            target = int(arg)
        else:
            source = int(arg)
    if target is None:
        sys.exit(__doc__)

    mon = focused_monitor()
    if not mon:
        return
    shown_before = (mon.get("active_tags") or [0])[0]
    if source is None:
        source = shown_before
    if not source or source == target:
        return

    # A group's hidden tabs travel with its shown one (mango keeps their old
    # workspace on them in the list), so only the shown tab is moved.
    mine = [c for c in clients() if c["monitor"] == mon["name"]
            and source in c.get("tags", []) and not c["is_global"]
            and not c["is_minimized"]
            and not (c["is_group"] and not c["is_group_focus"])]
    if not mine:
        return
    ids = [c["id"] for c in mine]
    grouped = any(c["is_group"] for c in mine)
    focus_before = next((c["id"] for c in clients() if c["is_focused"]), None)

    def finish():
        if follow:
            dispatch(f"view,{target},0")
            if focus_before in ids:
                dispatch("focusid", focus_before)
        else:
            if shown_before:
                dispatch(f"view,{shown_before},0")
            if focus_before and focus_before not in ids:
                dispatch("focusid", focus_before)

    # A fullscreen window hides its own tile, so drop the state first, read the
    # real layout, and put the state back at the end.
    fulls = [c["id"] for c in mine if c["is_fullscreen"]]
    if fulls and not simple and not grouped:
        for i in fulls:
            dispatch("togglefullscreen", i)
        mine = [c for c in clients() if c["id"] in ids]

    tiled = [c for c in mine if not c["is_floating"]]
    tree = build(tiled) if (tiled and not simple and not grouped) else None
    if tree is None:
        simple_move(ids, target)
        for i in fulls:
            dispatch("togglefullscreen", i)
        finish()
        return

    ops = []
    plan(tree, ops)
    floats = [c for c in mine if c["is_floating"]]
    src_area = bbox([box(c) for c in tiled])

    run_dir = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    override = os.path.join(run_dir, "mango-moveworkspace.conf")
    with open(override, "w", encoding="utf-8") as f:
        f.write("animations=0\nlayer_animations=0\ndwindle_manual_split=1\n"
                f"split_color={focus_colour()}\n")
    try:
        mmsg("dispatch", f"setoption,source,{override}")
        time.sleep(SETTLE)
        dispatch(f"view,{target},0")

        root = tree.rep()
        dispatch(f"tagsilent,{target}", root["id"])
        for anchor, direction, new in ops:
            dispatch("focusid", anchor["id"])
            dispatch(f"dwindle_split_{direction}", anchor["id"])
            dispatch(f"tagsilent,{target}", new["id"])

        placed = {c["id"]: box(c) for c in clients()}
        tile_scale = make_scaler(
            src_area, bbox([placed[leaf.win["id"]] for leaf in tree.leaves()]))
        for leaf in tree.leaves():
            leaf.target = tile_scale(leaf.box)
        order = sorted(tree.leaves(), key=lambda l: -l.target[2] * l.target[3])
        for _ in range(RATIO_PASSES):
            now = {c["id"]: box(c) for c in clients()}
            for leaf in order:
                cur = now.get(leaf.win["id"])
                if not cur:
                    continue
                dw, dh = leaf.target[2] - cur[2], leaf.target[3] - cur[3]
                if dw or dh:
                    dispatch(f"resizewin,{dw:+d},{dh:+d}", leaf.win["id"])

        for c in floats:
            dispatch(f"tagsilent,{target}", c["id"])
            dispatch(f"resizewin,{c['width']},{c['height']}", c["id"])
            dispatch(f"movewin,{c['x']},{c['y']}", c["id"])
        for i in fulls:
            dispatch("togglefullscreen", i)
        finish()
    finally:
        try:
            os.remove(override)
        except OSError:
            pass
        mmsg("dispatch", "reload_config")


if __name__ == "__main__":
    main()
