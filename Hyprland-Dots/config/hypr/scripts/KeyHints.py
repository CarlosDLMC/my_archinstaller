#!/usr/bin/env python3
"""Keybind cheat sheet with a search box (SUPER H).

The list is read from mango's config - ~/.config/mango/config.conf and every
file it sources, the way mango reads them - so it follows the binds as they
are: add a bind with a description and it shows up here. A bind's
description is the comment at the end of its line ("  # text").

Usage:
    KeyHints.py          open the GTK window (type to filter, Esc closes)
    KeyHints.py --dump   print "KEYS<TAB>ACTION" lines (used by KeyBinds.sh)
"""

import json
import os
import re
import subprocess
import sys

CONFIG = os.path.expanduser("~/.config/mango/config.conf")

# Modifier order, and their weight when sorting (SHIFT=1 CTRL=4 ALT=8 SUPER=64).
MOD_BITS = ((64, "SUPER"), (4, "CTRL"), (8, "ALT"), (1, "SHIFT"))

# Friendlier names for the key names in the config. Anything not listed is
# shown as-is (F6, Print, XF86AudioPlay, ...).
KEY_NAMES = {
    "btn_left": "left click (drag)",
    "btn_right": "right click (drag)",
    "UP": "scroll up",
    "DOWN": "scroll down",
    "bracketleft": "[",
    "bracketright": "]",
    "period": ".",
    "comma": ",",
    "space": "Space",
    "Return": "Enter",
    "Delete": "Del",
    "Print": "PrtSc",
    "Shift_L": "Left Shift",
    "Alt_L": "Left Alt",
    "code:209": "XF86AudioPause",
}


def natural(s):
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", s)]


def strip_comment(line):
    """(value, comment): mango cuts a line at a # that follows whitespace and
    is not inside quotes."""
    quote = None
    for i, ch in enumerate(line):
        if quote:
            if ch == quote:
                quote = None
        elif ch in "'\"":
            quote = ch
        elif ch == "#" and i > 0 and line[i - 1] in " \t":
            return line[:i].rstrip(), line[i + 1:].strip()
    return line.rstrip(), ""


def config_lines(path, seen):
    """Every line of the config and the files it sources, in mango's order."""
    path = os.path.realpath(path)
    if path in seen:
        return
    seen.add(path)
    base = os.path.dirname(CONFIG)
    try:
        with open(path, encoding="utf-8") as f:
            for raw in f:
                if raw.startswith("#") or not raw.strip():
                    continue
                key, _, value = raw.rstrip("\n").partition("=")
                key = key.strip()
                if key in ("source", "source_optional"):
                    src = value.split(" #", 1)[0].strip()
                    if src.startswith("./"):
                        src = os.path.join(base, src[2:])
                    yield from config_lines(os.path.expanduser(src), seen)
                else:
                    yield key, value
    except OSError:
        return


def load_binds():
    rows, seen = [], set()
    for key, value in config_lines(CONFIG, set()):
        value, desc = strip_comment(value)
        if re.fullmatch(r"bind[slrpc]*", key):
            kind = "key"
        elif key in ("mousebind", "axisbind", "gesturebind"):
            kind = key
        else:
            continue
        fields = [f.strip() for f in value.split(",")]
        if len(fields) < 3:
            continue
        mod_names = [m.strip().upper() for m in fields[0].split("+")]
        mask = 0
        for bit, name in MOD_BITS:
            if name in mod_names:
                mask |= bit
        raw = fields[1]
        if kind == "gesturebind":
            label = f"{fields[2]}-finger swipe {raw.lower()}"
        else:
            label = KEY_NAMES.get(raw, raw.upper() if len(raw) == 1 else raw)
        mods = [name for bit, name in MOD_BITS if mask & bit]
        keys = " + ".join(mods + [label])
        act = desc or " ".join(f for f in fields[2:] if f)
        if (keys, act) in seen:
            continue
        seen.add((keys, act))
        # SUPER binds first, then grouped by modifier combo, then by key.
        sort_key = (0 if mask & 64 else 1, mask, natural("10" if raw == "0" else raw))
        rows.append((sort_key, keys, act, raw))
    rows.sort(key=lambda r: r[0])
    return [(keys, act, raw) for _, keys, act, raw in rows]


def dump(rows):
    for keys, act, _ in rows:
        print(f"{keys}\t{act}")


# The launcher's look (SUPER + D, rofi/themes/soviet-teletype.rasi) in
# wallust's rofi colours, so the cheat sheet follows the wallpaper exactly as
# rofi does: a grey window under a title band, a red > prompt with a blinking
# one-letter block cursor, and the list on the terminal's black. The literals
# are the sovietpunk fallbacks, for when the file is missing. mango draws
# the frame: it is the focused-window border.
ROFI_COLORS = os.path.expanduser("~/.config/rofi/wallust/colors-rofi.rasi")
PALETTE = {
    "normal-background": "#262625",   # the window
    "foreground": "#E8C4C0",          # text
    "color0": "#4C4C4B",              # dividers
    "color8": "#96716D",              # the band, column headers, the status line
    "color12": "#59302D",             # scrollbar
    "color14": "#BE564A",             # the prompt and the cursor
    "color15": "#D6A29C",             # what you type
}

