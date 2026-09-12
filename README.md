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

- Fresh Arch Linux installation with the `base` system and a kernel
- Internet connection
- git installed (or will be installed automatically)
- **A normal user account that can `sudo`** — see below

The sudo requirement is the one that actually bites, because a minimal
`archinstall` does not guarantee it and the failure is immediate. `install.sh`
refuses to run as root (it builds AUR packages, and `makepkg` will not run as
root either), and every install script calls `sudo` — so a machine where you
are still sitting in a root shell, or where your user is not in `wheel`, cannot
run this at all.

Check before you start:

```bash
whoami                 # must NOT be root
groups | grep -q wheel && echo "in wheel" || echo "NOT in wheel"
sudo -v                # must accept your password, not "user is not in the sudoers file"
```

If any of those is wrong, fix it from a root shell and log back in as your user:

```bash
useradd -m -G wheel -s /bin/bash yourname   # skip if the account already exists
usermod -aG wheel yourname                  # if it exists but is not in wheel
passwd yourname
pacman -S --needed sudo
EDITOR=nano visudo                          # uncomment: %wheel ALL=(ALL:ALL) ALL
```

Group changes only take effect on a new login, so log out and back in before
running the installer. The `nopasswd_sudo` preset option later replaces that
prompt with a passwordless rule — but it runs *during* the install, so you need
working password sudo to get that far.

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

   With `--preset`, the installer runs **fully non-interactively**: no welcome
   box, no confirmation prompt, no AUR-helper picker and no component menu. The
   selection comes from `custom-preset.conf`, and if no AUR helper is present
   yet it builds `yay` from the vendored `yay-bin/` PKGBUILD automatically.
   Run `./install.sh` with no arguments to pick components from a menu instead;
   that interactive path is unchanged.

