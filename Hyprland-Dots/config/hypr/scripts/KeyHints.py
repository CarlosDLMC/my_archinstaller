#!/usr/bin/env python3
"""Keybind cheat sheet with a search box (SUPER H).

The list is generated LIVE from `hyprctl binds`, i.e. the keybinds Hyprland
has loaded right now, so it never drifts out of date: add a bind with a
description in the Lua config and it shows up here after the next reload.

Usage:
    KeyHints.py          open the GTK window (type to filter, Esc closes)
    KeyHints.py --dump   print "KEYS<TAB>ACTION" lines (used by KeyBinds.sh)
"""

import json
import os
import re
import subprocess
import sys

# Hyprland modmask bits (X11 modifier order): SHIFT=1 CTRL=4 ALT=8 SUPER=64.
MOD_BITS = ((64, "SUPER"), (4, "CTRL"), (8, "ALT"), (1, "SHIFT"))

# Friendlier names for the keysyms Hyprland reports. Anything not listed is
# shown as-is (F6, Print, XF86AudioPlay, ...).
KEY_NAMES = {
    "mouse:272": "left click (drag)",
    "mouse:273": "right click (drag)",
    "mouse_up": "scroll up",
    "mouse_down": "scroll down",
    "bracketleft": "[",
    "bracketright": "]",
    "period": ".",
    "comma": ",",
    "space": "Space",
    "Return": "Enter",
    "Delete": "Del",
    "Print": "PrtSc",
    "left": "Left",
    "right": "Right",
    "up": "Up",
    "down": "Down",
    "SHIFT_L": "Left Shift",
    "ALT_L": "Left Alt",
}


def key_name(b):
    """Keysym or keycode of a bind, as text. The digit row is bound by keycode
    in some setups (10..19 = 1..9,0); anything else by keycode stays raw."""
    code = b.get("keycode", 0)
    if code > 0:
        if 10 <= code <= 18:
            return str(code - 9)
        if code == 19:
            return "0"
        return f"code:{code}"
    return b.get("key", "")


def mods(b):
    mask = b.get("modmask", 0)
    return [name for bit, name in MOD_BITS if mask & bit]


def action(b):
    if b.get("has_description") and b.get("description"):
        return b["description"]
    if b.get("dispatcher") == "__lua":
        return "(no description)"
    return f'{b.get("dispatcher", "")} {b.get("arg", "")}'.strip()


def natural(s):
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", s)]


def load_binds():
    out = subprocess.run(["hyprctl", "-j", "binds"], check=True,
                         capture_output=True, text=True).stdout
    rows, seen = [], set()
    for b in json.loads(out):
        if b.get("submap"):
            continue
        raw = key_name(b)
        m = mods(b)
        keys = " + ".join(m + [KEY_NAMES.get(raw, raw)])
        act = action(b)
        if (keys, act) in seen:
            continue
        seen.add((keys, act))
        mask = b.get("modmask", 0)
        # SUPER binds first, then grouped by modifier combo, then by key.
        sort_key = (0 if mask & 64 else 1, mask, natural("10" if raw == "0" else raw))
        rows.append((sort_key, keys, act, raw))
    rows.sort(key=lambda r: r[0])
    return [(keys, act, raw) for _, keys, act, raw in rows]


def dump(rows):
    for keys, act, _ in rows:
        print(f"{keys}\t{act}")


# The launcher's look (SUPER + D, rofi/themes/soviet-tui.rasi) in wallust's
# rofi colours, so the cheat sheet follows the wallpaper exactly as rofi does,
# Light mode included. The literals are the sovietpunk fallbacks, for when the
# file is missing. Hyprland draws the frame: it is the focused-window border.
ROFI_COLORS = os.path.expanduser("~/.config/rofi/wallust/colors-rofi.rasi")
PALETTE = {
    "normal-background": "#262625",   # the window
    "foreground": "#E8C4C0",          # text
    "color0": "#4C4C4B",              # dividers
    "color8": "#96716D",              # column headers, the status line
    "color12": "#59302D",             # scrollbar
    "color14": "#BE564A",             # the stamp and the caret
    "on-color14": "rgba(0,0,0,0.7)",  # text on the stamp, as RofiContrast.py picks it
}

CSS = """
#cheatsheet, #cheatsheet treeview.view {
    background-color: %(normal-background)s; color: %(foreground)s; }
#cheatsheet * { border-radius: 0; }
#cheatsheet .stamp {
    background-color: %(color14)s; color: %(on-color14)s; padding: 0 8px;
    font-family: "Terminess Nerd Font"; font-weight: bold; font-size: 18pt; }
#cheatsheet entry {
    background: none; border: none; box-shadow: none; outline: none;
    color: %(foreground)s; caret-color: %(color14)s;
    -GtkWidget-cursor-aspect-ratio: 0.08; }
/* A thin caret, not the launcher's block: GTK centres a wide caret on the
   insertion point, so a block would sit on top of the last letter typed. */
#cheatsheet .list { border-top: 1px solid %(color0)s; }
#cheatsheet treeview header button {
    background: none; border: none; box-shadow: none;
    border-bottom: 1px solid %(color0)s; color: %(color8)s;
    font-family: "Terminess Nerd Font"; font-weight: bold; font-size: 18pt; }
#cheatsheet scrollbar { background: none; border: none; }
#cheatsheet scrollbar slider {
    background-color: %(color12)s; min-width: 2px; border: none; }
#cheatsheet .status {
    color: %(color8)s; border-top: 1px solid %(color0)s; padding-top: 8px; }
"""