CSS = """
#cheatsheet { background-color: %(normal-background)s; color: %(foreground)s; }
#cheatsheet * { border-radius: 0; }
/* The title band, a shade off the window and run out to its edges. */
#cheatsheet .band {
    background-color: rgba(255,255,255,0.07); color: %(color8)s; padding: 9px 20px;
    font-family: "Terminess Nerd Font"; font-weight: bold; font-size: 17pt; }
#cheatsheet .prompt {
    color: %(color14)s; font-family: "Terminess Nerd Font"; font-weight: bold; font-size: 22pt; }
#cheatsheet .typed {
    color: %(color15)s; font-family: "Terminess Nerd Font"; font-size: 22pt; }
/* The real field takes the typing but is not seen: GTK centres a wide caret on
   the insertion point, so its own block would sit on the last letter typed.
   The line is drawn in .typed instead, with the block after it. */
#cheatsheet entry.hidden {
    opacity: 0; min-width: 1px; min-height: 1px; padding: 0; margin: 0;
    border: none; box-shadow: none; background: none; }
/* The list on the terminal's black (foot.ini), as in the launcher. */
#cheatsheet .screen { background-color: #000000; padding: 8px 6px; }
#cheatsheet treeview.view {
    background-color: #000000; color: %(foreground)s;
    font-family: "Terminess Nerd Font"; font-size: 20pt; }
#cheatsheet treeview header button {
    background: #000000; border: none; box-shadow: none;
    border-bottom: 1px solid %(color0)s; color: %(color8)s;
    font-family: "Terminess Nerd Font"; font-weight: bold; font-size: 18pt; }
#cheatsheet scrollbar { background: none; border: none; }
#cheatsheet scrollbar slider {
    background-color: %(color12)s; min-width: 2px; border: none; }
#cheatsheet .status {
    color: %(color8)s; padding-top: 4px;
    font-family: "Terminess Nerd Font"; font-weight: bold; font-size: 16pt; }
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

    pal = palette()
    provider = Gtk.CssProvider()
    provider.load_from_data((CSS % pal).encode())
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
    win.add(outer)

    band = Gtk.Label(label="ЭВМ «ЭЛЕКТРОНИКА» · СОЧЕТАНИЯ КЛАВИШ", xalign=0)
    band.get_style_context().add_class("band")
    outer.pack_start(band, False, False, 0)

    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10,
                  margin_top=12, margin_bottom=14, margin_start=20, margin_end=20)
    outer.pack_start(box, True, True, 0)

    # The search line, as the launcher's: a red >, then what you type with a
    # blinking block after it.
    line = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
    prompt = Gtk.Label(label=">", valign=Gtk.Align.CENTER)
    prompt.get_style_context().add_class("prompt")
    line.pack_start(prompt, False, False, 0)
    typed = Gtk.Label(xalign=0, valign=Gtk.Align.CENTER, ellipsize=Pango.EllipsizeMode.START)
    typed.get_style_context().add_class("typed")
    line.pack_start(typed, True, True, 0)
    search = Gtk.Entry(width_chars=1, max_width_chars=1)
    search.get_style_context().add_class("hidden")
    line.pack_start(search, False, False, 0)
    box.pack_start(line, False, False, 0)

    hint = " действие или клавиши, например: screenshot, workspace, super shift"
    cursor_on = True

    def draw_line():
        text = GLib.markup_escape_text(search.get_text())
        # A space when off, the same width as the block: nothing shifts.
        block = f'<span foreground="{pal["color14"]}">█</span>' if cursor_on else " "
        tail = "" if search.get_text() else f'<span foreground="{pal["color8"]}">{GLib.markup_escape_text(hint)}</span>'
        typed.set_markup(text + block + tail)

    def blink():
        nonlocal cursor_on
        cursor_on = not cursor_on
        draw_line()
        return True

    blinker = [GLib.timeout_add(600, blink)]

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

    r_keys = Gtk.CellRendererText(weight=Pango.Weight.BOLD, ypad=4)
    col_keys = Gtk.TreeViewColumn("КЛАВИШИ", r_keys, text=0)
    col_keys.set_resizable(True)
    tree.append_column(col_keys)

    r_act = Gtk.CellRendererText(ypad=4)
    col_act = Gtk.TreeViewColumn("ДЕЙСТВИЕ", r_act, text=1)
    col_act.set_expand(True)
    tree.append_column(col_act)

    scroll = Gtk.ScrolledWindow()
    scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
    scroll.add(tree)
    scroll.get_style_context().add_class("screen")
    box.pack_start(scroll, True, True, 0)

    # Ellipsized, so the line can never set the window's minimum width: it used
    # to, and held the window wider than the 65% the window rule asks for.
    status = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.END)
    status.get_style_context().add_class("status")
    box.pack_start(status, False, False, 0)

    total = len(rows)

    def refresh(*_):
        nonlocal tokens, cursor_on
        text = search.get_text().lower().replace("+", " ")
        tokens = text.split()
        filt.refilter()
        n = len(filt)
        status.set_text(
            f"{n} ИЗ {total} · ESC - ЗАКРЫТЬ · "
            f"SUPER H - ОТКРЫТЬ/ЗАКРЫТЬ · SUPER SHIFT K - СПИСОК В ROFI")
        scroll.get_vadjustment().set_value(0)
        # Typing shows the cursor and restarts its blink, as a terminal does.
        cursor_on = True
        GLib.source_remove(blinker[0])
        blinker[0] = GLib.timeout_add(600, blink)
        draw_line()

    search.connect("changed", refresh)

    def on_key(_w, ev):
        adj = scroll.get_vadjustment()
        if ev.keyval == Gdk.KEY_Escape:
            win.destroy()
            return True
        # The cursor lives at the end of the line: moving it inside the hidden
        # field would type where the drawn line does not show it.
        if ev.keyval in (Gdk.KEY_Left, Gdk.KEY_Right, Gdk.KEY_Home, Gdk.KEY_End):
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
        print(f"KeyHints: could not read binds from the mango config: {e}", file=sys.stderr)
        return 1
    if "--dump" in sys.argv[1:]:
        dump(rows)
    else:
        gui(rows)
    return 0


if __name__ == "__main__":
    sys.exit(main())
