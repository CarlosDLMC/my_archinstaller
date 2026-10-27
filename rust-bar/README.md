# rust-bar

The desktop bar, rewritten in Rust: the quickshell bar's look, behaviour and
animations, with as little memory as possible and no more CPU.

## Why it can look identical

Most of the "look" of a Qt Quick bar is how Qt draws text, so the renderer
reproduces Qt's text pipeline instead of approximating it. Every rule below was
measured against quickshell 0.3.2 / Qt 6.12 on this machine (shaders extracted
from libQt6Quick, uniforms and textures read back from Qt's GL calls):

- **Distance-field text**: one field per glyph at 54 px, 5 px spread, sampled
  at texel centres; thresholds `QT_DF_BASE .5`, `BASEDEVIATION .065`,
  `SCALEFORMAXDEV .15`, `SCALEFORNODEV .3`, `RANGE .06`.
- **Plain text** is subpixel (Qt's `hiqsubpixeldistancefieldtext`, dual-source
  blended); **`Text.Outline`** is two passes - the outline material, then the
  plain text in gray on top.
- **Metrics**: FreeType's `linearHoriAdvance >> 10` (a 500-unit glyph at 24 px
  is 767/64 px); fonts with bitmap strikes (Terminess) take the strike's
  ascent/descent; a line is `ceil(ascent + descent)`; a Text's width includes the
  last glyph's negative right bearing (hinted), which is why a lone Nerd icon is
  wider than its advance.
- **Bold**: the bar's Qt uses the family's *regular* file and FreeType's
  synthetic embolden, except on fixed-pitch faces (Terminess), where bold looks
  exactly like regular.
- Colours go through QColor's arithmetic (`color.rs`), blending is in gamma
  space on a non-sRGB, premultiplied surface, like Qt's.

## Layout

| file | what |
|---|---|
| `src/gpu.rs`, `*.wgsl` | wgpu (Vulkan only), one device for every surface; instanced quads: rounded rects, distance-field and subpixel text, images |
| `src/text.rs` | fonts (fontconfig match, mmapped), FreeType outlines, distance fields, Qt metrics, layout, elide |
| `src/color.rs`, `src/theme.rs` | QColor maths; Theme.qml's roles from `wallust-colors.json` |
| `src/app.rs` | Wayland (sctk layer shell), event loop, one strip per output, frame-callback redraws, helper processes |
| `src/services.rs` | Mango.qml streams, SystemStats, clock, weather, DND, battery, Wi-Fi, VPN, agent check |
| `src/pw.rs` | PipeWire: default sink/source volume and mute (needs clang to build) |
| `src/bar.rs` | shell.qml's strip |
| `src/ipc.rs` | `rust-bar msg <target> <function> [args]` - the keybinds' calls |

## Status

- [x] Engine, text parity (≥99.6 % of pixels within 8/255 of Qt on the test sets)
- [x] Strip: every widget - logo, workspaces, dividers, title, clock, bell (DND), weather pill, agent, CPU, memory, volume (PipeWire, event-driven), battery (sysfs), Wi-Fi (nmcli monitor), VPN, layout, ПУЛЬТ icon; matches the QML strip in the sandbox
- [ ] Strip: Wi-Fi blink while connecting, colour emoji in titles, battery change events (netlink instead of udevadm)
- [ ] Animations (Qt easing curves), cursor shape on hover changes, click-on-release
- [ ] Cards (notch canvas, CardSurface, CardKeys) - calendar, weather, audio, network, power, battery, ПУЛЬТ, VPN, agent
- [ ] Overlays: layout OSD, clipboard, polkit agent, power menu, screenshot, recording
- [ ] Wallpaper carousel + reveal, overview
- [ ] Switch-over: keybinds, scripts, installer build step

## Testing

Parity is checked in a headless mango sandbox, against quickshell itself (not
`grabToImage` or the `qml` runtime, which turn subpixel text off):
`rust-bar textref SPEC OUT.png` renders text rows for diffing; the sandbox
scripts live outside the repo (`~/.cache/bar-ab`). First strip measurement in
that sandbox: QML bar 77 MB PSS / 57 MB private; this bar 19 MB / 7 MB, idle
CPU 0.
