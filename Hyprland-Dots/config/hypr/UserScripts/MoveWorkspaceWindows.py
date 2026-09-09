#!/usr/bin/env python3
"""Move every window of one workspace into another, keeping the dwindle layout.

Hyprland's IPC cannot read or write the dwindle tree, so the layout is
recovered from the window rectangles (they always form a guillotine/BSP
partition), replayed in the target workspace with `layoutmsg preselect`, and
the split ratios are restored with `resizewindowpixel exact`.

Usage: MoveWorkspaceWindows.py <target> [source] [--follow] [--simple]
  target/source  workspace id or name; source defaults to the active workspace
  --follow       stay on the target workspace afterwards
  --simple       plain batch move, no layout reconstruction
"""

import json
import subprocess
import sys
import time

SETTLE = 0.04          # seconds to let a dispatch land
EDGE_SLOP = 6          # px tolerance when recovering the split tree
RATIO_PASSES = 3       # resize sweeps used to restore split ratios


def hypr(*args):
    return subprocess.run(("hyprctl", *args), capture_output=True, text=True).stdout


def query(what):
    return json.loads(hypr("-j", what))


def dispatch(*cmds):
    hypr("--batch", "; ".join("dispatch " + c for c in cmds))


def getopt_int(name):
    return json.loads(hypr("-j", "getoption", name))["int"]


def setopt(name, value):
    hypr("keyword", name, str(value))


# ---------------------------------------------------------------- BSP recovery

class Leaf:
    def __init__(self, win):
        self.win = win
        self.box = win["box"]

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
    by_box = {id(w): w["box"] for w in wins}
    boxes = [by_box[id(w)] for w in wins]
    for axis in (0, 1):
        parts = cut(boxes, axis)
        if parts:
            near, far = parts
            pick = lambda group: [w for w in wins if by_box[id(w)] in group]
            return Split(axis, build(pick(near)), build(pick(far)))
    return None            # not a clean partition -> caller falls back


def plan(node, ops):
    """Pre-order insertion plan: (anchor, preselect direction, new window)."""
    if isinstance(node, Leaf):
        return
    ops.append((node.first.rep(), "r" if node.axis == 0 else "d",
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

    def scale(box):
        x, y, w, h = box
        return (round(dx0 + (x - sx0) * fx), round(dy0 + (y - sy0) * fy),
                max(1, round(w * fx)), max(1, round(h * fy)))
    return scale


# ----------------------------------------------------------------------- move

def simple_move(addrs, target):
    hypr("--batch", "; ".join(
        f"dispatch movetoworkspacesilent {target},address:{a}" for a in addrs))


def main():
    target = source = None
    follow = simple = False
    for arg in sys.argv[1:]:
        if arg == "--follow":
            follow = True
        elif arg == "--simple":
            simple = True
        elif target is None:
            target = arg
        else:
            source = arg
    if target is None:
        sys.exit(__doc__)

    clients = query("clients")
    if source is None:
        source = query("activeworkspace")["name"]
    if source == target:
        return

    mine = [c for c in clients if c["workspace"]["name"] == source
            and not c["pinned"]]
    if not mine:
        return

    addrs = [c["address"] for c in mine]
    grouped = any(c["grouped"] for c in mine)

    # A fullscreen window hides its own tile, so drop the state first, read the
    # real layout, and put the state back at the end.
    fulls = [(c["address"], c["fullscreen"], c["fullscreenClient"])
             for c in mine if c["fullscreen"]]
    if fulls and not simple and not grouped:
        for address, _, _ in fulls:
            dispatch(f"focuswindow address:{address}", "fullscreenstate 0 0")
            time.sleep(SETTLE)
        clients = query("clients")
        mine = [c for c in clients if c["address"] in addrs]

    tiled = [c for c in mine if not c["floating"]]

    if simple or grouped or not tiled:
        simple_move(addrs, target)
        if follow:
            dispatch(f"workspace {target}")
        return

    for c in tiled:
        c["box"] = tuple(c["at"]) + tuple(c["size"])
    tree = build(tiled)
    if tree is None:                      # unexpected geometry, stay safe
        simple_move(addrs, target)
        if follow:
            dispatch(f"workspace {target}")
        return

    monitors = {m["id"]: m for m in query("monitors")}
    workspaces = {w["name"]: w for w in query("workspaces")}
    src_mon = monitors[mine[0]["monitor"]]
    dst_name = workspaces.get(target, {}).get("monitor", src_mon["name"])
    dst_mon = next(m for m in monitors.values() if m["name"] == dst_name)
    src_area = bbox([c["box"] for c in tiled])
    mon_scale = make_scaler(
        (src_mon["x"], src_mon["y"], src_mon["width"], src_mon["height"]),
        (dst_mon["x"], dst_mon["y"], dst_mon["width"], dst_mon["height"]))

    ops = []
    plan(tree, ops)
    floats = [c for c in mine if c["floating"]]

    anim = getopt_int("animations:enabled")
    split = getopt_int("dwindle:force_split")
    focus_before = query("activewindow").get("address")
    ws_before = {m["name"]: m["activeWorkspace"]["name"]
                 for m in monitors.values()}
    mon_before = next(m["name"] for m in monitors.values() if m["focused"])

    setopt("animations:enabled", 0)
    setopt("dwindle:force_split", 2)
    try:
        dispatch(f"focusmonitor {dst_mon['name']}", f"workspace {target}")
        time.sleep(SETTLE)

        root = tree.rep()
        dispatch(f"movetoworkspace {target},address:{root['address']}")
        time.sleep(SETTLE)
        for anchor, direction, new in ops:
            dispatch(f"focuswindow address:{anchor['address']}",
                     f"layoutmsg preselect {direction}",
                     f"movetoworkspace {target},address:{new['address']}")
            time.sleep(SETTLE)

        placed = {c["address"]: tuple(c["at"]) + tuple(c["size"])
                  for c in query("clients")}
        tile_scale = make_scaler(
            src_area,
            bbox([placed[l.win["address"]] for l in tree.leaves()]))
        for leaf in tree.leaves():
            leaf.target = tile_scale(leaf.box)
        sweep = ["resizewindowpixel "
                 f"exact {l.target[2]} {l.target[3]},address:{l.win['address']}"
                 for l in sorted(tree.leaves(),
                                 key=lambda l: -l.target[2] * l.target[3])]
        for _ in range(RATIO_PASSES):
            dispatch(*sweep)
            time.sleep(SETTLE)

        drift = []
        for c in floats:
            x, y, w, h = mon_scale(tuple(c["at"]) + tuple(c["size"]))
            drift += [f"movetoworkspace {target},address:{c['address']}",
                      f"resizewindowpixel exact {w} {h},address:{c['address']}",
                      f"movewindowpixel exact {x} {y},address:{c['address']}"]
        if drift:
            dispatch(*drift)
        for address, mode, client_mode in fulls:
            dispatch(f"focuswindow address:{address}",
                     f"fullscreenstate {mode} {client_mode}")
            time.sleep(SETTLE)

        if follow:
            if focus_before in addrs:
                dispatch(f"focuswindow address:{focus_before}")
        else:
            dispatch(f"workspace {ws_before[dst_mon['name']]}",
                     f"focusmonitor {mon_before}")
            time.sleep(SETTLE)
            if focus_before and focus_before not in addrs:
                dispatch(f"focuswindow address:{focus_before}")
    finally:
        setopt("dwindle:force_split", split)
        setopt("animations:enabled", anim)


if __name__ == "__main__":
    main()
