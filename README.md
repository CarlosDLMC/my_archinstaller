# My Arch Installer

Automated Arch Linux installation with custom Hyprland setup.
Some things such as the calendar starting on Sunday or Monday, the 24 or 12 hour time etc are decided by the locales.
Please select a locale that suits you 

## Features

- **Custom Quickshell Bar** with event-based monitoring (no polling)
- **Complete Hyprland Configuration** with custom keybindings and layouts
- **Keyboard Layout Switcher** (US/ES/RU) with SUPER+SPACE
- **Night Light Toggle** with hyprsunset
- **VPN Selector** with WireGuard configurations
- **Custom Terminal** setup with pokefetch and zsh
- **ly Display Manager** (lightweight TUI login screen with large font)
- **Soviet TUI Lock Screen** matching ly, auto-sized to any display (720p → 4K)
- **Offline Speech-to-Text** with Handy (toggle via SUPER + CTRL + F8)
- **Whole-Workspace Move** with SUPER + ALT + number, rebuilding the tiling layout window for window
- **All Essential Packages** pre-configured

## Quick Install (Fresh Arch System)

### Prerequisites

- Fresh Arch Linux installation with base system
- Internet connection
- git installed (or will be installed automatically)

### Installation Steps

1. **Clone this repository:**
   ```bash
   cd ~/Documents
   git clone https://github.com/CarlosDLMC/my_archinstaller.git
   cd my_archinstaller
   ```

2. **Run the installation:**
   ```bash
   chmod +x install.sh
   ./install.sh --preset custom-preset.conf
   ```

   With `--preset`, the installer runs **non-interactively**: the component
   menu is skipped and the selection comes from `custom-preset.conf`. Run
   `./install.sh` with no arguments to pick components from a menu instead.

3. **Reboot when prompted:**
   ```bash
   # The script will ask if you want to reboot
   # Answer 'y' to reboot now
   ```

4. **Recreate your machine-local secrets:**
   ```bash
   mkdir -p ~/.config/zsh
   chmod 600 ~/.config/zsh/secrets.zsh   # after creating it
   ```

   API keys and tokens are deliberately **not** in this repo. `.zshrc` sources
   `~/.config/zsh/secrets.zsh` if it exists and starts fine without it, so the
   shell will work immediately - but anything needing a key will not. Add the
   exports you use, for example:

   ```bash
   export ANTHROPIC_API_KEY="..."
   export CLOUDFLARE_EMAIL="..."
   export CLOUDFLARE_API_KEY="..."
   export BITBUCKET_TOKEN="..."
   ```

5. **Optional per-machine tooling.** The installer does not install `fnm`,
   `uv`, `rustup` or Homebrew. `.zshrc` guards each of their hooks, so their
   absence is silent - install whichever you need.

6. **Done!** After reboot, log in through ly and enjoy your custom Hyprland setup.

## What Gets Installed

### Core System
- Hyprland, hypridle, hyprlock
- ly display manager with large font
- PipeWire audio
- NetworkManager

### Desktop Environment
- Quickshell (custom bar)
- foot (terminal)
- rofi (launcher)
- wlogout (power menu)
- swaync (notifications)
- awww (wallpaper daemon)
- wallust (color scheme generator)

### Custom Features
- Keyboard layouts: US, ES, RU
- Night light with hyprsunset
- VPN selector for WireGuard
- Custom pokefetch terminal greeting
- Event-based system monitoring
- Battery, WiFi, Bluetooth, Volume widgets
- Whole-workspace move that preserves the dwindle layout

### Applications
- LibreWolf (browser)
- Thunar (file manager)
- btop, cava, fastfetch
- mpv, pavucontrol
- swappy (screenshot editor)
- Handy (offline speech-to-text — Parakeet V3, auto-detects 25 languages)

## Configuration

All configurations are stored in `Hyprland-Dots/config/` and will be copied to `~/.config/` during installation.

### Key Bindings (Some Important Ones)

