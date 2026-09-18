#!/usr/bin/env python3
"""Pick a readable text colour for each wallust slot, for rofi.

wallust fills color0..color15 from whatever the wallpaper happens to hold, so
a numbered slot has no guaranteed lightness. The rofi themes use those slots
as fills and then print a *fixed* colour on top - style-4 prints {{background}}
on @color12 - which is a coin flip. On Catppuccin-Mocha_hanged_man_tree color12
came out #09151E and the selected row was black on black (1.14:1); on the
sovietpunk wallpaper it is #59302D and black reads 1.89:1.

The fill is the part that looks good, so the fill is left exactly as wallust
made it. Only the text on top is chosen here: keep {{background}} whenever it
clears 4.5:1, which is what the themes have always done and what most
wallpapers give, and fall back to {{foreground}} only when it does not.

Run as a wallust hook (see [hooks] in ~/.config/wallust/wallust.toml), after
the templates are written. Rewrites the `on-colorN:` lines that the
colors-rofi.rasi template emits with {{background}} as their default, so if
this never runs rofi still gets a valid palette that behaves exactly as before.
"""

import os
import re
import sys

DEFAULT_TARGET = "~/.config/rofi/wallust/colors-rofi.rasi"

# WCAG AA for body text. The themes use these slots behind app names and the
# search entry, so this is ordinary reading text, not a graphical accent.
MIN_RATIO = 4.5


def luminance(hex_colour):
    h = hex_colour.lstrip("#")
    srgb = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def parse(text):
    """slot -> #RRGGBB. `background:` is an rgba() literal, so read it too:
    rofi composites it over the blur behind the window, and the themes treat
    it as the flat colour they print on accents."""
    slots = {}
    for line in text.splitlines():
        m = re.match(r"\s*([a-z0-9-]+)\s*:\s*(#[0-9A-Fa-f]{6})\s*;", line)
        if m:
            slots[m.group(1)] = "#" + m.group(2).lstrip("#").upper()
            continue
        m = re.match(r"\s*(background)\s*:\s*rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)", line)
        if m:
            slots["background"] = "#%02X%02X%02X" % tuple(int(m.group(i)) for i in (2, 3, 4))
    return slots



def _to_hsl(hex_colour):
    h = hex_colour.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    hi, lo = max(r, g, b), min(r, g, b)
    light = (hi + lo) / 2
    if hi == lo:
        return 0.0, 0.0, light
    d = hi - lo
    sat = d / (2 - hi - lo) if light > 0.5 else d / (hi + lo)
    if hi == r:
        hue = ((g - b) / d) % 6
    elif hi == g:
        hue = (b - r) / d + 2
    else:
        hue = (r - g) / d + 4
    return hue / 6, sat, light


def _to_hex(hue, sat, light):
    if sat == 0:
        r = g = b = light
    else:
        q = light * (1 + sat) if light < 0.5 else light + sat - light * sat
        p = 2 * light - q

        def channel(t):
            t %= 1
            if t < 1 / 6:
                return p + (q - p) * 6 * t
            if t < 1 / 2:
                return q
            if t < 2 / 3:
                return p + (q - p) * (2 / 3 - t) * 6
            return p

        r, g, b = channel(hue + 1 / 3), channel(hue), channel(hue - 1 / 3)
    return "#%02X%02X%02X" % tuple(round(c * 255) for c in (r, g, b))


def lift_to_contrast(colour, fill):
    """Move `colour` away from `fill` in lightness until it clears MIN_RATIO.

    Steps toward whichever end is further from the fill, so dark text on a
    mid-grey goes darker and light text goes lighter. One of the two always
    gets there: at the crossover grey both black and white clear about 4.5:1.
    """
    hue, sat, light = _to_hsl(colour)
    up = luminance(colour) >= luminance(fill)
    steps = [light + i * 0.02 for i in range(1, 50)] if up else \
            [light - i * 0.02 for i in range(1, 50)]
    for step in steps:
        if not 0.0 <= step <= 1.0:
            break
        candidate = _to_hex(hue, sat, step)
        if contrast(candidate, fill) >= MIN_RATIO:
            return candidate
    return "#FFFFFF" if up else "#000000"

def readable_on(fill, background, foreground):
    """The text to print on `fill`: "@background", "@foreground", or a hex.

    Preference, not just the maximum: @background is what the themes already
    print, so it wins every tie and every case where it is merely adequate.
    That keeps the look identical on the wallpapers where nothing was ever
    wrong; only the unreadable ones change. Returning a rasi reference rather
    than a hex value also keeps DarkLight.sh's light-mode rewrite working.
    """
    if contrast(background, fill) >= MIN_RATIO:
        return "@background"
    if contrast(foreground, fill) >= MIN_RATIO:
        return "@foreground"
    # Neither clears: a mid-tone fill, which nothing already in the palette
    # can sit on. Lift one of them away from the fill instead - the same trick
    # Theme.qml plays for the bar logo, where hue and saturation stay and only
    # lightness moves, as far as it has to and no further.
    #
    # Both are tried, because either can be stuck: @background is often pure
    # black and cannot go darker, and a near-white @foreground cannot go
    # lighter. @background is still preferred when both work, to stay closer
    # to what the theme has always printed.
    for candidate in (lift_to_contrast(background, fill),
                      lift_to_contrast(foreground, fill)):
        if contrast(candidate, fill) >= MIN_RATIO:
            return candidate
    # Unreachable for any real fill: at the crossover grey both ends clear
    # ~4.5:1. Keep the better of the two rather than raise.
    return (background if contrast(background, fill) >= contrast(foreground, fill)
            else foreground)


def main():
    # An argument overrides the target, which is what the checks in
    # /tmp use to run this against a generated palette without touching
    # the live one.
    target = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else DEFAULT_TARGET)
    try:
        with open(target) as fh:
            text = fh.read()
    except OSError as exc:
        print(f"RofiContrast: cannot read {target}: {exc}", file=sys.stderr)
        return 0  # never fail the wallust run over this

    slots = parse(text)
    if "background" not in slots or "foreground" not in slots:
        print("RofiContrast: palette has no background/foreground, leaving it alone",
              file=sys.stderr)
        return 0

    bg, fg = slots["background"], slots["foreground"]

    def rewrite(match):
        name = match.group(1)           # e.g. "on-color12"
        fill = slots.get(name[3:])      # the slot it sits on
        if fill is None:
            return match.group(0)
        return f"{name}: {readable_on(fill, bg, fg)};"

    # `background` here is the rgba() literal the themes actually print, not
    # wallust's {{background}} hex - parse() reads it from that line.

    #  A palette left over from before the template grew the on-colorN lines
    #  would leave the themes referring to names that do not exist, which rofi
    #  will not start on. Put them in rather than let that happen.
    if not re.search(r"^on-color\d+\s*:", text, flags=re.M):
        block = "".join(f"on-color{i}: @background;\n" for i in range(16))
        close = text.rindex("}")
        text = text[:close] + block + text[close:]

    out = re.sub(r"^(on-color\d+)\s*:\s*[^;]+;", rewrite, text, flags=re.M)

    if out != text:
        with open(target, "w") as fh:
            fh.write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
