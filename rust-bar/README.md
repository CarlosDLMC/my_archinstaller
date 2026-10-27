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
- **Positions**: anchors centre with qRound(half(parent) - half(size)), where
  an odd integer part rounds a half up; horizontalAlignment centres the
  advances (no overhang).
- **Layouts** snap to the pixel grid (QGridLayoutEngine): an item that cannot
  shrink has its preferred size, margins included, as a minimum that is
  rounded *up*, so the strip's cells are whole pixels and the fill item takes
  the rest; a GridLayout's fill columns get qRound()ed starts with the
  neighbours absorbing the difference, then qRound()ed sizes.
- **Subpixel only until a Text changes**: Qt 6.12 rebuilds a Text's node on
  any change of text, colour or layout, and the distance-field glyph nodes it
  recycles come back with gray anti-aliasing - so a card's live values, hover
  colours and anything updated after the card opened are gray, the rest
  subpixel (`TextMemo`).
- **Rounded rectangles** are Qt's smooth rectangle node, not a circle SDF:
  each corner is an inscribed polygon of `clamp(ceil(r·π/6), 3, 18)` chords,
  radius capped at `min(w, h)·0.4999` and dropped at ≤ 0.5 px, and the
  anti-aliasing ring moves every edge vertex half a pixel in x *and* in y, so
  alpha is `0.5 - max((n·q - c) / (n.x + n.y))` over the edges and chords
  (exact on the battery gauge's 1 px corners, where `fwidth` was 60 levels off).
- **Translucent text stays subpixel**: Qt keeps the subpixel material for any
  colour alpha or item opacity; coverage is scaled by alpha × opacity and the
  colour goes in once (white at alpha .3 over 16 reads 84 = 242·.3 + 16·.7).
- **Unsmoothed rectangles** (radius 0) are triangles under the GPU fill rule:
  a 1 px border at x.5 lands on the pixel whose centre the left edge passes.
- **Line breaking** is QTextLayout's: Unicode line-break opportunities
  (UAX #14 - after spaces, hyphens, slashes), Text.Wrap breaking an
  over-long piece anywhere; a wrapped Text is one node, so all its lines
  turn gray together.
- Colours go through QColor's arithmetic (Qt 6's darker/lighter in float HSV) (`color.rs`), blending is in gamma
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
| `src/cards.rs` | the dropdown cards: surfaces, notch, focus chain, keys, each card's content |
| `src/anim.rs`, `src/runtime.rs` | easing/animated values; processes, timers, event-loop sources |
| `src/ipc.rs` | `rust-bar msg <target> <function> [args]` - the keybinds' calls |

## Status

- [x] Engine, text parity (≥99.6 % of pixels within 8/255 of Qt on the test sets)
- [x] Strip: every widget - logo, workspaces, dividers, title, clock, bell (DND), weather pill, agent, CPU, memory, volume (PipeWire, event-driven), battery (sysfs), Wi-Fi (nmcli monitor), VPN, layout, ПУЛЬТ icon; matches the QML strip in the sandbox
- [x] Shaping (rustybuzz: flags, ZWJ sequences, JetBrains Mono ligatures - Qt applies them) and colour emoji (Noto strike scaled by size/strike height, as Qt does)
- [x] Animations (Qt easing curves, Behavior-style retargeting, looping pulse), cursor shape on hover changes, click-on-release
- [x] Card framework: card-sized layer + 1-pixel click catcher (wp_viewporter) instead of a full-screen surface, notch canvas (arcTo, QPainter-like fill), CardKeys focus chain, hover colour animations, `cards toggle` IPC
- [x] Power card (logo) - matches the QML card; with it open: 21 MB PSS / 24 MB VRAM against 88 MB / 127 MB
- [x] Calendar card (clock) - matches; Qt's CLDR month/day names for LC_TIME, wheel steps months
- [x] Weather card - matches (tooltip parsing as CenterInfo does it, word wrap)
- [x] Audio card - outputs, inputs + live mic meter (PipeWire peak monitor), per-app faders, default device switching, slider drag/wheel/keys; strip: left click mutes, wheel steps 5%
- [x] ПУЛЬТ card - Bluetooth (power, paired, scan, pair, connect), night light, НЕ ЗАСЫПАТЬ (the systemd-inhibit holder), the stats switch, power profiles; grows with its lists
- [x] VPN card - tunnel + off key, ВРЕМЯ/ПОГОДА sync with busy spinners, WireGuard configs with flags; the same scripts
- [x] Theme follows wallust live (inotify, 80 ms debounce); timezone and weather city follow their cache files
- [x] Claude Code card - plan, limit meters with reset times and stale-data note, tokens by day and by model (hover shows the split), the same agent-usage.py modes and refresh cadence
- [x] Wi-Fi card (networks): link header, scanned networks with signal and lock, rescan timing, password entry (● echo, blinking cursor), connect watchdog, disconnect; the strip icon blinks while connecting
- [x] Battery card - level, segment gauge with the limit marker, time left / draw, capacity, cycles, health, per-pack rows, charge-limit presets through the same root helper; kernel power_supply uevents (netlink, no `udevadm monitor` process) keep it and the strip fresh
- [x] Network details card (Wi-Fi right click, NetworkPanel): radio key, SSID, channel gauge, addresses, traffic and latency every 3 s from network-status.sh, the DNS picker, the speed test (streamed, cancellable) and the share-by-QR view, with the same scripts and nmcli calls
- [x] The CRT power-off effect as `rust-bar crt` (CrtOff.sh will call it instead of `qs -c crt`): the frame folds to a line, draws in to a point, fades; `done` for CrtOff.sh; 30 s safety exit
- [x] Overlay framework (osd.rs): Overlay-layer panel on the focused screen, its own size, input only on the panel; the dialogs' dim is one stretched pixel; fade 0..1 OutCubic with scale .94..1
- [x] Layout OSD + LayoutState: MRU `layout next`, the strip label cycles, the switcher shows on every change, hover holds it, click picks
- [x] Power menu (PowerOsd + PowerState): the character-cell console, hover/arrows/letters by scan code, the five-second launch countdown (sync on ПРОДУВКА, fires at zero), UEFI/Windows keys from login1/efibootmgr; the logo card's keyboard path arms it
- [x] Screenshot + recording dialogs (ShotOsd/RecordOsd + their states): big keys with hover/held looks, monitor picker (wlr-randr) with double click, the recorder's audio switches saved to ~/.cache/screenrecord_audio, a running recording stops instead; same scripts
- [x] Polkit agent + dialog (PolkitState/PolkitOsd and quickshell's PolkitAgent): registers as the session's agent on the system bus (libdbus), queues BeginAuthentication, runs the PAM conversation through polkit 128's helper socket like libpolkit-agent-1, retries after a wrong password, Esc cancels, polkitd's CancelAuthentication honoured. The dialog matches a QML mock at 99.9%; registration is checked; **the conversation and success path are not tested yet** - that needs the live test (never trigger pkexec on the live session for tests)
- [x] Clipboard history (ClipboardState/ClipboardOsd): cliphist list, search line with TextInput editing, list with keyboard/wheel/hover/click, image thumbnails and preview decoded off the main thread at QML's sourceSize, pick/delete/wipe through clip.sh; 99.9% within 8 levels in the tested states
- [ ] Wallpaper carousel + reveal, overview
- [ ] Switch-over: keybinds, scripts, installer build step

## Testing

Parity is checked in a headless mango sandbox, against quickshell itself (not
`grabToImage` or the `qml` runtime, which turn subpixel text off):
`rust-bar textref SPEC OUT.png` renders text rows for diffing; the sandbox
scripts live outside the repo (`~/.cache/bar-ab`). First strip measurement in
that sandbox: QML bar 77 MB PSS / 57 MB private; this bar 19 MB / 7 MB, idle
CPU 0.