3. **It reboots itself — but only if everything installed.**

   A preset run ends with `02-Final-Check.sh`. If every package is accounted
   for, you get a 15-second countdown and then a reboot, so the whole install
   is unattended; press any key during the countdown to cancel and stay in the
   session. An interactive run (no `--preset`) still asks.

   If the check finds anything missing, the installer **stops instead of
   rebooting** and leaves the list on screen. This matters because a package
   failure is not fatal on its own — the install carries on — so rebooting
   would scroll the only warning away and hand you a desktop that is subtly
   wrong with nothing on screen saying why. See
   [When the installer stops without rebooting](#when-the-installer-stops-without-rebooting).

4. **Fill in your machine-local secrets.**

   The installer creates `~/.config/zsh/secrets.zsh` for you from
   `Hyprland-Dots/config/zsh/secrets.zsh`, with **placeholder values** and mode
   `600`. Open it and replace them with your real keys:

   ```bash
   ${EDITOR:-nano} ~/.config/zsh/secrets.zsh
   ```

   The tracked copy in `Hyprland-Dots/config/zsh/secrets.zsh` is a template:
   every value in it is fake, and it must stay that way. Anything committed to
   git is recoverable from the history forever, even after a later commit
   deletes it, and this repo is pushed to GitHub — so real keys only ever go in
   the deployed copy under `~/.config/zsh/`, never in the repo.

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
- CPU microcode, detected per machine (see [Microcode](#microcode))
- A power profile daemon, whichever one the distro provides (see [Power profiles](#power-profiles))
- CUPS printing, socket-activated (see [Printing](#printing))

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
- `config/hypr/configs/ENVariables.lua` — `LC_TIME` for everything Hyprland launches
- `scripts/SovietLock.py` — calls `setlocale(LC_TIME, "ru_RU.utf8")` itself, so
  the lock screen reads `Четверг, 10 сентября 2026`

The bar's calendar picks up `firstDayOfWeek` and its `MMMM yyyy` heading from
`Qt.locale()`. The bar's *clock* does not — `Clock.qml` formats `"HH:mm"`
directly, so it is 24-hour regardless of locale.

**To change it**, edit `LC_TIME` in both `locale.conf` and `ENVariables.lua`,
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
`config/rofi/themes/LonerOrZ.rasi` asks for `Iosevka`, and the quickshell
*overview* config (`config.json` / `modules/common/Appearance.qml`, not the bar,
and not autostarted) asks for `Open Sans` and `FiraConde Nerd Font`. Both render
substituted here already, so this is inherited from upstream rather than
something the install broke.

### GTK theme

The GTK theme is **Adwaita**, set in two places that have to agree:

- `Hyprland-Dots/config/gtk-3.0/settings.ini` — `gtk-theme-name`
- `Hyprland-Dots/config/hypr/initial-boot.sh` — `gtk_theme`, applied over `gsettings`

Both matter because GTK3 applications read the theme from *either* source
depending on how they were launched, so a mismatch means some windows are
themed and others are not. That is exactly what happened here before: the
`settings.ini` copy on this machine named `Andromeda-dark`, which was never
installed, so those applications silently fell back to Adwaita while everything
reading `gsettings` got `Flat-Remix-GTK-Blue-Dark`. Adwaita is now set in both.

Adwaita is built into `gtk3` itself, so unlike a downloaded theme it needs no
package and can never go missing. Dark mode comes from
`gtk-application-prefer-dark-theme=1` plus `color-scheme=prefer-dark`, not from
a separate dark theme name.

The **icon** theme (`Flat-Remix-Blue-Dark`) and **cursor** (`Bibata-Modern-Ice`)
are unchanged and still come from `GTK-themes-icons/` via `gtk_themes.sh`, which
also still installs the Flat-Remix GTK themes — they are simply no longer
selected. One consequence worth knowing: `scripts/DarkLight.sh` picks a *random*
theme matching `*Dark*` or `*Light*` from `~/.themes`, so running it would
switch away from Adwaita. Nothing binds it to a key, so it only happens if you
call it yourself.

### Terminal greeting (pokefetch)

`.zshrc` runs `~/pokefetch_perfect` on every new shell, which draws a Pokemon
next to a `fastfetch` panel. It shells out to `pokemon-colorscripts`, and that
binary comes from `install-scripts/zsh_pokemon.sh` and **nowhere else** — which
is gated behind the preset's `pokemon` option.

So `pokemon` is not optional decoration despite reading like it: with it `OFF`,
every new terminal printed

```
/home/you/pokefetch_perfect: line 6: pokemon-colorscripts: command not found
```

and then rendered the panel with an empty `Pokemon:` field. `custom-preset.conf`
now sets `pokemon="ON"`, and `pokefetch_perfect` additionally degrades to a
plain `fastfetch` with a one-line hint if the binary is ever missing — so the
failure cannot come back silently.

### Graphics

`install-scripts/graphics.sh` reads `lspci` and installs the VA-API and Vulkan
drivers for whatever GPU it finds — `intel-media-driver` + `vulkan-intel` on
Intel, `vulkan-radeon` on AMD (VA-API for AMD now comes from `mesa` itself,
which is why there is no `libva-mesa-driver` here — asking for that name fails
the install), plus the `lib32-` variants (multilib is enabled by `pacman.sh`,
which runs first). NVIDIA is not handled here; `nvidia.sh` owns that, and the
preset's `nvidia` option defaults to `auto` — see [Hardware options](#hardware-options).

This is easy to skip because nothing *looks* broken without it: `mesa` alone
gives a perfectly good desktop. What you lose is hardware video decode, so mpv
and every browser fall back to the CPU — a hot laptop and short battery, with
no error anywhere. The script runs `vainfo` afterwards and says so if decode
did not come up.

### Microcode

`install-scripts/ucode.sh` reads the vendor from `/proc/cpuinfo` and installs
`amd-ucode` or `intel-ucode`. Nothing asks you: the CPU already knows what it
is, and a prompt could only be answered wrong.

Like the graphics drivers, this is invisible when it is missing. The machine
boots, the desktop comes up, and the CPU just keeps running whatever microcode
revision the board's firmware supplied. What you lose is every erratum and
side-channel mitigation the vendor shipped after the last BIOS release — on a
laptop that stopped getting firmware updates, years of them.

Installing the package is only half of it: the microcode has to actually reach
the kernel early, or the package just sits on disk. How that happens depends on
the system, so the script checks three things in order.

**mkinitcpio's `microcode` hook** — in Arch's default `HOOKS` since 2024, and
the usual case. It builds the image straight into the main initramfs as an
early uncompressed CPIO section, and the pacman hook regenerates the initramfs
when the ucode package lands. Nothing else is needed, and in particular the
bootloader entry must **not** be edited — the image is already there, and a
separate `initrd` line would only load it a second time. This is checked first
on purpose: telling someone to hand-edit a working boot entry is a good way to
end up with one that is broken.

**GRUB**, without that hook — it discovers the image by itself, so the script
just regenerates `grub.cfg`.

**systemd-boot**, without that hook — entries are edited by hand, and the
script deliberately will not do it for you. A malformed loader entry is an
unbootable machine that cannot be repaired from the desktop that failed to come
up. Instead it names the entries missing the line and prints the exact line to
add, above the existing `initrd`:

```
initrd /amd-ucode.img
```

After rebooting, confirm it took:

```bash
journalctl -k -b | grep microcode      # want: "microcode updated early"
```

### Power profiles

The bar's `PowerProfileWidget.qml` runs `powerprofilesctl` and watches
`net.hadess.PowerProfiles` on the system bus. What it needs is that D-Bus API —
not one particular package.

On Arch the API comes from `power-profiles-daemon`. On CachyOS it normally
comes from `tuned-cachy-ppd`, which provides the same interface and
**conflicts** with `power-profiles-daemon`. That conflict is why this has its
own script: asking for `power-profiles-daemon` on CachyOS is not a harmless
no-op, it is a conflicting transaction, and `pacman -S --noconfirm` will not
remove an installed package to satisfy it — so the install stops partway
through a run whose whole point is being unattended.

`install-scripts/power_profiles.sh` asks `pacman -T` whether anything already
satisfies the dependency (which counts `provides`) and installs
`power-profiles-daemon` only when nothing does. It then checks that
`powerprofilesctl` actually exists, because the widget calls the CLI rather
than the bus — a provider without it leaves the dropdown inert even with the
daemon running.

`services.sh` enables whichever unit is present: `power-profiles-daemon.service`,
or `tuned-ppd.service` with `tuned.service` under it. The unit name is not
fixed either, and hardcoding one meant enabling a unit that did not exist.

### Printing

`install-scripts/printing.sh` installs `cups`, `cups-filters` and `cups-pdf`.
Nothing else in the install pulls in a print stack, so without it every
application's print dialog opens with an empty printer list and no way to add
one — which is easy to miss for weeks, because nothing looks broken until the
first time you try to print.

Like Docker, CUPS is **socket-activated** rather than enabled at boot: `cupsd`
is idle almost all the time on a laptop, so `cups.socket` and `cups.path` start
it on demand — the first print dialog, `lp` call, or visit to
<http://localhost:631> brings it up. Enable `cups.service` instead if you want
`cupsd` resident, which is only needed if you rely on it continuously browsing
the network for printers that appear later.

No driver package is installed, and for a modern network printer none is
needed: IPP Everywhere / AirPrint printers advertise their own capabilities and
`cups-filters` does the rendering. Only an old USB or PostScript-only model
needs a vendor driver (`brother-*`, `gutenprint`) from the AUR.

**The printer itself is not configured by the installer** — see
[What is deliberately NOT in this repo](#what-is-deliberately-not-in-this-repo).
Adding it back is normally just discovery, since `avahi` and `nss-mdns` are
already wired up:

```bash
# Look for it on the network (driverless printers answer here)
driverless
# or add it explicitly, replacing the URI and name
sudo lpadmin -p Brother -E -v ipp://192.168.1.110/ipp/print -m everywhere
lpstat -p          # should report the printer as idle
```

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
- **`~/.config/hypr/monitors.lua`** — the repo ships a generic template. This
  machine's copy also carries a patched-EDID setup for a 2560x1440@75 Samsung
  over HDMI, which additionally needs a blob in `/usr/lib/firmware/edid/`, a
  `FILES=` entry in `/etc/mkinitcpio.conf` and a `drm.edid_firmware=` kernel
  parameter — none of which live under `~`. Use `nwg-displays` to lay out
  whatever monitors the new machine has.
- **`/etc/wireguard/*.conf`** — your VPN configs. They contain private keys, so
  they must never be committed. See below for how to move them across.
- **`/etc/cups/printers.conf`** and its PPD — the printer queue. The device URI
  is a LAN address (`ipp://192.168.1.110/ipp/print`) that will not be right on
  another network, so the queue is machine-specific even though CUPS itself is
  installed. Re-add the printer once; see [Printing](#printing).
- **`intel-undervolt`** — deliberately not carried over. The config on this
  machine reads `enable no`, so the service runs and does nothing; there is
  nothing to reproduce. Undervolt offsets are also per-CPU-sample, so copying
  another machine's numbers is a bad idea.
- **Applications** beyond the desktop itself (browsers, editors, chat, language
  toolchains). The installer builds the Hyprland environment, not the full
  workstation.
- **The wallust colour files** — `cava/config`,
  `hypr/wallust/wallust-hyprland.lua`, `rofi/wallust/colors-rofi.rasi`,
  `wallust/output/colors-waybar.css`, `quickshell/qml_color.json` and
  `quickshell/bar/wallust-colors.json`. Every one is a `target` in
  `wallust.toml`, rewritten in full each time the wallpaper changes, so they are
  runtime state and are gitignored — otherwise whichever palette happened to be
  up got committed and the next wallpaper change dirtied the tree, which
  `auto-install.sh` then refuses to pull over.

  They still have to *exist*: `UserDecorations.lua` requires
  `wallust-hyprland.lua`, twelve rofi themes `@theme` `colors-rofi.rasi` and
  wlogout's `style.css` `@import`s `colors-waybar.css` — a missing file there is
  a config error on first launch, not a silent fallback. So a rendered snapshot
  of each lives in **`Hyprland-Dots/defaults/`**, mirroring its path under
  `~/.config/`, and `copy.sh` puts it in place. `initial-boot.sh` runs wallust on
  first login and overwrites all of them from your actual wallpaper.

  Re-running the installer keeps the palette you are already using: `copy.sh`
  recovers these files from the backup it just made and only falls back to
  `defaults/` when there is nothing to recover. That matters because
  `initial-boot.sh` is guarded by `.initial_startup_done` and will not run a
  second time — without the recovery the desktop would sit on the snapshot
  palette until the next wallpaper change.

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

See `Hyprland-Dots/config/hypr/configs/Keybinds.lua` for all keybindings, or press
`SUPER H` (cheat sheet) / `SUPER SHIFT K` (search) — both list the live binds from `hyprctl binds`.

The Hyprland config is Lua (`hyprland.lua` + `configs/*.lua` + `UserConfigs/*.lua`); the
hyprlang `.conf` format is deprecated since Hyprland 0.55 and removed in 0.57.
`hyprctl keyword` no longer exists — scripts change options with `hyprctl eval 'hl.config({...})'`
and dispatch with `hyprctl dispatch 'hl.dsp.…'`.

**Two binds do nothing on a fresh install.** `SUPER + T` launches Telegram and
`SUPER + R` launches RustRover (`UserConfigs/UserKeybinds.lua`), and
neither application is installed by this repo — applications beyond the desktop
itself are deliberately out of scope, see
[What is deliberately NOT in this repo](#what-is-deliberately-not-in-this-repo).
A bind pointing at a missing binary fails silently in Hyprland: no error, no
notification, the key just does nothing. Install `telegram-desktop` and
`rustrover` if you want them, or delete the two lines.

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
- **Ignore the "Shortcut" field inside Handy's UI** — Wayland blocks apps from registering global shortcuts, so it doesn't work. The Hyprland keybind in `UserKeybinds.lua` is what actually fires the toggle.

**If you would rather have it resident**, uncomment this line in `~/.config/hypr/UserConfigs/Startup_Apps.lua`:

```lua
-- hl.exec_cmd(V.UserScripts .. "/handy-start.sh")
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
- CUPS printing
- And more...

Two of them are load-bearing rather than optional, despite the names:
`dots` (without it you get vanilla Hyprland) and `pokemon` (`.zshrc` needs
`pokemon-colorscripts` — see [Terminal greeting](#terminal-greeting-pokefetch)).

#### Hardware options

`nvidia`, `nouveau` and `rog` take a third value, **`auto`**, which is their
default, and it is what the shipped preset uses.

A preset is carried from machine to machine, which makes it the worst possible
place to record what hardware a machine has. This one was written on a laptop
with Intel graphics, so it used to say `nvidia="OFF"` — and run unchanged on an
NVIDIA machine that silently skipped `nvidia.sh` entirely. No driver, no
prompt, and `02-Final-Check.sh` could not report it, because nothing had been
attempted. The same applied to `rog="OFF"` on an ASUS laptop.

With `auto`, the installer answers these from the machine instead: `lspci` for
the GPU, `/sys/class/dmi/id/sys_vendor` for ASUS hardware. `ON` and `OFF` still
force the decision, for when you mean it — `nvidia="OFF"` to stay on the
open-source driver, for instance. A forced `ON` is still ignored with a note if
the hardware is not there, so a stale preset cannot install an NVIDIA driver on
an AMD box.

This is also why there is no CPU/GPU vendor prompt: `--preset` runs
unattended by design, so a dialog could only appear in the interactive path —
the one that already worked.

### After Installation

All configs are in `~/.config/`. Main files to edit:
- `~/.config/hypr/` - Hyprland configuration
- `~/.config/quickshell/bar/` - Custom bar configuration
- `~/.config/foot/` - Terminal configuration
- `~/.zshrc` - Shell configuration
- `~/.config/gtk-3.0/settings.ini` - GTK theme, font, cursor and dark-mode preference
- `~/.config/environment.d/locale.conf` - `LC_TIME`, i.e. the clock and calendar format
- `~/.config/fontconfig/conf.d/99-no-ligatures.conf` - turns coding ligatures off

## Troubleshooting

### When the installer stops without rebooting

A preset run that ends with

```
[WARN] NOT rebooting: the final check found missing packages.
```

did most of its work — Hyprland is installed and the dotfiles are deployed —
but at least one package did not land. The names are printed above that line
and saved to `Install-Logs/00_CHECK-*_installed.log`.

Two things feed that list. `02-Final-Check.sh` verifies a hardcoded set of
sixteen essentials, which catches a package that was never even attempted
because its script was skipped or died early. Everything else comes from
`Install-Logs/.failed-packages`, which `record_package_failure()` in
`Global_functions.sh` appends to whenever any `install_*` function's
post-install verification fails — so the check covers every package the install
actually tried, not just the sixteen. Anything that failed but was later pulled
in as a dependency of something else is re-verified and dropped from the list,
so what you see is genuinely still absent.

In practice these are almost always AUR builds (`awww`, `handy-bin`,
`pokemon-colorscripts`), which break for reasons that have nothing to do with
this repo — an upstream tarball moved, a dependency bumped its soname. Retry
them by hand and read the real error:

```bash
yay -S awww          # replace with whatever was listed
```

Then reboot yourself:

```bash
systemctl reboot
```

Re-running `./install.sh --preset custom-preset.conf` is also safe — every
package step skips what is already installed, and `copy.sh` will not overwrite
a `secrets.zsh` you have filled in.

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
- ✅ printing (CUPS — nothing else pulls in a print stack; see [Printing](#printing))
- ✅ pokemon (`pokemon-colorscripts`, which `.zshrc` needs for the pokefetch
  greeting — see [Terminal greeting](#terminal-greeting-pokefetch))

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