- `SUPER + Return` - Open terminal (foot)
- `SUPER + Q` - Close active window
- `SUPER + SHIFT + Q` - Terminate active process
- `SUPER + M` - Exit Hyprland
- `SUPER + SPACE` - Switch keyboard layout (US → ES → RU)
- `SUPER + SHIFT + SPACE` - Float current window
- `SUPER + CTRL + ALT + B` - Toggle quickshell bar
- `SUPER + CTRL + F8` - Handy: toggle speech-to-text (press once to start recording, press again to stop and transcribe into the focused field)
- `SUPER + ALT + <1-0>` - Move *every* window of the current workspace to that workspace, keeping the tiling layout intact (`SUPER + CTRL + <1-0>` still moves one window silently)
- `CTRL + ALT + L` - Lock screen (Soviet TUI)
- `CTRL + ALT + P` - Power menu (wlogout)

See `Hyprland-Dots/config/hypr/configs/Keybinds.conf` for all keybindings.

### Speech-to-Text (Handy)

Handy is offline speech-to-text — no audio leaves your machine. `wtype` injects the transcription into whatever window has focus.

**Workflow:**
1. Focus a text field.
2. Press `SUPER + CTRL + F8` — a notification confirms recording started.
3. Speak.
4. Press `SUPER + CTRL + F8` again — recording stops, transcription runs, text is typed into the field.

**First login on a fresh install:**
- Handy opens automatically so you can pick a model. Choose **Parakeet V3** (CPU-friendly, auto-detects 25 languages including English, Spanish, German, Russian) and let it download (~30s).
- **Ignore the "Shortcut" field inside Handy's UI** — Wayland blocks apps from registering global shortcuts, so it doesn't work. The Hyprland keybind in `UserKeybinds.conf` is what actually fires the toggle.
- Once you've selected a model, Handy starts hidden on every subsequent login. The keybind keeps working in the background.

This behavior is implemented by `~/.config/hypr/UserScripts/handy-start.sh`, which opens Handy visibly while `selected_model` is empty and switches to `--start-hidden` once it's set.

### Lock Screen (Soviet TUI)

The lock screen is built to match the **ly** login screen, so logging in and unlocking
look like the same machine: pure black, a single monospace face, a block-glyph clock,
and Russian labels (`ГРАЖДАНИН`, `КОД ДОСТУПА`). A wrong password gives ly's own
`НЕВЕРНЫЙ КОД ДОСТУПА`.

Everything sits in one bordered TUI panel: date, kernel, uptime, load, memory, AC state,
every battery pack, keyboard layout, and weather.

**Weather comes from the bar**, `~/.cache/quickshell/weather.json`, so the lock screen
and the bar always show the same reading. If that file is missing (a machine without
quickshell) it falls back to the legacy `~/.cache/.weather_cache`. Either way, a reading
older than two hours is labelled with its age in the section header
(`╠═ ПОГОДА · 3 Ч НАЗАД ═╣`) rather than shown as if it were current — weather fetchers
here have broken silently before.

**Keys and mouse:**
- `ENTER` submit · `ESC` or `CTRL + U` clear the password
- `ALT + SHIFT` or `SUPER + SPACE` — switch keyboard layout (these work while locked)
- Click the `РАСКЛАДКА` value — also switches layout

**Works on any display.** `hyprlock.conf` contains no geometry at all — it sources
`hyprlock-monitors.conf`, regenerated before every lock by `scripts/SovietLockGen.py`
from `hyprctl monitors`. It emits one widget set *per attached monitor*, so a 1080p
laptop and a 2K external are each sized correctly at the same time. Chosen font size:

- `1280x720` → 8
- `1920x1080` → 13
- `2560x1440` → 18
- `3840x2160` → 27

Verified by rendering at all four. HiDPI scaling, ultrawide and rotated panels are
handled too (a 4K at scale 2 is laid out as 1080p, which is what hyprlock actually uses).

**Going idle does not lock.** The lock screen is only ever raised deliberately, with
`CTRL + ALT + L`. hypridle's screenlock listener is commented out in `hypridle.conf`;
uncomment it to get a 10-minute auto-lock back. Idle still blanks the display after
10.5 minutes — it just leaves the session unlocked. The session is also locked before
suspend (`before_sleep_cmd`), which is separate from idle.

