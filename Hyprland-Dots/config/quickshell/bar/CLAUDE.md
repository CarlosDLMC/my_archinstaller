# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Quickshell configuration for a Hyprland Wayland desktop bar. The config uses QML with Quickshell-specific modules, organized into modular components.

## Commands

```bash
# Restart quickshell to apply changes
pkill -x quickshell; sleep 0.5; quickshell &

# Test weather script
~/.config/quickshell/bar/scripts/weather-fetch.sh | jq -r '.text'
```

## Architecture

### File Structure

```
shell.qml           # Main entry point, assembles the bar layout
Theme.qml           # Singleton with colors, fonts, and theme settings
qmldir              # QML module definition for the singletons
Monitors.qml        # Singleton: connected monitors, shared by the capture dialogs
RecordState.qml     # Singleton: screen-recording dialog state + global shortcuts
ShotState.qml       # Singleton: screenshot dialog state + global shortcut
SystemStats.qml     # Singleton: CPU usage/temp + memory, read from /proc via FileView
AgentUsage.qml      # Singleton: Claude Code allowance + token stats
NightLight.qml      # Singleton: night-light state, watched off Hyprsunset.sh's state file
components/         # Modular widget components
  ├── DropdownWidget.qml   # Base component for click-to-open dropdown widgets (notch design)
  ├── AudioPanel.qml       # Audio card body: output/input device + level, per-app levels
  ├── NetworkPanel.qml     # Network card body: link, connection, traffic, DNS, speed test, share QR
  ├── AgentWidget.qml      # Claude Code usage: session % in the bar, card on click
  ├── AgentPanel.qml       # Agents card body: plan, allowance meters, tokens by day/model
  ├── VolumeSlider.qml     # Draggable level track, shared by every row of the audio card
  ├── WeatherStatItem.qml  # Reusable stat row for weather popup
  ├── WorkspaceBar.qml     # Hyprland workspaces with app icons (pill-shaped)
  ├── WindowInfo.qml       # Current window title
  ├── CenterInfo.qml       # Date/DND/weather with click popup showing detailed forecast
  ├── CpuWidget.qml        # CPU usage + temperature (renders SystemStats)
  ├── MemoryWidget.qml     # Memory in use (renders SystemStats)
  ├── DiskWidget.qml       # Disk usage percentage
  ├── VolumeWidget.qml     # Volume with mute/sink detection (speaker/headphone/bluetooth/hdmi)
  ├── BatteryWidget.qml    # Battery level with charging status
  ├── WifiWidget.qml       # WiFi status with network speeds (extends DropdownWidget)
  ├── BluetoothWidget.qml  # Bluetooth status with dropdown (extends DropdownWidget)
  ├── PowerProfileWidget.qml # Power profile selector (extends DropdownWidget)
  ├── PowerWidget.qml      # Power menu: lock, logout, reboot, shutdown (extends DropdownWidget)
  ├── RecordOsd.qml        # Screen-recording dialog (centred box, big buttons, audio toggles)
  ├── ShotOsd.qml          # Screenshot dialog (same box, no audio row)
  ├── BigButton.qml        # Big icon+label button, shared by both capture dialogs
  ├── ToggleRow.qml        # Labelled switch, shared by both capture dialogs
  ├── SlackWidget.qml      # Slack indicator, click to focus app
  ├── WhatsAppWidget.qml   # WhatsApp indicator, click to focus app
  └── Separator.qml        # Visual separator line
```

### Key Components

- **Theme.qml**: Singleton pragma provides `Theme.colBg`, `Theme.fontSize`, etc. to all components.
  Colours are **not** hardcoded here — see Theming below.
- **WorkspaceBar.qml**: Pill-shaped workspace indicators with numbers and deduplicated app icons (max 3). Hover effects and active state highlighting
- **RecordOsd.qml**: Screen-recording dialog on `$mainMod SHIFT R` (global shortcut
  `quickshell:recordMenu`). Two big mode buttons (full screen / region), a monitor
  picker shown only when more than one is connected, and switches for system audio
  and mic. State lives in `RecordState.qml`; the recording itself is done by
  `~/.config/hypr/scripts/ScreenRecord.sh`, so the dialog and the bare keybinds
  share one code path. Keys: `F` full screen, `R` region, `W` window, `S`/`M` audio
  toggles, `Esc` dismiss. Pressing the shortcut while recording stops it.
- **ShotOsd.qml**: Screenshot dialog on `$mainMod Print` (global shortcut
  `quickshell:shotMenu`). Same box as RecordOsd without the audio row. State in
  `ShotState.qml`, capture by `~/.config/hypr/scripts/ScreenShot.sh`. Keys: `F`
  full screen, `R` region, `W` active window, `E` annotate (satty), `Esc` dismiss.
  `ShotState.settleMs` (300ms) waits for the overlay to leave the screen before
  grim runs, otherwise the shot contains the dialog and its dim — it must stay
  comfortably above the 160ms fade.
