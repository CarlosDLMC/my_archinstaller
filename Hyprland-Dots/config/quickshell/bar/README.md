# Quickshell Bar for Hyprland

A modern, feature-rich status bar for Hyprland built with [Quickshell](https://quickshell.outfoxxed.me/). Features a clean design with notch-style dropdown popups, weather integration, system monitoring, and more.

![Quickshell Bar](https://img.shields.io/badge/Hyprland-Ready-blue)
![QML](https://img.shields.io/badge/Built%20with-QML-green)

## Preview

![Bar Preview](screenshots/bar-preview.png)

## Features

- **Workspaces**: Pill-shaped indicators with workspace numbers and app icons
- **Window Info**: Current window title display
- **Weather Widget**: Click-to-open popup with detailed forecast, temperature coloring, hourly rain predictions, and offline caching
- **System Stats**: CPU, memory, disk usage, volume (with audio sink detection), and battery
- **Network**: WiFi status with real-time upload/download speeds
- **Bluetooth**: Device status with connection indicator
- **Power Profiles**: Quick switching between power modes
- **DND Toggle**: Do Not Disturb mode via dunst (`dunstctl`)
- **Power Menu**: Lock, logout, reboot, and shutdown options
- **Notch Design**: Elegant dropdown popups with concave corner notches connecting to the bar

## Dependencies

- [Quickshell](https://quickshell.outfoxxed.me/) - The shell framework
- [Hyprland](https://hyprland.org/) - Wayland compositor
- `nmcli` - WiFi management
- `bluetoothctl` - Bluetooth management
- `powerprofilesctl` - Power profile switching
- `dunst` / `dunstctl` - Notification daemon with DND support
- `wpctl` / `pactl` - Audio control
- `hyprctl` - Hyprland IPC
- `jq` - JSON parsing
- A [Nerd Font](https://www.nerdfonts.com/) - For icons (Material Design Icons range recommended)

### Included

- `scripts/weather.py` - Weather data script (outputs JSON with waybar-compatible format). Uses weather.com and auto-detects location via IP. Requires `pyquery` (`pip install pyquery`).

## Installation

1. Install Quickshell following the [official guide](https://quickshell.outfoxxed.me/docs/guide/intro.html)

2. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/quickshell-config.git ~/.config/quickshell
   ```

3. Start Quickshell:
   ```bash
   quickshell
   ```

4. (Optional) Add to your Hyprland config to start on login:
   ```ini
   exec-once = quickshell
   ```

## Configuration

### Theme

Edit `Theme.qml` to customize colors, fonts, and sizes:

```qml
pragma Singleton
import QtQuick

QtObject {
    property color colBg: "#1e1e2e"
    property color colFg: "#cdd6f4"
    property color colMuted: "#6c7086"
    // ... more colors

    property int fontSize: 13
    property string fontFamily: "JetBrainsMono Nerd Font"
}
```

### Adding Widgets

See `CLAUDE.md` for detailed documentation on the architecture and how to create new widgets.

## File Structure

```
shell.qml              # Main entry point, assembles the bar and scales it
Theme.qml              # Colour/font theme singleton
LayoutState.qml        # Keyboard-layout MRU state (GNOME-style switching)
qmldir                 # QML module definition
components/
  ├── DropdownWidget.qml     # Base for dropdown widgets (notch design)
  ├── WorkspaceBar.qml       # Workspace indicators ([N] marks the active one)
  ├── WindowInfo.qml         # Active window title
  ├── CenterInfo.qml         # Clock, DND toggle, weather
  ├── CalendarPopup.qml      # Calendar, opened from the clock
  ├── WeatherStatItem.qml    # Stat row inside the weather popup
  ├── CpuWidget.qml          # CPU usage and temperature
  ├── MemoryWidget.qml       # Memory used, in GB
  ├── DiskWidget.qml         # Disk usage (not currently in the bar)
  ├── VolumeWidget.qml       # Volume/mute via Pipewire
  ├── BatteryWidget.qml      # Battery average, per-pack detail in dropdown
  ├── WifiWidget.qml         # WiFi status, scanning and connecting
  ├── BluetoothWidget.qml    # Bluetooth status and device management
  ├── PowerProfileWidget.qml # Power profiles
  ├── NightLightWidget.qml   # hyprsunset toggle
  ├── KeyboardLayoutWidget.qml # Current keyboard layout
  ├── LayoutOsd.qml          # Centred layout-switcher OSD, one per screen
  ├── VpnWidget.qml          # VPN selector; syncs clock and weather
  ├── PowerWidget.qml        # Power menu
  ├── Clock.qml              # Time display
  ├── SlackWidget.qml        # Slack indicator
  ├── WhatsAppWidget.qml     # WhatsApp indicator
  └── Separator.qml          # Pipe divider
scripts/
  ├── weather-fetch.sh       # Picks the city, falls back to IP location
  ├── weather-location.py    # Weather fetch for a named city
  ├── weather.py             # Original IP-based weather fetch
  ├── layouts.py             # Keyboard layout enumeration
  ├── vpn-sync.sh            # Point clock/weather at the VPN exit
  └── vpn-reset.sh           # Restore local timezone and weather
```

## Key Patterns

- **Hot Reload**: Changes are applied automatically on save
- **Process + SplitParser**: Shell commands for data fetching
- **HyprlandFocusGrab**: Click-outside to close popups
- **Notch Design**: Dropdowns use Canvas-drawn shapes with concave corners

## Credits & Inspiration

- **[quickshell-btw](https://github.com/tonybanters/quickshell-btw)** by Tony Banters - Major inspiration for this configuration
- **[Quickshell](https://quickshell.outfoxxed.me/)** - The amazing shell framework by outfoxxed
- **[Hyprland](https://hyprland.org/)** - The dynamic tiling Wayland compositor

## License

MIT License - Feel free to use, modify, and distribute.

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.
