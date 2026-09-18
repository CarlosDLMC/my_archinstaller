# Gaming

Short notes for a fresh install. Packages (`mangohud`, `lib32-mangohud`,
`gamescope`) come from `install-scripts/01-hypr-pkgs.sh`. Steam is **not**
installed by this repo — `sudo pacman -S steam`.

## 1. Turn on Proton

Steam → Settings → Compatibility → **Enable Steam Play for all other titles**,
pick the latest numbered Proton (not Experimental), restart Steam.

Windows games won't launch without this. Native Linux games don't need it.

**Experimental vs. latest stable:** use the numbered stable. Experimental
tracks bleeding-edge Wine/DXVK and can regress. Force it on a *single* game
only if that game is broken: Properties → Compatibility → Force the use of a
specific Steam Play compatibility tool. Check protondb.com first.

Don't downgrade Proton on a game that already ran — the prefix in
`steamapps/compatdata/<appid>/` can break. Back it up first.

## 2. Per-game commands

Right-click game → Properties → General → **Launch Options**.

`%command%` is a placeholder Steam replaces with the real launch command.
Wrappers go *before* it, env vars before that:

```
VAR=value   wrapper   [flags]   --   %command%
```

| Want | Launch option |
|---|---|
| Nothing | *(leave empty)* |
| **Default — overlay + fps cap** | `mangohud %command%` |
| FSR, game has no built-in option | `gamescope -W 2560 -H 1440 -w 1920 -h 1080 -F fsr --fsr-sharpness 5 -f --adaptive-sync --mangoapp -- %command%` |
| Overlay visible from the start | `MANGOHUD_CONFIG=no_display=0 mangohud %command%` |
| Uncapped, to see what the card does | `MANGOHUD_CONFIG=fps_limit=0 mangohud %command%` |

Use `mangohud %command%` by default. gamescope is a repair tool — reach for it
when a game gets the resolution wrong, loses the cursor to another monitor,
breaks on alt-tab, or needs FSR it doesn't ship.

**Inside gamescope use `--mangoapp`, outside it use `mangohud`. Never both.**

FSR: always prefer the game's own FSR 2/3 setting. gamescope's is FSR 1.0,
which upscales the finished frame including the HUD. `-w`/`-h` is the render
size, `-W`/`-H` the output. Sharpness is backwards: 0 = max, 20 = none.
FSR 4 needs RDNA 4 — it will not run on older cards.

Keys: `Shift_R+F12` show/hide overlay · `Shift_L+F1` cycle the cap ·
in gamescope `SUPER+U` toggle FSR, `SUPER+I`/`O` sharpness.
`Keybinds.lua` deliberately leaves SUPER + U/N/I/S/G unbound for gamescope.

## 3. Where the config lives

```
~/.config/MangoHud/MangoHud.conf     ← deployed by Hyprland-Dots/copy.sh
Hyprland-Dots/config/MangoHud/       ← repo copy, edit this one
/usr/share/doc/mangohud/MangoHud.conf.example   ← every option
```

It ships with `no_display`, so the overlay starts hidden. The cap and vsync
still apply — MangoHud is not just an overlay.

## 4. What to cap the fps to

**Cap 3 below your monitor's max refresh rate.** Find it:

```sh
hyprctl monitors | grep -A1 '^Monitor'          # current mode, e.g. 2560x1440@74.998
edid-decode /sys/class/drm/card*-DP-*/edid | grep -i 'Monitor ranges'
```

The EDID range (e.g. `48-75 Hz V`) is the FreeSync window. Set
`fps_limit` in `MangoHud.conf` to about 3 under the top of it:

| Panel | Cap |
|---|---|
| 60 Hz | 57 |
| 75 Hz | **72** ← the desktop's Samsung LS24A600N |
| 144 Hz | 141 |
| 165 Hz | 162 |

Sitting exactly at the ceiling makes the driver fall back to ordinary vsync
and queue frames, which costs latency without buying smoothness. Backing off
a few fps keeps you genuinely inside the variable-refresh window.

The **bottom** of the range matters too. If max ÷ min is under 2 there is no
LFC (Low Framerate Compensation) to catch you — a 48–75 Hz panel has none, so
dropping under 48 fps means visible judder. Turn settings down until the 1%
low stays clear of it; MangoHud shows that as the second number in
`fps_metrics`.

FreeSync itself needs no launch option. It comes from `misc:vrr = 2` in
`config/hypr/configs/SystemSettings.lua` (fullscreen only) and works whether
or not MangoHud is loaded — but the game must be **Fullscreen**, not
Borderless Windowed. Check with `hyprctl monitors | grep -i vrr` → `vrr: true`.
