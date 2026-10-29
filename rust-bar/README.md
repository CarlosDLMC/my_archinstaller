# rust-bar

The desktop bar: the strip on every screen, its dropdown cards, the overview
(SUPER+A), the full-screen menus and the polkit agent, in one Rust binary that
draws with Vulkan. Why it is written in Rust, with the measurements, is in the
repo README ("Why the bar is written in Rust").

Design inspired by [quickshell-btw](https://github.com/tonybanters/quickshell-btw)
by Tony Banters.

## Commands

| command | what |
|---|---|
| `rust-bar` | the bar; mango starts it (`startup.conf`), one per session |
| `rust-bar msg <target> <function> [args]` | a call to the running bar - what the keybinds run (`gamemode set`, `cards toggle <card>`, `power toggle\|exit`, `overview toggle\|open\|close`, `wallpaper toggle\|open\|close\|next\|prev\|nextFolder\|prevFolder`, `clipboard toggle`, `shot open`, `record open\|stop`, `layout next`) |
| `rust-bar crt` | the CRT power-off effect `CrtOff.sh` runs before the screen goes off |
| `rust-bar textref SPEC OUT.png` | renders rows of text to a PNG, for checking the text renderer |

Its helper scripts are in `~/.config/rust-bar/scripts/` (repo:
`dotfiles/config/rust-bar/scripts/`), wallust writes its palette to
`~/.config/rust-bar/wallust-colors.json`, and its caches (weather, thumbnails,
the Claude Code usage) are in `~/.cache/rust-bar/`.

## What it shows

- **Strip**: logo, workspaces, window title, clock, bell (do not disturb),
  weather, Claude Code, CPU, memory, volume, battery, Wi-Fi, VPN, keyboard
  layout and the ПУЛЬТ icon. The volume follows PipeWire's events, the battery
  the kernel's power_supply uevents, Wi-Fi `nmcli monitor`.
- **Cards** (click an icon, or SUPER+CTRL+letter with the focus inside):
  power, calendar, weather, audio (outputs, inputs, the live mic meter, per-app
  faders), ПУЛЬТ (Bluetooth, night light, НЕ ЗАСЫПАТЬ, the CPU/RAM switch,
  power profiles), VPN, Wi-Fi networks with password entry, network details
  (addresses, traffic, DNS, speed test, QR share), Claude Code usage, battery
  (gauge, health, charge limit).
- **Full-screen menus**: overview (workspace grid with window grabs, drag to
  move), wallpaper carousel and its reveal, clipboard history, screenshot and
  recording dialogs, the power menu, the keyboard-layout popup.
- **Polkit agent**: the session's authentication agent, with its own password
  dialog.
- The theme follows wallust live; the timezone and the weather city follow
  their cache files.

## How it draws

The look comes from Qt Quick, so the renderer reproduces Qt's drawing rules
instead of approximating them:

- **Distance-field text**: one field per glyph at 54 px, 5 px spread, sampled
  at texel centres; thresholds `QT_DF_BASE .5`, `BASEDEVIATION .065`,
  `SCALEFORMAXDEV .15`, `SCALEFORNODEV .3`, `RANGE .06`.
- **Text that has not changed is subpixel** (dual-source blended), text that
  changed after its card opened (live values, hover colours) is grey
  anti-aliased, as Qt 6.12 does it (`TextMemo`). Outlined text is two passes:
  the outline, then the plain text on top. Translucent text stays subpixel:
  coverage is scaled by alpha × opacity.
- **Metrics**: FreeType's `linearHoriAdvance >> 10`; fonts with bitmap strikes
  (Terminess) take the strike's ascent/descent; a line is
  `ceil(ascent + descent)`; a text's width includes the last glyph's negative
  right bearing. Bold is FreeType's synthetic embolden on the regular file,
  except on fixed-pitch faces.
- **Shaping**: rustybuzz (flags, ZWJ sequences, JetBrains Mono ligatures);
  colour emoji from the Noto strike, scaled. Line breaking follows UAX #14.
- **Layout** snaps to the pixel grid like Qt's grid layout engine: minimum
  sizes round up, fill cells get rounded starts and sizes.
- **Rounded rectangles**: each corner is a polygon of
  `clamp(ceil(r·π/6), 3, 18)` chords, radius capped at `min(w, h)·0.4999`, with
  a half-pixel anti-aliasing ring; radius 0 is plain triangles under the GPU
  fill rule.
- **Sheared clips** (the carousel's cards) cut a parallelogram with
  anti-aliased sloping sides.
- **Colour** maths is QColor's (darker/lighter in float HSV); blending is in
  gamma space on a premultiplied surface.
- **Animations** use Qt's easing curves and retarget mid-flight.

## Layout

| file | what |
|---|---|
| `src/gpu.rs`, `src/*.wgsl` | wgpu (Vulkan only), one device for every surface; instanced quads: rounded rects, distance-field and subpixel text, images |
| `src/text.rs` | fonts (fontconfig match, mmapped), FreeType outlines, distance fields, metrics, shaping, line breaking, elide |
| `src/color.rs`, `src/theme.rs` | colour maths; the theme's roles from `wallust-colors.json` |
| `src/app.rs` | Wayland (layer shell), event loop, one strip per output, frame-callback redraws, helper processes |
| `src/runtime.rs`, `src/anim.rs` | processes, timers, event-loop sources; animated values and easing |
| `src/services.rs` | mango's IPC streams, CPU/memory stats, clock, weather, do not disturb, battery, Wi-Fi, VPN, agent check |
| `src/pw.rs` | PipeWire: default sink/source volume and mute, the mic meter (needs clang to build) |
| `src/bar.rs` | the strip |
| `src/cards.rs` | the cards' surface, notch, focus chain and keys, and the small cards (power, calendar, weather) |
| `src/audio_card.rs`, `src/pult.rs`, `src/vpn.rs`, `src/wifi_card.rs`, `src/network_card.rs`, `src/agent.rs`, `src/battery.rs`, `src/cal.rs` | the other cards |
| `src/osd.rs` | the centred dialogs' surface (layout popup, power menu, screenshot/recording, clipboard, polkit): a panel on the focused screen, the dim behind it, fade and scale |
| `src/overview.rs`, `src/wallpaper.rs`, `src/clip.rs`, `src/capture.rs`, `src/power.rs`, `src/layout.rs` | overview, wallpaper carousel, clipboard, screenshot/recording, power menu, layout popup |
| `src/polkit.rs` | the polkit agent (system bus, PAM conversation through polkit's helper socket) and its dialog |
| `src/crt.rs` | `rust-bar crt` |
| `src/ipc.rs` | `rust-bar msg`: the socket in `$XDG_RUNTIME_DIR`, one bar per session |

## Building

`install-scripts/rust-bar.sh` builds it as the `rust-bar` package from
`pkgbuilds/rust-bar`, versioned by a hash of this crate, so a re-run rebuilds
only when the crate changed. By hand: `cargo build --release` (needs rust and
clang). It needs a Vulkan driver; machines without one (virtual machines) get
Mesa's software Vulkan from the installer.
