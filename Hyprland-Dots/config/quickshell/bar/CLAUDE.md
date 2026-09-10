# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Quickshell configuration for a Hyprland Wayland desktop bar. The config uses QML with Quickshell-specific modules, organized into modular components.

## Commands

```bash
# Restart quickshell to apply changes
pkill -x quickshell; sleep 0.5; quickshell &

# Test weather script
~/.config/quickshell/scripts/weather.py | jq -r '.text'
```

## Architecture

### File Structure

```
shell.qml           # Main entry point, assembles the bar layout
Theme.qml           # Singleton with colors, fonts, and theme settings
qmldir              # QML module definition for Theme singleton
components/         # Modular widget components
  ├── DropdownWidget.qml   # Base component for click-to-open dropdown widgets (notch design)
  ├── WeatherStatItem.qml  # Reusable stat row for weather popup
  ├── WorkspaceBar.qml     # Hyprland workspaces with app icons (pill-shaped)
  ├── WindowInfo.qml       # Current window title
  ├── CenterInfo.qml       # Date/DND/weather with click popup showing detailed forecast
  ├── CpuWidget.qml        # CPU usage percentage
  ├── MemoryWidget.qml     # Memory usage percentage
  ├── DiskWidget.qml       # Disk usage percentage
  ├── VolumeWidget.qml     # Volume with mute/sink detection (speaker/headphone/bluetooth/hdmi)
  ├── BatteryWidget.qml    # Battery level with charging status
  ├── Clock.qml            # Time display
  ├── WifiWidget.qml       # WiFi status with network speeds (extends DropdownWidget)
  ├── BluetoothWidget.qml  # Bluetooth status with dropdown (extends DropdownWidget)
  ├── PowerProfileWidget.qml # Power profile selector (extends DropdownWidget)
  ├── PowerWidget.qml      # Power menu: lock, logout, reboot, shutdown (extends DropdownWidget)
  ├── SlackWidget.qml      # Slack indicator, click to focus app
  ├── WhatsAppWidget.qml   # WhatsApp indicator, click to focus app
  └── Separator.qml        # Visual separator line
```

### Key Components

- **Theme.qml**: Singleton pragma provides `Theme.colBg`, `Theme.fontSize`, etc. to all components.
  Colours are **not** hardcoded here — see Theming below.
- **WorkspaceBar.qml**: Pill-shaped workspace indicators with numbers and deduplicated app icons (max 3). Hover effects and active state highlighting
- **CenterInfo.qml**: DND toggle + date + weather. Click shows popup with notch design connecting to bar. Displays location, temperature, condition, feels-like, min/max, and hourly rain forecast bars. Weather icon/temp colored by temperature. Caches weather data for offline use.
- **CpuWidget.qml / MemoryWidget.qml / DiskWidget.qml**: Simple percentage displays with themed colors
- **VolumeWidget.qml**: Volume with mute detection and audio sink icons (speaker/headphone/bluetooth/HDMI). Click opens pavucontrol
- **BatteryWidget.qml**: Battery level with charging status and tiered icons
- **WifiWidget.qml**: WiFi status with network speed display (upload/download), dropdown for network selection
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

- **Process + SplitParser**: All system data comes from shell commands via `Process` components with `SplitParser` for output
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
- `scripts/weather.py` for weather data (outputs JSON with waybar-compatible format)

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
- no need to restart quickshell, it hot reloads the config on save.