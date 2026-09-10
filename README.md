# My Arch Installer

Automated Arch Linux installation with custom Hyprland setup.

Dates and times run on a Russian time locale (`LC_TIME=ru_RU.UTF-8`), which is
what gives the 24-hour clock, the Monday-first calendar and the Cyrillic day and
month names that match the Soviet theme. `LANG` stays `en_US.UTF-8`, so
interfaces are in English and only dates and times are localised. See
[Locales](#locales) to change it.

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

4. **Fill in your machine-local secrets.**

   The installer creates `~/.config/zsh/secrets.zsh` for you from
   `Hyprland-Dots/config/zsh/secrets.zsh.example`, with **placeholder values**
   and mode `600`. Open it and replace them with your real keys:

   ```bash
   ${EDITOR:-nano} ~/.config/zsh/secrets.zsh
   ```

   API keys and tokens are deliberately **not** in this repo — anything
   committed to git is recoverable from the history forever, and this repo is
   pushed to GitHub. Only the `.example` template is tracked, and a real
   `secrets.zsh` is blocked by `.gitignore` as a safety net.

   `.zshrc` sources it guarded, so a shell without it still starts normally and
   only the tools needing a key will fail:

   ```bash
   [ -r "$HOME/.config/zsh/secrets.zsh" ] && . "$HOME/.config/zsh/secrets.zsh"
   ```

   Re-running the installer **never** overwrites a `secrets.zsh` that already
   exists — it is only created when missing, so your keys survive a re-install.

   Note that `ANTHROPIC_API_KEY` is only needed for direct API use (SDK
   scripts, `curl`). Claude Code does not read it; it authenticates by OAuth
   and stores its own token in `~/.claude/.credentials.json`.

5. **Optional per-machine tooling.** The installer does not install `fnm`,
   `uv`, `rustup` or Homebrew. `.zshrc` guards each of their hooks, so their
   absence is silent - install whichever you need.

6. **Done!** After reboot, log in through ly and enjoy your custom Hyprland setup.

## What Gets Installed

### Core System
- Hyprland, hypridle, hyprlock
- ly display manager with large font
- PipeWire audio
- NetworkManager (plus `nss-mdns`, wired into `nsswitch.conf` for `.local` names)
- GPU video-acceleration drivers, detected per machine (see [Graphics](#graphics))

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

### Locales

`install-scripts/locales.sh` generates `en_US.UTF-8`, `es_US.UTF-8` and
`ru_RU.UTF-8` (the last two pairing with the ES and RU keyboard layouts) and runs
`locale-gen`. This is not optional bookkeeping: setting `LC_TIME` to a locale
that was never generated **does not fail**, glibc just falls back to `C`. The
symptom is a 12-hour clock, a Sunday-first calendar and an English lock-screen
date, with nothing anywhere explaining why.

Three places consume it, and all three want Russian:

- `config/environment.d/locale.conf` — `LC_TIME` for the systemd user session
- `config/hypr/configs/ENVariables.conf` — `LC_TIME` for everything Hyprland launches
- `scripts/SovietLock.py` — calls `setlocale(LC_TIME, "ru_RU.utf8")` itself, so
  the lock screen reads `Четверг, 10 сентября 2026`

The bar's calendar picks up `firstDayOfWeek` and its `MMMM yyyy` heading from
`Qt.locale()`. The bar's *clock* does not — `Clock.qml` formats `"HH:mm"`
directly, so it is 24-hour regardless of locale.

**To change it**, edit `LC_TIME` in both `locale.conf` and `ENVariables.conf`,
add the locale to `wanted_locales` in `locales.sh`, and re-run it.

### Fonts

`install-scripts/fonts.sh` installs the font packages, and then verifies by name
that the families the configs actually reference are present — fontconfig
substitutes silently on a miss, so a missing font is otherwise invisible until
the desktop just looks wrong.

The ones that matter:

| Family | Package | Used by |
| --- | --- | --- |
| `Terminess Nerd Font` | `ttf-terminus-nerd` | **the quickshell bar** — `bar/Theme.qml` |
| `JetBrainsMono Nerd Font Mono` | `ttf-jetbrains-mono-nerd` | foot, hyprlock, `SovietLockGen.py` |
| `Fira Code` | `ttf-fira-code` | dunst, `gtk-3.0/settings.ini` |

To change the bar's font, edit `fontFamily` in
`Hyprland-Dots/config/quickshell/bar/Theme.qml` — every widget renders through
it — and add the package to `fonts.sh` and the family to `required_families`
in the same file.

Two places name fonts that are **not** installed and have never been:
`config/rofi/themes/KooL_LonerOrZ.rasi` asks for `Iosevka`, and the quickshell
*overview* config (`config.json` / `modules/common/Appearance.qml`, not the bar,
and not autostarted) asks for `Open Sans` and `FiraConde Nerd Font`. Both render
substituted here already, so this is inherited from upstream rather than
something the install broke.

### Graphics

`install-scripts/graphics.sh` reads `lspci` and installs the VA-API and Vulkan
drivers for whatever GPU it finds — `intel-media-driver` + `vulkan-intel` on
Intel, `libva-mesa-driver` + `vulkan-radeon` on AMD, plus the `lib32-` variants
(multilib is enabled by `pacman.sh`, which runs first). NVIDIA is not handled
here; `nvidia.sh` owns that and is gated behind the preset's `nvidia` option.

This is easy to skip because nothing *looks* broken without it: `mesa` alone
gives a perfectly good desktop. What you lose is hardware video decode, so mpv
and every browser fall back to the CPU — a hot laptop and short battery, with
no error anywhere. The script runs `vainfo` afterwards and says so if decode
did not come up.

### quickshell version

The installer uses the stable `quickshell` package, **not** `quickshell-git`,
even though this machine happens to run the `-git` build the bar was written
against. A `-git` PKGBUILD compiles whatever upstream HEAD is on the day you
install, so it pins nothing and can only drift further from what was tested.

Stable was verified rather than assumed: the exported QML API of 0.3.1 was
diffed against the `0.3.0.r6.gb66495f` build this bar was developed on — 118 →
119 types and 1056 → 1057 members, with nothing removed or renamed. The bar
only uses `PanelWindow`, `PopupWindow`, `Variants`, `ShellRoot`, `Singleton`,
`Process`, `Timer` and `HyprlandFocusGrab`, all unchanged.

### Wallpapers

`Hyprland-Dots/wallpapers/` is copied to `~/Pictures/wallpapers/`, which is the
directory `WallpaperSelect.sh`, `WallpaperRandom.sh` and the rofi picker all read.
The default wallpaper is set by `DEFAULT_WALLPAPER` near the bottom of
`Hyprland-Dots/copy.sh` — currently `sovietpunk/sovietpunk_2k_2560x1440.png`.
copy.sh seeds it into `~/.config/hypr/wallpaper_effects/.wallpaper_current`, which
is what `initial-boot.sh` loads on first login and what wallust derives the bar
and terminal colours from.

Those two `.wallpaper_current` / `.wallpaper_modified` files are runtime state — a
copy of whatever wallpaper is active — so they are deliberately **not** tracked.
Change the default by editing `DEFAULT_WALLPAPER`, not by committing an image
over them.

### What is deliberately NOT in this repo

These are machine-specific, so a fresh install starts without them:

- **`~/.config/zsh/secrets.zsh`** — API keys and tokens. See installation step 4.
- **`~/.config/hypr/monitors.conf`** — the repo ships a generic template. This
  machine's copy also carries a patched-EDID setup for a 2560x1440@75 Samsung
  over HDMI, which additionally needs a blob in `/usr/lib/firmware/edid/`, a
  `FILES=` entry in `/etc/mkinitcpio.conf` and a `drm.edid_firmware=` kernel
  parameter — none of which live under `~`. Use `nwg-displays` to lay out
  whatever monitors the new machine has.
- **`/etc/wireguard/*.conf`** — your VPN configs. They contain private keys, so
  they must never be committed. See below for how to move them across.
- **Applications** beyond the desktop itself (browsers, editors, chat, language
  toolchains). The installer builds the Hyprland environment, not the full
  workstation.

### VPN configs (the bar's VPN selector)

The VPN widget lists whatever is in `/etc/wireguard/`, so on a fresh machine the
dropdown is empty until you copy your configs over. `/etc/wireguard` is
`root:root 0700` and the `.conf` files hold private keys — treat them like
secrets, and never put them in this repo.

**On the old machine**, pack them up (the tarball lands in your home directory,
not in the repo):

```bash
sudo tar -czf ~/wireguard-configs.tar.gz -C /etc wireguard
sudo chown "$USER" ~/wireguard-configs.tar.gz
```

**Move the tarball across** — over the network, if both machines are up:

```bash
scp ~/wireguard-configs.tar.gz user@newmachine:~
```

or copy it to a USB stick. Either way, delete it once it has landed.

**On the new machine**, unpack it and fix the ownership and modes — `wg-quick`
refuses to use a config that is group- or world-readable:

```bash
sudo tar -xzf ~/wireguard-configs.tar.gz -C /etc
sudo chown -R root:root /etc/wireguard
sudo chmod 700 /etc/wireguard
sudo chmod 600 /etc/wireguard/*.conf
rm ~/wireguard-configs.tar.gz
```

**Check it worked.** The first command is exactly what the widget runs to build
its list, so if it prints your VPN names the dropdown will be populated:

```bash
sudo find /etc/wireguard -name '*.conf' -exec basename {} .conf \; | sort
sudo wg-quick up de-ber     # replace with one of your own config names
wg show interfaces          # should print the interface that just came up
sudo wg-quick down de-ber
```

Then restart the bar to pick them up: `pkill qs; qs -c bar &`.

**This needs passwordless sudo.** `VpnWidget.qml` runs `sudo find`,
`sudo wg-quick up|down` and `sudo timedatectl set-timezone` from a QML `Process`,
which has no terminal to prompt on — with stock sudoers those calls fail
silently and the dropdown does nothing at all. That is what the
`nopasswd_sudo` preset option installs (`install-scripts/sudoers_nopasswd.sh`
writes a validated `/etc/sudoers.d/10-wheel-nopasswd`). The trade-off is real:
any process running as your user can become root without a prompt. If you would
rather not have that, set `nopasswd_sudo="OFF"` and narrow the rule to just
those three commands — the VPN widget is the only thing here that depends on it.

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
- Handy does **not** autostart — it is launched on demand by the keybind, to save the RAM of an idle daemon. So on first use, press `SUPER + CTRL + F8` and Handy comes up.
- Pick a model: choose **Parakeet V3** (CPU-friendly, auto-detects 25 languages including English, Spanish, German, Russian) and let it download (~30s).
- **Ignore the "Shortcut" field inside Handy's UI** — Wayland blocks apps from registering global shortcuts, so it doesn't work. The Hyprland keybind in `UserKeybinds.conf` is what actually fires the toggle.

**If you would rather have it resident**, uncomment this line in `~/.config/hypr/UserConfigs/Startup_Apps.conf`:

```
# exec-once = $UserScripts/handy-start.sh
```

`handy-start.sh` opens Handy visibly while `selected_model` is empty — so you get the model picker on a fresh machine — and switches to `--start-hidden` once a model is set.

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
- `~/.config/gtk-3.0/settings.ini` - GTK font, cursor and dark-mode preference
- `~/.config/environment.d/locale.conf` - `LC_TIME`, i.e. the clock and calendar format
- `~/.config/fontconfig/conf.d/99-no-ligatures.conf` - turns coding ligatures off

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
- ✅ nopasswd_sudo (passwordless sudo for wheel — the bar's VPN widget
  silently does nothing without it; see [VPN configs](#vpn-configs-the-bars-vpn-selector)
  for the trade-off)

## Verification

After installation, verify everything was installed correctly:

```bash
cd ~/Documents/my_archinstaller
./verify-before-transfer.sh
```

## Notes

- The installation will backup existing configs to `~/.config/<app>.backup`
- Event-based monitoring reduces CPU usage significantly
- All scripts are logged to `Install-Logs/` (untracked - they are per-run output)
- First boot runs `initial-boot.sh` to set the wallpaper, run wallust, and apply
  the GTK, icon, cursor and Kvantum themes. It runs exactly once, guarded by
  `~/.config/hypr/.initial_startup_done`. That marker is gitignored on purpose:
  if it is ever committed, copy.sh deploys it to the new machine and the whole
  first-boot setup silently skips itself.

## Credits

Based on [JaKooLit's Arch-Hyprland](https://github.com/JaKooLit/Arch-Hyprland) with extensive customizations.

## License

See LICENSE.md file.