- **Monitors.qml**: Shared monitor list (`list`, `multiple`, `focusedName()`,
  `resolveTarget()`). `resolveTarget` keeps a remembered monitor while it is still
  plugged in and falls back to the focused one, so neither dialog can aim at a
  monitor that has been unplugged.

  Note: both capture tools **must** be given an explicit output. wf-recorder with
  no `-o` on a multi-monitor setup falls back to an interactive stdin prompt and
  silently records the laptop panel; grim with no `-o` captures the whole layout
  (both screens stitched together with the dead space between them).
- **SystemStats.qml**: CPU usage, CPU temperature and memory in use, sampled once
  every 5s for the whole shell. `CpuWidget` and `MemoryWidget` are pure renderers
  over it. Reads `/proc/stat`, `/proc/meminfo` and the hwmon sensor with `FileView`,
  so it costs no subprocesses at all; the sensor path is resolved once at startup
  rather than probed on every tick.
- **NightLight.qml**: night-light state and toggle. `Hyprsunset.sh` records what it
  did in `~/.cache/.hyprsunset_state` and rewrites it in place, so a `FileView` with
  `watchChanges` sees every change instantly - whether it came from the bar or from
  `SUPER + N`. A 60s check against `pgrep` runs only while the file says "on", to
  catch hyprsunset having died and left the file lying.
- **AgentWidget.qml / AgentPanel.qml / AgentUsage.qml**: Claude Code usage.
  The bar shows the share of the 5-hour session spent (the number that says
  whether you are about to be cut off); the card adds the plan, weekly and
  per-model allowances with reset countdowns, tokens by day for the last week,
  and tokens by model. Ported from Omarchy's agents plugin, reduced to the one
  agent this machine runs.

  `AgentUsage` is a **singleton** for the same reason `SystemStats` is: the bar
  is instantiated per screen, and this polls a network endpoint - two monitors
  would otherwise mean two calls to Anthropic every five minutes for the same
  number. It runs two cadences: the OAuth probe alone every 5 minutes (cheap,
  always, because the bar readout needs it), and the probe plus a transcript
  scan only while a card is open.

  `scripts/agent-usage.py` is the collector. The access token comes from the
  Claude CLI's own store and goes exactly one place - the Authorization header
  of Anthropic's usage endpoint; it is never printed or cached, and only the
  plan label reaches the output. The transcript scan caches **per file**, keyed
  by (mtime, size): a cold scan reads 160MB and costs ~1.3s of CPU, a repeat
  costs ~0.1s because only the session you are in has changed.

  The widget hides on `installed` - whether `~/.claude` exists at all - and not
  on whether a probe returned anything. Those were conflated at first, and the
  whole widget vanished from the bar the first time the usage endpoint rate
  limited us. The endpoint does rate limit, returns no useful headers (only a
  `Retry-After: 0` that is wrong), and a refusal can last many minutes, so:
  the last good reading is cached to disk and shown with its age, retries back
  off 60s -> 300s, and the icon's colour is **fixed** - it never signals state.
- **CenterInfo.qml**: DND toggle + date + weather. Click shows popup with notch design connecting to bar. Displays location, temperature, condition, feels-like, min/max, and hourly rain forecast bars. Weather icon/temp colored by temperature. Caches weather data for offline use.
- **CpuWidget.qml / MemoryWidget.qml / DiskWidget.qml**: Simple percentage displays with themed colors
- **VolumeWidget.qml**: Volume with mute detection and audio sink icons
  (speaker/headphone/bluetooth/HDMI). Left-click mutes, wheel adjusts,
  **right-click opens the audio card** (`AudioPanel.qml`) - output device and
  level, input device and level, and a level per running application. It reads
  `Quickshell.Services.Pipewire` directly, so there is nothing to poll and no
  subprocess; it replaced launching pavucontrol.

  Two things in there are load-bearing and easy to undo by accident. The
  Repeaters are fed *copies* of the PipeWire lists, refreshed through a 75ms
  debounce and only while the card is open: PipeWire can remove a node while
  Quickshell is still dispatching the removal, and rebuilding a Repeater from
  inside that signal crashes the PipeWire service. And `node.properties` is only
  read once the node reports `ready` (see `nodeProps()`), because it is not valid
  before the node is bound. The card's height comes from what the body measured,
  not from arithmetic over row counts - text height follows the font's line
  metrics, not the pixelSize, so counting rows clips the last one