def palette():
    """PALETTE with wallust's values from colors-rofi.rasi, @references resolved."""
    pal = dict(PALETTE)
    try:
        with open(ROFI_COLORS, encoding="utf-8") as f:
            raw = dict(re.findall(r"^\s*([a-z0-9-]+):\s*([^;]+);", f.read(), re.M))
    except OSError:
        return pal

    def resolve(value, depth=0):
        value = value.strip()
        if value.startswith("@") and depth < 4:
            return resolve(raw.get(value[1:], ""), depth + 1)
        return value

    for key in pal:
        value = resolve(raw.get(key, ""))
        if value:
            pal[key] = value
    return pal


def gui(rows):
    import gi
    from gi.repository import GLib
    GLib.set_prgname("hypr-cheat-sheet")  # Wayland app_id
    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")
    from gi.repository import Gdk, Gtk, Pango

    # The title is what configs/WindowRules.lua matches (tag Cheat_Sheet:
    # float, center, 65% x 90%), so keep it in sync with that rule.
    win = Gtk.Window(title="Quick Cheat Sheet")
    win.set_name("cheatsheet")  # what the CSS above is scoped to
    win.set_default_size(1100, 1000)
    win.connect("destroy", Gtk.main_quit)

    provider = Gtk.CssProvider()
    provider.load_from_data((CSS % palette()).encode())
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10,
                  margin_top=14, margin_bottom=14, margin_start=18, margin_end=18)
    win.add(box)

    # The launcher's search line: the ПОИСК stamp, then what you type. A plain
    # Entry, not a SearchEntry, which brings its own magnifier and clear icons.
    line = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
    stamp = Gtk.Label(label=" ПОИСК ", valign=Gtk.Align.CENTER)
    stamp.get_style_context().add_class("stamp")
    line.pack_start(stamp, False, False, 0)
    search = Gtk.Entry()
    search.set_placeholder_text(
        " действие или клавиши, например: screenshot, workspace, super shift")
    line.pack_start(search, True, True, 0)
    box.pack_start(line, False, False, 0)

    # keys, action, lowercase haystack used for filtering
    store = Gtk.ListStore(str, str, str)
    for keys, act, raw in rows:
        store.append([keys, act, f"{keys} {raw} {act}".lower()])

    tokens = []

    def visible(model, it, _data):
        if not tokens:
            return True
        hay = model[it][2]
        return all(t in hay for t in tokens)

    filt = store.filter_new()
    filt.set_visible_func(visible)

    tree = Gtk.TreeView(model=filt)
    tree.set_can_focus(False)          # focus stays in the search box
    tree.set_enable_search(False)
    tree.set_headers_visible(True)
    tree.get_selection().set_mode(Gtk.SelectionMode.NONE)

    r_keys = Gtk.CellRendererText(weight=Pango.Weight.BOLD, ypad=6)
    col_keys = Gtk.TreeViewColumn("КЛАВИШИ", r_keys, text=0)
    col_keys.set_resizable(True)
    tree.append_column(col_keys)

    r_act = Gtk.CellRendererText(ypad=6)
    col_act = Gtk.TreeViewColumn("ДЕЙСТВИЕ", r_act, text=1)
    col_act.set_expand(True)
    tree.append_column(col_act)

    scroll = Gtk.ScrolledWindow()
    scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
    scroll.add(tree)
    scroll.get_style_context().add_class("list")
    box.pack_start(scroll, True, True, 0)

    # Ellipsized, so the line can never set the window's minimum width: it used
    # to, and held the window wider than the 65% the window rule asks for.
    status = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.END)
    status.get_style_context().add_class("status")
    box.pack_start(status, False, False, 0)

    total = len(rows)

    def refresh(*_):
        nonlocal tokens
        text = search.get_text().lower().replace("+", " ")
        tokens = text.split()
        filt.refilter()
        n = len(filt)
        status.set_text(
            f"{n} из {total} · Esc - закрыть · "
            f"SUPER H - открыть/закрыть · SUPER SHIFT K - список в rofi")
        scroll.get_vadjustment().set_value(0)

    search.connect("changed", refresh)

    def on_key(_w, ev):
        adj = scroll.get_vadjustment()
        if ev.keyval == Gdk.KEY_Escape:
            win.destroy()
            return True
        step = {Gdk.KEY_Down: adj.get_step_increment() * 3,
                Gdk.KEY_Up: -adj.get_step_increment() * 3,
                Gdk.KEY_Page_Down: adj.get_page_increment(),
                Gdk.KEY_Page_Up: -adj.get_page_increment()}.get(ev.keyval)
        if step is not None:
            adj.set_value(adj.get_value() + step)
            return True
        return False

    win.connect("key-press-event", on_key)

    refresh()
    win.show_all()
    search.grab_focus()
    # GTK scrolls to the tree's initial cursor row once it is laid out; pull
    # the view back to the first row after that happens.
    GLib.idle_add(lambda: scroll.get_vadjustment().set_value(0) and False)
    Gtk.main()


def main():
    try:
        rows = load_binds()
    except (OSError, subprocess.CalledProcessError, ValueError) as e:
        print(f"KeyHints: could not read binds from hyprctl: {e}", file=sys.stderr)
        return 1
    if "--dump" in sys.argv[1:]:
        dump(rows)
    else:
        gui(rows)
    return 0


if __name__ == "__main__":
    sys.exit(main())
