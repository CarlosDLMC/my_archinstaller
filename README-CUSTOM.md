# Custom Arch-Hyprland Installation

This is a customized version of the Arch-Hyprland installation that includes all your personal configurations and preferences.

## Features

### Custom Quickshell Bar
- **Event-based monitoring** (no constant polling) for:
  - Volume changes (using `pactl subscribe`)
  - Network status (using `nmcli monitor`)
  - Battery status (using `udevadm monitor`)
  - Window changes (Hyprland events)
  - Keyboard layout changes (Hyprland events)

- **Widgets included:**
  - Workspace indicators (numbers only, simplified)
  - Window title
  - Date with weather information
  - CPU, Memory (in GB format), Disk usage
  - Volume (static icon, event-based updates)
  - Battery (with charging status, event-based updates)
  - WiFi (event-based updates)
  - Bluetooth
  - Night Light toggle (hyprsunset)
  - Keyboard Layout switcher (US/ES/RU)
  - Power profile selector
  - Power menu

- **Removed widgets:**
  - Slack widget
  - WhatsApp widget

### Configuration Changes
- **Terminal:** foot (replaced kitty)
- **Bar:** Quickshell (replaced waybar)
- **Clock:** 24-hour format (HH:mm)
- **Date:** dd.MM.yyyy format
- **Font size:** 20px (increased from 15px)
- **Memory display:** Shows GB usage instead of percentage
- **Keyboard layouts:** US, ES, RU with SUPER+SPACE switching

### Installed Packages
- `quickshell` - Custom bar
- `foot` - Terminal emulator
- `hyprsunset` - Night light functionality
- `wireguard-tools` - VPN support
- `inotify-tools` - File system monitoring
- All other Hyprland essentials (wallust, swaync, rofi, wlogout, etc.)

## Installation

### IMPORTANT: Before Installing

**Make sure you copy the ENTIRE Arch-Hyprland directory to the new computer!**

The installation needs these subdirectories:
- `Hyprland-Dots/` - Contains all your custom configurations
- `install-scripts/` - Installation scripts
- `Install-Logs/` - Will store installation logs

**How to transfer:**

1. On your current computer:
   ```bash
   # Verify the directory is complete
   ls ~/Documents/Arch-Hyprland/Hyprland-Dots/

   # You should see: config/, copy.sh, .zshrc, pokefetch_perfect, etc.
   ```

2. Transfer to new computer (use USB, rsync, or scp):
   ```bash
   # Example with USB
   cp -r ~/Documents/Arch-Hyprland /path/to/usb/

   # Example with rsync (if computers are networked)
   rsync -av ~/Documents/Arch-Hyprland/ newcomputer:~/Documents/Arch-Hyprland/
   ```

3. On the new computer, verify everything was copied:
   ```bash
   cd ~/Documents/Arch-Hyprland
   ls -la Hyprland-Dots/
   # Should show config/, copy.sh, .zshrc, pokefetch_perfect, .local/, etc.
   ```

### Quick Install

Run the installation with the custom preset:

```bash
cd ~/Documents/Arch-Hyprland
chmod +x install.sh
./install.sh --preset custom-preset.conf
```

### Manual Install

If you want to choose options manually:

```bash
chmod +x install.sh
./install.sh
```

**Important:** Make sure to select these options:
- ✅ quickshell
- ✅ dots (Download and install pre-configured Hyprland dotfiles)
- ✅ gtk_themes (for Dark/Light mode)
- ✅ thunar (file manager)
- ✅ bluetooth (if needed)
- ✅ xdph (for screen sharing)
- ✅ zsh (optional but recommended)

### Post-Installation

After installation:

1. **Reboot your system** (highly recommended)

2. **Start Hyprland:**
   - If SDDM is installed, it will start automatically
   - Otherwise, type `Hyprland` at the TTY

3. **Keyboard layout switching:**
   - Press `SUPER + SPACE` to cycle through layouts (US → ES → RU)
   - The bar will show the current layout

4. **Night light toggle:**
   - Click the sun icon in the bar to toggle night light

5. **Volume control:**
   - Use volume keys on keyboard
   - Click volume icon to open pavucontrol

## Customizations Made

This installation includes all the customizations from your current system:

1. **Removed waybar** completely
2. **Event-based monitoring** instead of polling (battery, volume, WiFi, etc.)
3. **Custom quickshell bar** with simplified workspace indicators
4. **Night light toggle** with hyprsunset
5. **Keyboard layout switcher** in the bar
6. **24-hour clock** and custom date format
7. **Memory display in GB** instead of percentage
8. **Static volume icon** (doesn't disappear or change)
9. **Fast battery status updates** (no 30-second lag)
10. **All configuration files** from ~/.config/

## Directory Structure

```
Arch-Hyprland/
├── install.sh                    # Main installation script
├── custom-preset.conf            # Preset with your configurations
├── Hyprland-Dots/                # Your customized dotfiles
│   ├── copy.sh                   # Script to deploy dotfiles
│   ├── config/                   # All config directories
│   │   ├── hypr/                 # Hyprland config with custom keybinds
│   │   ├── quickshell/           # Custom bar configuration
│   │   ├── foot/                 # Terminal config
│   │   ├── wlogout/              # Power menu
│   │   ├── wallust/              # Color schemes
│   │   └── ...                   # All other configs
│   ├── .zshrc                    # Shell configuration
│   └── ...
├── install-scripts/              # Individual installation scripts
└── README-CUSTOM.md              # This file
```

## Notes

- The installation will backup your existing configs to `~/.config/<app>.backup`
- All event-based monitoring reduces CPU usage significantly
- VPN selector and NAS daemon configurations are preserved
- Keyboard layout changes are instant (event-based, no polling)

## Troubleshooting

### If you see the "Warning: You are using an autogenerated config" message:

This means the custom dotfiles weren't copied properly. **Run the diagnostic script first:**

```bash
cd ~/Documents/Arch-Hyprland
./diagnose.sh
```

The diagnostic will tell you exactly what's missing and how to fix it.

### Quick Fix - Manually copy dotfiles:

```bash
cd ~/Documents/Arch-Hyprland/Hyprland-Dots
chmod +x copy.sh
./copy.sh
```

Then restart Hyprland:
```bash
hyprctl dispatch exit
```

### If packages are missing:

Check which packages are missing:
```bash
./diagnose.sh
```

Install any missing packages with yay:
```bash
yay -S <package-name>
```

### Other common issues:

1. **Check if quickshell is running:**
   ```bash
   pgrep quickshell
   ```

2. **Restart quickshell:**
   ```bash
   pkill quickshell && sleep 0.5 && quickshell &
   ```

3. **Check Hyprland config:**
   ```bash
   cat ~/.config/hypr/configs/Startup_Apps.conf
   ```

4. **Check logs:**
   ```bash
   journalctl -xe
   ```

### If keybindings don't work:

This means Hyprland is using the default config. Follow the "Quick Fix" above to copy the custom dotfiles.

Enjoy your customized Hyprland setup!