- **BatteryWidget.qml**: Battery level with charging status and tiered icons
- **WifiWidget.qml**: WiFi status. **Left-click** opens the network list (scan,
  connect, password entry, disconnect); **right-click** opens the details card
  (`NetworkPanel.qml`) - link quality, IP/gateway/DNS, live throughput and
  latency, a DNS provider picker, the radio toggle, and two actions: a speed
  test and a share-QR for the current network. It replaced launching
  `nm-connection-editor`, which is still installed for the things the card
  deliberately leaves out - per-profile IP settings, 802.1X, VPN and wired
  profiles, and **managing saved networks**, which was tried in the card and
  removed: ten remembered profiles was more than half its height.

  Facts are laid out as label/value pairs, two to a row, in a
  `GridLayout { columns: 4 }` (the shape DHH uses). One pair per row made a
  very tall card for mostly short values. The SSID spans the full width and
  saved/long names elide in the **middle**, because several of these networks
  are one router with different suffixes and right-eliding rendered them
  identically.

  The speed test and the QR replace the card's body rather than opening
  windows of their own (DHH gives each a centred card, but this bar's cards
  are dropdowns and a second layer surface would fight the focus grab).
  Closing the card stops a running speed test - it saturates the link with
  eight parallel streams, so leaving it running would be a real cost.

  Both views share one popup, switched by `panelMode`, so there is still one
  notch card and one focus grab. The right-click path sets `dropdownOpen`
  directly rather than emitting `opened()`, because that signal kicks off a
  Wi-Fi rescan the details view neither shows nor needs.

  Every poll in the card is gated on it being open, and its data comes from
  `scripts/network-status.sh`. Note that script reports the **radio** and the
  **default route separately**: with WireGuard up the route interface is the
  tunnel, so keying the radio details off it (as the original did) silently
  dropped SSID, signal and rate for as long as the VPN was connected
- **BluetoothWidget.qml**: Bluetooth status with dropdown. Icon turns green when device connected
- **Widget components**: Each has its own Process components for data fetching and PopupWindow for dropdowns

### Theming

The bar is **monochrome by design**. The desktop it sits on is a two-hue
composition (warm near-black + crimson), so any stray hue in the bar becomes
the loudest thing on screen. Widgets are distinguished by *brightness* and by
their text label, never by hue.

Colour flows one way:

```
wallpaper
  -> wallust  (~/.config/wallust/templates/bar-colors.json)
  -> ~/.config/quickshell/bar/wallust-colors.json   (generated, gitignored)
  -> Theme.qml  (FileView + watchChanges, hot-reloads)
  -> components use Theme.col*
```

Change the wallpaper and the bar recolours itself; no restart, no edits.
`Theme.qml` holds the sovietpunk palette as *fallbacks* only, used when the
generated file is missing or malformed (it logs a warning and keeps the last
good palette rather than rendering blank).

**Never put a hex literal in a component.** Use a semantic role:

| Role | Use for |
|---|---|
| `colValue` / `colFg` | numbers, primary text |
| `colLabel` / `colDim` | `CPU`, `MEM` — the noun, and secondary info |
| `colBright` | emphasis (active workspace, hot temp) |
| `colMuted` | separators, inactive, "off" states |
| `colAccent` | active / connected / on |
| `colAlert` | **needs attention**: muted, low battery, DND on, VPN down, storm |
| `colWarn` | state unknown or degraded (e.g. `dunstctl` failed) |
| `colOnAlert` | text sitting on an alert-filled shape |

`colAlert` is the only real hue in the bar. Spend it only on states worth
looking at — if everything is an alert, nothing is.

Ordinal data (temperature, load) is encoded as a brightness ramp, with
`colAlert` reserved for genuine extremes. See `getTempColor()` in
`CenterInfo.qml`.

### Key Patterns

**The bar is instantiated once per screen.** `shell.qml` wraps it in
`Variants { model: Quickshell.screens }`, so anything a widget polls, it polls N
times on an N-monitor machine. Data that is the same on every screen belongs in a
singleton that the widgets render; only the rendering should be per-screen. See
`SystemStats.qml`.

**Prefer, in this order:**

1. **A Hyprland event payload.** `Hyprland.onRawEvent` carries the data with the
   event - `activewindow` is `"<class>,<title>"`, `windowtitlev2` is
   `"<address>,<title>"`, `activelayout` is `"<device>,<layout>"`. Parse the
   payload; do not shell out to `hyprctl` to re-fetch what you were just handed.
   **Always filter on `event.name` first** - Hyprland fires a great many events
   (ten `activelayout`s per keyboard switch), and an unfiltered handler runs on
   all of them. See `WindowInfo.qml` and `KeyboardLayoutWidget.qml`.