**Stays lit while plugged in.** When you *have* locked, `scripts/IdleDpms.sh` skips the
idle blank while locked *and* on AC, so the panel stays readable at the desk but still
blanks on battery.

**Files** (in `~/.config/hypr/`, from `Hyprland-Dots/config/hypr/`):
- `hyprlock.conf` — colours and background only
- `hyprlock-monitors.conf` — generated, do not edit
- `scripts/SovietLock.py` — draws the panel, date, footer
- `scripts/SovietClock.sh` — draws the block-glyph clock
- `scripts/SovietLockGen.py` — sizes the widgets per monitor
- `scripts/IdleDpms.sh` — idle blanking policy
- `scripts/LockRun.sh` — starts hyprlock, logs its output and exit code
- `hypridle.conf` — calls `LockRun.sh` and `IdleDpms.sh`

The clock is shell rather than another `SovietLock.py` mode because it is the one
widget hyprlock re-runs every second per monitor, and Python's startup dominated
its cost: ~45 ms a run became ~5 ms. Measured end-to-end as hyprlock's own CPU
over a 60s lock — which includes re-reading and re-rendering the label, not just
running the command — that is **7.4% → 2.4% of one core per monitor**, so a
two-monitor lock costs ~4.7% instead of ~14.8%. With every widget static hyprlock
uses no measurable CPU at all, so the clock is the whole cost of a locked screen.
Most of what remains is hyprlock's own per-tick work (~18 ms), not the script
(~5 ms) — dropping seconds from the clock is the only way to cut it much further.
Output is byte-identical to the Python version it replaced.

**Customizing:** panel contents and wording in `SovietLock.py`; colours via `$ink` /
`$dim` in `hyprlock.conf`; sizing via `HEIGHT_BUDGET` / `WIDTH_BUDGET` in
`SovietLockGen.py`. Set `hide_cursor = true` for a keyboard-only, ly-pure screen
(layout switching still works from the keyboard).

## Customization

### Before Installation

Edit `custom-preset.conf` to enable/disable components:
- ly display manager
- Bluetooth
- GTK themes
- zsh with Oh-My-Zsh
- And more...

### After Installation

All configs are in `~/.config/`. Main files to edit:
- `~/.config/hypr/` - Hyprland configuration
- `~/.config/quickshell/bar/` - Custom bar configuration
- `~/.config/foot/` - Terminal configuration
- `~/.zshrc` - Shell configuration

## Troubleshooting

### If you see "Warning: You are using an autogenerated config"

This means the custom dotfiles weren't copied. Run the diagnostic:

```bash
cd ~/Documents/my_archinstaller
./diagnose.sh
```

The diagnostic will tell you exactly what's wrong and how to fix it.

### Quick Fix

If dotfiles weren't copied:

```bash
cd ~/Documents/my_archinstaller/Hyprland-Dots
./copy.sh
hyprctl dispatch exit  # Restart Hyprland
```

### Check Installation Logs

If something fails during installation:

```bash
ls ~/Documents/my_archinstaller/Install-Logs/
cat ~/Documents/my_archinstaller/Install-Logs/install-*.log
```

## Manual Installation (Without Preset)

If you want to select options manually:

```bash
chmod +x install.sh
./install.sh
```

**Important:** Make sure to select:
- ✅ quickshell
- ✅ dots (Download and install pre-configured Hyprland dotfiles)
- ✅ ly (lightweight TUI display manager)
- ✅ gtk_themes (for Dark/Light mode)
- ✅ bluetooth (if you need it)
- ✅ xdph (for screen sharing)
- ✅ handy (offline speech-to-text, SUPER + CTRL + F8)

## Verification

After installation, verify everything was installed correctly:

```bash
cd ~/Documents/my_archinstaller
./verify-before-transfer.sh
```

## Notes

- The installation will backup existing configs to `~/.config/<app>.backup`
- Event-based monitoring reduces CPU usage significantly
- All scripts are logged to `Install-Logs/`
- First boot runs `initial-boot.sh` to set up themes and wallpapers

## Credits

Based on [JaKooLit's Arch-Hyprland](https://github.com/JaKooLit/Arch-Hyprland) with extensive customizations.

## License

See LICENSE.md file.