2. **`FileView`**, for anything that lives in a file - `/proc`, `/sys`, and the
   caches under `~/.cache/quickshell`. With `watchChanges: true` it updates on
   inotify, which is both cheaper and faster than polling an mtime by hand. Set
   `printErrors: false` where a missing file is a normal state. `blockLoading:
   true` makes `reload()` + `text()` synchronous, which is what you want for
   `/proc`.
3. **A D-Bus / netlink monitor process** (`nmcli monitor`, `dbus-monitor`,
   `udevadm monitor`), for hardware state with no file to watch. Gate these on the
   hardware actually existing - see below.
4. **A `Process` on a timer**, only when none of the above applies. Pick the
   interval from how often the value really changes: a clock showing `HH:MM`
   needs a minute, not a second.

- **Hiding is not stopping**: `visible: false` drops a widget from the layout but
  leaves its timers and monitor processes running. Every widget that hides itself
  on absent hardware (`hasWifi`, `hasBattery`, `hasAdapter`) must also gate its
  timers and processes on the same property, or a desktop pays for a wifi scanner
  it cannot use.
- **Process + SplitParser**: how the remaining shell-command data is fetched
- **Theme singleton**: Components access theme via `import ".."` then use `Theme.colFg`, `Theme.fontSize`, etc.
- **PopupWindows**: Dropdowns use `PopupWindow` with `visible` bound to `*DropdownOpen` properties
- **HyprlandFocusGrab**: Used to close popups when clicking outside. Requires `import Quickshell.Hyprland`. Example:
  ```qml
  HyprlandFocusGrab {
      id: myFocusGrab
      windows: [myPopup]
      active: myDropdownOpen
      onCleared: myDropdownOpen = false
  }
  ```
- **Nerd Font Icons**: Uses Material Design Icons range (nf-md-*) which render correctly in Qt. Other ranges may not work.

### External Dependencies

- `nmcli` for WiFi scanning/connecting
- `bluetoothctl` for Bluetooth management
- `powerprofilesctl` for power profile management
- `dunstctl` for DND (Do Not Disturb) toggle
- `wpctl` / `pactl` for volume control and audio sink detection
- `hyprctl` for workspace/window data
- `jq` for JSON parsing
- `scripts/weather-fetch.sh` -> `scripts/weather-location.py` for weather data (outputs JSON the bar parses)
- `scripts/network-speedtest.sh <down|up> [seconds]` prints one Mb/s sample per second.
  Saturates the link with 8 parallel curl workers against fast.com's CDN endpoints and
  measures the result off `/sys` byte counters. Unlike the upstream version it **stops on
  its own** rather than running until killed. The fast.com token in it is public (it
  base64-decodes to a keyboard mash), identifies the fast.com app rather than the user,
  and is overridable with `FAST_TOKEN`
- `scripts/network-qr.sh` emits `meta` + a 0/1 matrix for a Wi-Fi join QR, drawn by the card
  as plain rectangles. Needs `qrencode` (now in `01-hypr-pkgs.sh`); without it, it prints one
  `error` line the card shows instead of failing silently
- `scripts/network-status.sh` for the network card's status (tab-separated key/value lines).
  Uses `nmcli` for the radio details rather than `iw`, which is **not** a dependency of this
  repo and is not installed - the upstream version read the radio through `iw` and so produced
  nothing at all here. `iw` is consulted only for the dBm reading, when it happens to exist

### Adding New Widgets

1. Create a new component in `components/` (e.g., `MyWidget.qml`)
2. Add Process components for data fetching with SplitParser
3. Use `import ".."` to access Theme singleton
4. Add the component to shell.qml's RowLayout
5. For dropdowns, extend `DropdownWidget`:
   ```qml
   DropdownWidget {
       id: myWidget
       popupWidth: 200
       popupHeight: 150

       // Icon content (default property - what shows in bar)
       Text {
           anchors.verticalCenter: parent.verticalCenter
           text: "󰤨"
           color: Theme.colFg
       }

       // Popup content (use myWidget.* for property references)
       popupContent: Component {
           Column {
               Text { text: myWidget.someProperty }
           }
       }

       // Optional: React to dropdown opening
       onOpened: someProcess.running = true
   }
   ```
   The base component handles: barWindow connection, dropdownOpen state, MouseArea toggle, HyprlandFocusGrab, and PopupWindow with notch design (concave corners connecting narrow stem to wider body). Popup is automatically centered on the icon.

   `triggerButton` picks which button opens the card (left by default).
   Whichever buttons are *not* the trigger arrive as `onOtherClicked(button)`,
   and the wheel as `onWheelMoved(deltaY)`, so a widget keeps its own gestures
   instead of having them swallowed by the card's hit area - that is how
   `VolumeWidget` opens on right-click while left-click still mutes.
- no need to restart quickshell, it hot reloads the config on save.