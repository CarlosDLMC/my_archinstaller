# My Arch Installer

Automated Arch Linux installation with custom Hyprland setup.

Dates and times run on a Russian time locale (`LC_TIME=ru_RU.UTF-8`), which is
what gives the 24-hour clock, the Monday-first calendar and the Cyrillic day and
month names that match the Soviet theme. `LANG` stays `en_US.UTF-8`, so
interfaces are in English and only dates and times are localised. See
[Locales](#locales) to change it.

## Also works on CachyOS

This installs cleanly on top of a **CachyOS "No Desktop"** install and was
written with it in mind (it already knows about `tuned-cachy-ppd` and
`cachyos-hyprland-settings`). On the installer's **Additional packages** page,
select exactly this and nothing else:

- **CachyOS Packages**: keep `cachyos-settings`, `cachyos-micro-settings` and
  `cachyos-kernel-manager`. Uncheck `cachyos-hello`, `cachyos-packageinstaller`
  and `cachyos-wallpapers` (the dots ship their own wallpapers).
- **Base-devel + Common packages**: keep only the **Network** and **hardware**
  sub-groups. Network gives you NetworkManager to get online on first boot;
  hardware carries `linux-firmware`, which nothing else on the page or in this
  repo installs. Every other sub-group is duplicated by the install scripts.
- Uncheck everything else: the shell configuration, every desktop entry
  (especially **Hyprland** - it brings SDDM and its own bar, which would fight
  ly and the Quickshell bar), Firefox, both printing groups and accessibility.

If the machine has an NVIDIA GPU, the CachyOS installer already puts its
prebuilt kernel module (`linux-cachyos-nvidia-open`) on it. `nvidia.sh` sees
that and keeps it instead of installing `nvidia-open-dkms`, which would
conflict with it; the rest of the NVIDIA setup (mkinitcpio modules, modeset
options, nouveau blacklist) runs the same either way. The NVIDIA environment
variables in `configs/ENVariables.lua` turn themselves on when every GPU in the
machine is NVIDIA, and stay off on hybrid laptops.

git is not part of that selection, so after the first login:

```bash
sudo pacman -S git
```

then continue with the [Installation Steps](#installation-steps) below.

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
- **Herdr** terminal workspace manager for AI coding agents, with the sidebar, keybindings, theme and done/blocked sounds preconfigured
- **Dev layouts** (`hdl` / `hds` / `hdlm` / `hsl`) that build a whole editor + agent + terminal pane layout in one command
- **Neovim with LazyVim**, which is where the file tree beside the agents comes from
- **Hunk** review-first diff viewer, for reading what the agents actually wrote
- **Whole-Workspace Move** with SUPER + ALT + number, rebuilding the tiling layout window for window
- **Boot Splash** with the repo logo (Plymouth, optional - replaces the CachyOS one)
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
running the installer. The `nopasswd_sudo` preset option replaces that prompt
with a passwordless rule as the very first step of the install — but it is
installed *by* the installer, so you need working password sudo for that one
first prompt.

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

   With `--preset`, the installer runs **non-interactively**: no welcome box,
   no confirmation prompt, no AUR-helper picker and no component menu. The
   selection comes from `custom-preset.conf`, and if no AUR helper is present
   yet it builds `yay` from the vendored `yay-bin/` PKGBUILD automatically.
   Run `./install.sh` with no arguments to pick components from a menu instead;
   that interactive path is unchanged.

   **You type your sudo password exactly once**, right after the selection is
   printed, and never again. With `nopasswd_sudo="ON"` (the shipped preset)
   the passwordless rule is installed *first*, before the first package, so
   nothing later in the run can prompt. A background `sudo -v` keepalive also
   runs for the whole install, which covers the interactive path and any
   machine where the rule is off. Before this, sudo's 5-minute timestamp
   expired during the first long step and the next package call sat on a
   spinner waiting for a password nobody could see.

3. **It reboots itself — but only if everything landed.**

   A preset run ends with `02-Final-Check.sh`. It checks two things: that
   every package is accounted for, and that each selected component produced
   what it exists to produce — the dotfiles are in `~/.config`, `ly@tty2` is
   enabled and its config matches the repo, zsh is the login shell, the
   Russian locale was generated, `systemd-resolved` is enabled, passwordless
   sudo works, and so on. If all of that passes you get a 15-second countdown
   and then a reboot; press any key during the countdown to cancel and stay in
   the session. An interactive run (no `--preset`) still asks.

   If anything is missing, the installer **stops instead of rebooting** and
   leaves the list on screen. This matters because a package or script failure
   is not fatal on its own — the install carries on — so rebooting would
   scroll the only warning away and hand you a desktop that is subtly wrong
   with nothing on screen saying why. The screen is no longer cleared before
   the check, so whatever a script printed during the run is still above it. See
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
- NetworkManager (plus `nss-mdns`, wired into `nsswitch.conf` for `.local` names,
  and `systemd-resolved` — see [DNS](#dns))
- GPU video-acceleration drivers, detected per machine (see [Graphics](#graphics))
- CPU microcode, detected per machine (see [Microcode](#microcode))
- A power profile daemon, whichever one the distro provides (see [Power profiles](#power-profiles))
- CUPS printing, socket-activated (see [Printing](#printing))

### Desktop Environment
- Quickshell (custom bar)
- foot (terminal)
- rofi (launcher)
- wlogout (power menu)
- dunst (notifications — swaync is removed if present)
- awww (wallpaper daemon)
- wallust (color scheme generator)

### Custom Features
- Keyboard layouts: US, ES, RU
- Night light with hyprsunset
- VPN selector for WireGuard
- Custom pokefetch terminal greeting
- Event-based system monitoring
- Battery, WiFi, Bluetooth, Volume widgets
- Battery charge limit (60% / 80% / Full) — see [Battery charge limit](#battery-charge-limit)
- Whole-workspace move that preserves the dwindle layout

### Applications
- LibreWolf (browser, `extra/librewolf` — `librewolf-bin` no longer exists in the AUR)
- vim (the `$EDITOR` the Hyprland config names) and nano
- Thunar (file manager)
- btop, cava, fastfetch
- mpv, pavucontrol
- satty (screenshot annotation editor)
- Handy (offline speech-to-text — Parakeet V3, auto-detects 25 languages)
- Herdr (terminal workspace manager for AI coding agents — a static binary from
  herdr.dev, not a repo or AUR package, see [Herdr](#herdr-terminal-workspace-manager))
- Neovim + LazyVim, with ripgrep, fd, lazygit, tree-sitter-cli, stylua and shfmt
  (see [Neovim and the file explorer](#neovim-and-the-file-explorer))
- Hunk (terminal diff viewer for agent changesets — also an out-of-band binary,
  see [Hunk](#hunk-reading-what-the-agents-wrote))

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

The GTK **application font** (`JetBrainsMono Nerd Font 16`, monospace
`JetBrainsMono Nerd Font Mono 16`) is set by `initial-boot.sh` over `gsettings`
too. It has to be: that value lives in dconf, which no dotfile carries, so a
fresh machine used to come up at `settings.ini`'s 14pt (or the portal's
Cantarell default in GTK4 apps) while this one showed 16pt. Change it with
`gtk_font` / `gtk_mono_font` at the top of `initial-boot.sh`.

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

**systemd-boot or limine**, without that hook — both are reported, never
edited. The installer does not write to any bootloader, on purpose: a malformed
boot entry is an unbootable machine that cannot be repaired from the desktop
that failed to come up, and that is a far worse outcome than a microcode update
that has not been wired up yet. So it names what is missing and prints the
exact line to add, which in both cases must come *above* the initramfs:

```
initrd /amd-ucode.img              # systemd-boot, in /boot/loader/entries/*.conf
module_path: boot():/amd-ucode.img # limine, in /boot/limine.conf
```

If `limine-mkinitcpio-hook` or `limine-entry-tool` generates your entries, this
is already handled.

Anything else (rEFInd, a UKI) gets the same treatment: a description of what to
add, and no changes made.

After rebooting, confirm it took:

```bash
journalctl -k -b | grep microcode      # want: "microcode updated early"
```

### DNS

`01-hypr-pkgs.sh` installs `systemd-resolvconf`, which replaces the classic
`resolvconf` with a shim over `resolvectl` — and that shim only works while
`systemd-resolved` is running. A stock `archinstall` + NetworkManager system has
neither, so NetworkManager writes `/etc/resolv.conf` itself and DNS just works.
Add the shim without the daemon and NetworkManager switches to the resolvconf
path, which then fails: the link comes up, nothing resolves, and nothing says
why. `wg-quick` has the same dependency for the `DNS=` line in every WireGuard
config here, so the bar's VPN selector was broken by it too.

`services.sh` therefore enables `systemd-resolved` and points `/etc/resolv.conf`
at its stub whenever `systemd-resolvconf` is installed. This machine only ever
worked because resolved had been enabled by hand, months before the installer
existed — which is exactly the kind of gap a fresh install exposes. Check with:

```bash
resolvectl status | head -5     # should list a DNS server per link
readlink /etc/resolv.conf       # ../run/systemd/resolve/stub-resolv.conf
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

### Battery charge limit

Click the battery in the bar. The card shows level, capacity, cycles, draw,
time and — per pack, where there is more than one — **health**, meaning
`energy_full / energy_full_design`: how much of its original capacity the cell
still holds. Under that, three pills: **60%**, **80%** and **Full**.

Why you want one. A lithium cell wears out two ways. Cycling it is the one
everybody counts, and a laptop that lives on mains barely does it — the charger
bypasses a full pack and runs the machine off the adapter, so the cycle counter
hardly moves. The other is **calendar ageing**: held at 100%, a cell sits at
~4.2V and its electrolyte oxidises at that potential whether or not any current
flows, faster the warmer it is. Inside a laptop that is plugged in permanently
that is the dominant wear by a wide margin.

The T480 this was written on shows it plainly. The internal pack has **239
cycles and 44%** of its design capacity left; the removable one has **566
cycles and 82%**. Cycling is not what killed the first one.

A threshold stops charging short of full so the cell spends its life at a
voltage where that reaction is far slower. 60% is the one to want on a machine
that stays on a desk; 80% is the usual compromise for one that travels.

Two things about it that are not obvious:

- It is only a **charge** limit. It stops charging; it discharges nothing. A
  pack that was already above the limit when you set it stays there until the
  machine actually runs off the battery — on a desk, that can be months. The
  card says `Above limit · 60%` rather than `Holding at 60%` so this is visible
  rather than mysterious.
- It will not bring a dead pack back. Below about 60% health the cell is past
  what a threshold can save; the limit protects the packs you still have.

**Nothing is set for you.** `install-scripts/battery_charge_limit.sh` seeds
`/etc/battery-charge-limit.conf` with whatever the hardware is already doing and
leaves it there — a machine that travels wants the full pack, and an installer
that decides 60% on its own is a laptop that dies in a meeting.

What it installs, and why each piece exists:

| Piece | Why |
|---|---|
| `/usr/local/bin/battery-charge-limit` | Those sysfs files are root-writable only, and a QML `Process` has no tty to prompt on. Root-owned on purpose: sudo is passwordless here, so a user-writable script behind it would be a way to run anything as root |
| `/etc/battery-charge-limit.conf` | A sysfs write does not survive a reboot |
| `battery-charge-limit.service` | Re-applies it at boot **and after resume** — some firmware clears the threshold on wake |

From a terminal, if you prefer:

```bash
sudo battery-charge-limit get        # what each pack is set to
sudo battery-charge-limit set 60     # set every pack, and remember it
```

Machines with no `charge_control_end_threshold` — desktops, and laptops whose
vendor never wired one up — get nothing installed, and the card hides the
control instead of offering one that does nothing. Support is best on ThinkPads
(via `thinkpad_acpi`, no extra module needed) and most ASUS laptops.

### Laptops and desktops

The same install is meant to work on both, so anything tied to laptop hardware
is decided by whether the hardware is there — never by a question or a flag you
have to remember to flip when you move the preset to another machine.

- **Battery widget** — hidden when there is no `/sys/class/power_supply/BAT*`.
  It used to sit in the bar reading `0%` with an empty dropdown. The reading is
  a singleton, so hiding it really does stop the work: one `udevadm monitor` for
  the whole shell, and none at all on a desktop.
- **Charge limit picker** — shown only where the kernel exposes
  `charge_control_end_threshold` *and* the root helper is installed. See
  [Battery charge limit](#battery-charge-limit).
- **Bluetooth widget** — hidden when no controller is bound
  (`/sys/class/bluetooth/hci*`). It used to show a permanently "off" icon whose
  toggle silently failed, because `bluetoothctl` had no adapter to talk to.
- **Separators** — tied to the widget beside them. A hidden widget drops out of
  the layout, but its separator is a sibling and would otherwise remain,
  leaving two dividers with nothing between them.
- **`configs/Laptops.lua` and `UserConfigs/Laptops.lua`** — not loaded at all on
  a desktop. They bind `XF86MonBrightness*`, `XF86KbdBrightness*` and
  `XF86TouchpadToggle`, and name a touchpad device by its exact Hyprland name.
  None of that errors on a desktop; it just fills the keybind cheat sheet with
  entries that do nothing.
- **`bluetooth` in the preset** — `auto`, so bluez is installed and enabled only
  when a controller is present.

Laptop detection lives in `V.is_laptop` (`configs/Vars.lua`). A battery is the
primary signal; DMI `chassis_type` is the fallback, so a laptop running with a
dead or removed battery is still treated as one.

### Boot splash (Plymouth)

The `plymouth` preset option installs a Plymouth theme (`assets/plymouth/soviet/`)
that paints the repo logo on black, with the stock spinner and the LUKS password
prompt underneath. It is what you see between the firmware and ly.

On CachyOS the stock theme keeps the motherboard's own logo (the ACPI BGRT
image) as background and adds a CachyOS watermark at the bottom. This theme
ignores the firmware image entirely, so disabling **Boot Logo Display** in the
BIOS leaves only black, then the logo. That is the closest you can get to a
custom vendor logo without flashing modified firmware, which ASUS boards reject
through every official path.

- `plymouth="auto"` (the shipped preset) acts only where plymouth is already
  installed **and** in the mkinitcpio `HOOKS` - CachyOS does both. On a plain
  Arch install it does nothing.
- `plymouth="ON"` installs plymouth and the theme anywhere, then prints the two
  steps it deliberately does not do: adding the `plymouth` hook to
  `/etc/mkinitcpio.conf` and `splash` to the kernel command line. The command
  line lives in the bootloader entry, and this repo never writes to a
  bootloader.

Only `soviet.plymouth` and `watermark.png` are in the repo; the spinner frames
and dialog artwork are copied at install time from plymouth's own `spinner`
theme. To change the picture, replace `watermark.png` (about 400 px tall, on a
black or transparent background) and re-run:

```bash
./install-scripts/plymouth.sh
```

### Limine boot menu theme

CachyOS installs Limine bare: the pretty menu on the live ISO is GRUB with the
CachyOS GRUB theme, not Limine. `assets/limine/` carries a theme for the installed
Limine: `limine-wallpaper.png` (a 3840x2160 KGB server-hall render with the terminals
switched off, upscaled from a 1280x720 Grok render with Real-ESRGAN; Limine scales it
to the screen) and `theme.conf`, the global options that
go at the top of `/boot/limine.conf`: wallpaper, no "Limine vX.Y.Z" header (empty `interface_branding:`), Limine's own key help lines
(they name the hotkeys: S reboots into the firmware setup, E edits an entry, B types a
one-off entry), a fully transparent text box, phosphor-green text matching the CRTs,
2x font scale.

Limine's terminal maps text onto a 256-glyph CP437 font and cannot show Cyrillic, so
`interface_branding` stays unset. `make-wallpaper.sh` is optional: it paints a
Cyrillic title into a copy of the wallpaper and darkens the left side for the menu
text; point `wallpaper:` at its output and raise `term_margin` if you use it.

The `limine` preset option (`install-scripts/limine.sh`, `limine="auto"` in the
shipped preset) applies it wherever a `limine.conf` exists: wallpaper onto the ESP,
theme block prepended, and `timeout: no` so the menu waits for a choice instead of
booting the default after a countdown. This is the one place the repo edits a
bootloader config, added knowingly on 2026-09-13; the safeguards are a backup kept
as `limine.conf.pre-theme`, an edit confined to the marked block plus the `timeout:`
line, a before/after comparison of the OS entries that aborts the write if they
differ, and a re-enroll when `ENABLE_ENROLL_LIMINE_CONFIG` is on in
`/etc/default/limine`. Re-running replaces the block rather than duplicating it.
To do it by hand instead:

```bash
sudo cp assets/limine/limine-wallpaper.png /boot/limine-wallpaper.png   # /boot is the ESP on CachyOS
sudo cp /boot/limine.conf /boot/limine.conf.pre-theme
cat assets/limine/theme.conf <(sudo cat /boot/limine.conf) | sudo tee /boot/limine.conf.new >/dev/null && sudo mv /boot/limine.conf.new /boot/limine.conf
sudo sed -i 's/^timeout: .*/timeout: no/' /boot/limine.conf
```

`limine-entry-tool` only rewrites the kernel entries under the CachyOS heading, so
the global block survives kernel updates (`timeout` and `default_entry` already do).
A missing wallpaper is skipped silently, an unknown key is ignored, so a typo
degrades the look rather than the boot. The selected entry is drawn in reverse video,
which is why the highlight bar takes the `term_foreground` colour. Limine still draws
its box frame around the entries; that is part of the program, not the theme. Revert
everything with `sudo cp /boot/limine.conf.pre-theme /boot/limine.conf`.

### Firmware boot logo (the picture before the bootloader)

`bios-logo/` puts `LOGO.JPG` into the motherboard firmware itself, so the vendor logo
at power-on is replaced too. It is vendor-independent for the image surgery (AMI
Aptio V, which ASUS, Gigabyte, MSI and ASRock all use) and documents the vendor
specific parts: where to download the stock file, what to name it, and which
button-driven recovery flasher writes a modified image. Verified on the ASUS TUF
GAMING B650M-PLUS WIFI via USB BIOS FlashBack. Not part of `install.sh` on purpose -
it is a firmware flash the user does by hand. See `bios-logo/README.md`.

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
It ships the full set in use on this machine (fourteen files, about 49 MB,
including the `Dynamic-Wallpapers/` light and dark pair) so the picker on a
fresh install offers the same choices. The copy is additive: wallpapers you add
locally are never removed by a re-run.
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

The configs are not tied to a machine (a provider config carries a key pair the
provider registered to your account), so the same files work on every computer
you copy them to.

**On the old machine**, fix the permissions first — configs added by hand often
end up owned by your user and world-readable, and `wg-quick` refuses to use a
config that is group- or world-readable:

```bash
sudo chown -R root:root /etc/wireguard
sudo chmod 700 /etc/wireguard
sudo find /etc/wireguard -name '*.conf' -exec chmod 600 {} +   # zsh cannot glob a root-only dir
```

Then pack them into a **passphrase-encrypted** archive. `tar` pipes straight
into `gpg`, so the plaintext never touches disk and the resulting `.gpg` file is
safe to park in cloud storage or e-mail to yourself:

```bash
sudo tar -cz -C /etc wireguard | gpg --symmetric --cipher-algo AES256 -o ~/wireguard-configs.tar.gz.gpg
```

`gpg` asks for a passphrase twice. That passphrase is the entire protection —
anyone who gets the file can guess offline at full speed — so use a long one
(five or six random words, or 20+ random characters) and keep it in your
password manager, not next to the file. Do not use a password-protected zip
instead: the classic ZipCrypto scheme is broken.

**Move the `.gpg` file across** — cloud storage, `scp`, or a USB stick all work
because it is encrypted:

```bash
scp ~/wireguard-configs.tar.gz.gpg user@newmachine:~
```

**On the new machine**, decrypt and unpack in one go (`gpg` ships with every
Arch install), then lock the ownership and modes down again:

```bash
gpg --decrypt ~/wireguard-configs.tar.gz.gpg | sudo tar -xz -C /etc
sudo chown -R root:root /etc/wireguard
sudo chmod 700 /etc/wireguard
sudo find /etc/wireguard -name '*.conf' -exec chmod 600 {} +   # zsh cannot glob a root-only dir
rm ~/wireguard-configs.tar.gz.gpg
```

**Check the two things the widget depends on.** Both commands must succeed —
the first without a password prompt, the second printing `active`:

```bash
sudo -n true && echo "passwordless sudo OK"
systemctl is-active systemd-resolved
```

If `sudo` prompts, run `install-scripts/sudoers_nopasswd.sh` (see below). If
resolved is inactive, `sudo systemctl enable --now systemd-resolved` — every
config here has a `DNS=` line and `wg-quick` fails on it without resolved.

**Check it worked.** The first command is exactly what the widget runs to build
its list, so if it prints your VPN names the dropdown will be populated:

```bash
sudo find /etc/wireguard -name '*.conf' -exec basename {} .conf \; | sort
sudo wg-quick up de-ber     # replace with one of your own config names
wg show interfaces          # should print the interface that just came up
curl -s https://ipinfo.io/country   # should print the server's country
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
- `ALT + Tab` - **nothing, on purpose.** Hyprland's default cycle-window bind is
  removed in `UserKeybinds.lua` so the key reaches Herdr, which cycles terminal
  tabs with it. A compositor bind is consumed before any application sees it, so
  this is the only way Herdr can have the key. Window cycling stays on
  `SUPER + J` / `SUPER + K`.

See `Hyprland-Dots/config/hypr/configs/Keybinds.lua` for all keybindings, or press
`SUPER H` for the cheat sheet: a window listing every live bind (from `hyprctl binds`) with a
search box, so typing `screenshot` or `super shift` filters by action or keys. `SUPER SHIFT K`
shows the same list in rofi.

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

### Herdr (terminal workspace manager)

Herdr runs AI coding agents inside one persistent terminal session: workspaces
(typically one per git worktree), tabs inside them, panes inside those, and a
sidebar listing every agent's state — idle, working, done, blocked — across all
of them at once. The sidebar is the point: you can leave an agent running in
workspace 3 and see from workspace 1 the moment it finishes or gets stuck.

Controlled by the `herdr` preset option. It needs `dots` on, which owns
everything below except the binary itself.

**It is not a repo or an AUR package.** `install-scripts/herdr.sh` reads
`https://herdr.dev/latest.json` — the manifest carries the per-platform download
URL and its sha256 — and installs the static binary to `~/.local/bin/herdr`. The
manifest is read rather than a version pinned, so a fresh install gets whatever
is current; `herdr update` keeps it current afterwards. The sha256 is verified
before the binary is installed and a mismatch means it is **not** installed:
this is a binary from outside the distro's package manager, so that hash is the
only integrity check there is. If herdr.dev is unreachable the component is
*skipped* rather than failing the install — it lands in the failed-package
manifest and `02-Final-Check.sh` reports it at the end.

The binary is the only thing `herdr.sh` downloads. The config, the sounds and
the four helper scripts are dotfiles, which is why `install.sh` runs `herdr.sh`
*after* `dotfiles-main.sh` — the other order would substitute paths into a file
that does not exist yet and then have `copy.sh` lay the untouched template back
on top of it.

#### Key bindings

The prefix is `CTRL + B`, and `CTRL + B ?` lists everything.

| Keys | Action |
| --- | --- |
| `ALT + 1…9` | Switch to workspace N |
| `CTRL + ALT + 1…9` | Focus tab N, creating it when N is the next tab up |
| `ALT + Tab` / `CTRL + Tab` | Next tab (`CTRL + SHIFT + Tab` for previous) |
| `ALT + T` / `ALT + C` | New / close tab |
| `ALT + H J K L` | Focus pane left / down / up / right (arrows work too) |
| `ALT + V` / `ALT + S` | Split vertical / horizontal |
| `ALT + X` / `ALT + Z` | Close pane / zoom pane |
| `ALT + N` | New workspace |
| `ALT + Q` | Close workspace — a popup that also removes the git worktree if it is one |
| `ALT + W` / `ALT + B` | Next / previous workspace |
| `CTRL + B W` | Workspace picker |

`ALT + Tab` only reaches Herdr because `UserKeybinds.lua` removes Hyprland's
default cycle-window bind on that key; see [Key Bindings](#key-bindings-some-important-ones).

`CTRL + ALT + 1…9` are not a Herdr feature — Herdr's own `switch_tab` cannot
create a tab that is not there. They are `[[keys.command]]` entries calling
`~/.local/bin/herdr-goto-tab`, which focuses tab N or creates it when N is one
past the end.

#### What the config changes

`~/.config/herdr/config.toml`, from `Hyprland-Dots/config/herdr/`:

- **Sidebar legibility.** `status_indicators = "symbols"` gives each state a
  distinct glyph instead of relying on colour alone, and `[theme.custom]`
  brightens the greys the stock theme uses for secondary text, which were too
  dim to read at a glance. Per-token rules colour the state word itself —
  blocked red, working amber, done mint, idle grey — and `dim = false` on each
  token is the part that actually makes it stick, since per-token styling wins
  over the theme.
- **A wider sidebar** (`sidebar_width = 30`) and no row gap, so more agents fit
  on screen.
- **A `claude`-specific row layout** that adds the stripped terminal title, so
  Claude Code sessions are identifiable by what they are working on rather than
  by tab number.
- **Notifications are off by default.** `ui.toast.delivery = "off"` and
  `ui.sound.enabled = false`. The done/blocked sounds are wired up and shipped
  (`config/herdr/sounds/*.mp3`, freedesktop tones converted to mp3, which is the
  format Herdr requires) — set `enabled = true` to turn them on, or
  `delivery = "system"` to route toasts through dunst. `droid` is pinned off in
  `[ui.sound.agents]` either way.

#### The moving parts around it

- **`__HOME__` in `config.toml`.** Herdr's `[[keys.command]]` entries take a
  command string, and a tracked dotfile cannot contain one machine's `$HOME`.
  The dotfile ships `__HOME__` and `herdr.sh` substitutes it in the *installed*
  copy. Re-running is a no-op once no placeholders are left.
- **`herdr-workspace-numbers.service`.** Herdr has no built-in workspace-number
  token, so the sidebar reads a custom `$num` written into workspace metadata —
  and that metadata does not survive a server restart. This user unit runs
  `herdr-watch-workspace-numbers` to re-stamp it. Nothing else depends on it;
  drop it if Herdr ever grows a real number token.
- **`CARGO_TARGET_DIR` in `.zshrc`.** Herdr creates git worktrees under
  `~/.herdr/worktrees`, and cargo gives every worktree its own `target/` — about
  20 GB apiece on a large Rust repo, which fills a 225 GB disk after three
  branches. One shared cache at `~/.cache/cargo-target` avoids that.
- **`~/.local/bin` on `PATH`.** Added by `.zshrc` with a duplicate guard.
  Nothing else puts it there — systemd's user environment does not carry it —
  and without it the binary sits on disk while `herdr` is not a command.
- **Claude Code integration.** If `claude` is on `PATH` at install time,
  `herdr integration install claude` adds a `SessionStart` hook to
  `~/.claude/settings.json` that reports the session id, so conversations resume
  into their native sessions after a server restart. Skipped if Claude Code is
  not installed; re-running will not install it twice.

**On a fresh install** Herdr does not autostart and nothing launches it — run
`herdr` in a terminal. Its keybindings only exist inside that session, so
`ALT + Tab` does nothing at all until you are in one.

#### Dev layouts

Four shell functions build a whole pane layout and start everything in it. They
live in `~/.config/zsh/herdr-layouts.zsh` and `.zshrc` sources them:

| Command | Layout |
| --- | --- |
| `hdl [agent] [agent2]` | editor ~70% on the left, agent(s) in the right column, terminal along the bottom |
| `hds [agent]` | a 2x2 square: editor, live `hunk diff --watch`, terminal, agent |
| `hdlm [agent] [agent2]` | one `hdl` tab per subdirectory of the current directory |
| `hsl <count> <command>` | `count` panes tiled in a grid, all running the same command |

The agent defaults to `claude`; `hdl codex` or `hdl claude codex` works too. Run
one from the pane you want to become the layout - `hds` splits the pane it is
called in, and renames the tab after the directory.

`hdl` is the everyday one. `hds` trades the terminal quadrant for a permanent
diff pane, which is worth it once an agent is actually writing code.

These drive Herdr over its socket API rather than through keybindings, so they do
not care what your `config.toml` keymap looks like.

**`hdl` starts an agent that a fresh install does not have.** This repo installs
no coding agent - `claude`, `codex` and the rest are applications, which are
deliberately out of scope, the same as the `SUPER + T` and `SUPER + R` binds. The
layouts print a one-line note for any command they are about to start that is not
on PATH (`herdr layout: 'claude' is not installed - its pane will be empty`) and
then build the layout anyway, so the pane is there to type in. Install the agent
you use and it fills itself. The same note appears for `nvim` or `hunk` if their
install options were off.

They are ported from Omarchy Quattro's `default/bash/fns/herdr` (omacom/omarchy,
MIT, DHH), with three deliberate differences. **They are zsh, not bash** - his
arrays are 0-indexed and zsh's are 1-indexed, so a verbatim copy of his `hsl`
would read an empty slot first and never reach the last column, silently building
one column fewer than asked. **The agent defaults to `claude`**, where his `hds`
hardcodes `opencode`. And **the editor is named `nvim` outright** rather than
`$EDITOR`, which is `vim` here - these layouts exist for the LazyVim file tree,
which vim does not have.

### Neovim and the file explorer

Herdr has no file browser. Its `goto` action is a session navigator, not a file
picker, and nothing in its config can open a tree. The file explorer sitting next
to the agents is **Neovim's**, drawn by `snacks.explorer`, which LazyVim ships
and binds to `Space E`. So the file tree is a Neovim question that happens to be
answered inside a Herdr pane.

Worth keeping the names straight, because they blur:

| Name | What it is |
| --- | --- |
| Neovim | the editor - the `nvim` binary |
| lazy.nvim | the plugin manager |
| LazyVim | a curated config built on lazy.nvim, cloned to `~/.config/nvim` |
| snacks.nvim | one of its plugins - the one drawing the tree |

There is no `lazyvim` command. You always run `nvim`.

The ones worth learning first:

- `Space E` - toggle the file tree (double-click opens; single click just moves the cursor)
- `Ctrl + W W` - hop between tree and editor
- `Space Space` - fuzzy-find a file
- `Space S G` - grep everything, with preview
- `Space G G` - lazygit in a floating pane
- `a` / `A` in the tree - new file / new directory, `?` for the rest

`neovim.sh` installs `tree-sitter-cli`, `stylua` and `shfmt` from the repos rather
than letting mason.nvim fetch them. mason installs asynchronously inside a running
nvim, and the headless `+Lazy! sync` the script runs exits the moment lazy is
done - which kills those installs mid-flight. That left nvim-treesitter reporting
a hard `❌ tree-sitter (CLI)` with no parsers and no highlighting. pacman installs
them synchronously and mason has nothing left to race. Parsers themselves are
*not* pre-fetched: on treesitter's `main` branch they install per language the
first time you open a matching file.

**The Neovim config is deliberately not tracked here.** The LazyVim starter is
meant to be forked and grown - `lua/plugins/*.lua` is yours - and vendoring a copy
would both freeze someone else's template and put `copy.sh`'s wholesale directory
replacement on top of your own plugin files on every re-run. `neovim.sh` clones
the starter once and never touches it again; an existing LazyVim config is left
completely alone, and any other `~/.config/nvim` is backed up rather than merged
over.

### Hunk (reading what the agents wrote)

The sidebar tells you an agent is working, done or blocked. It says nothing about
the code. [Hunk](https://github.com/modem-dev/hunk) is a review-first terminal
diff viewer for agent-authored changesets: a multi-file review stream with a file
sidebar and agent annotations beside the lines, and `--watch` re-renders as the
agent writes. `hds` parks it in a permanent quadrant.

- `hunk diff` - the working tree, `--watch` to auto-reload, `--staged` for the index
- `hunk show` - the last commit; `hunk log` - browse history
- `hunk pager` / `hunk difftool` - wire it into git itself

Like Herdr, it is not in the repos or the AUR. Upstream's one-liner pipes an
unread script into a shell, which this repo does nowhere else, so `hunk.sh`
resolves the release through the GitHub API, verifies the archive against the
published `SHA256SUMS`, and installs the binary to `~/.local/bin` - the same
checked path `herdr.sh` takes. A mismatch installs nothing. Update later with
`hunk update`.

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

The kernel module installed is `nvidia-open-dkms`. The closed-source
`nvidia-dkms` this script used to name no longer exists in the repos — only
the open modules do — and asking for the old name installed nothing while the
rest of the script still added the modules to `mkinitcpio.conf` and blacklisted
nouveau, so an NVIDIA machine rebooted with no GPU driver at all. The open
modules support Turing (GTX 16xx / RTX 20xx) and newer; anything older needs
`nvidia-390xx-dkms` or `nvidia-470xx-dkms` from the AUR, set by hand.

Note that enabling `nvidia` does **not** touch your bootloader. The driver's
`modeset=1 fbdev=1` settings are written to `/etc/modprobe.d/nvidia.conf`,
which the module reads when it loads and which works identically under
systemd-boot, limine, GRUB, rEFInd or a UKI. `nvidia.sh` used to also add those
as kernel parameters by editing `/etc/default/grub` and rewriting every
systemd-boot entry's `options` line; that was redundant with the modprobe
drop-in and is gone.

### After Installation

All configs are in `~/.config/`. Main files to edit:
- `~/.config/hypr/` - Hyprland configuration
- `~/.config/quickshell/bar/` - Custom bar configuration
- `~/.config/foot/` - Terminal configuration
- `~/.zshrc` - Shell configuration
- `~/.config/herdr/config.toml` - Herdr keybindings, sidebar rows, theme and sounds
- `~/.config/nvim/lua/plugins/` - your Neovim plugins (not tracked by this repo)
- `~/.config/zsh/herdr-layouts.zsh` - the `hdl` / `hds` / `hdlm` / `hsl` layout functions
- `~/.config/gtk-3.0/settings.ini` - GTK theme, font, cursor and dark-mode preference
- `~/.config/environment.d/locale.conf` - `LC_TIME`, i.e. the clock and calendar format
- `~/.config/fontconfig/conf.d/99-no-ligatures.conf` - turns coding ligatures off

## Troubleshooting

### When the installer stops without rebooting

A preset run that ends with

```
[WARN] NOT rebooting: the final check found missing packages.
```

did most of its work, but at least one package or component did not land. The
names are printed above that line and saved to
`Install-Logs/00_CHECK-*_installed.log`.

Three things feed that list. `02-Final-Check.sh` verifies a hardcoded set of
sixteen essential packages, which catches a package that was never even
attempted because its script was skipped or died early. Everything else on the
package side comes from `Install-Logs/.failed-packages`, which
`record_package_failure()` in `Global_functions.sh` appends to whenever any
`install_*` function's post-install verification fails — so the check covers
every package the install actually tried, not just the sixteen. Anything that
failed but was later pulled in as a dependency of something else is re-verified
and dropped from the list, so what you see is genuinely still absent.

The third source is the **outcome checks**: for each component the preset
selected, the script verifies the result rather than the package — the
dotfiles are actually in `~/.config`, `ly@tty2.service` is enabled and
`/etc/ly/config.ini` matches the repo, zsh is your login shell, the
`ru_RU.UTF-8` locale is generated, `systemd-resolved` is enabled, `sudo -n`
works, the icon and cursor themes are extracted. Each failure names the script
to re-run. These exist because the failures that hurt most were never
packages: a `copy.sh` that died left vanilla Hyprland with every package
"installed", and a `locales.sh` that was killed before it ran left the clock in
English — and both used to reboot as if nothing were wrong.

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

#### "Validating source files with sha256sums... FAILED"

Seen with `wallust` (2026-09-13). The package is hosted on Codeberg, and
Codeberg regenerates its release tarballs from time to time: same source,
different archive bytes, so the checksum written into the AUR PKGBUILD stops
matching. Nothing on your machine is wrong.

**The installer now handles this for allowlisted packages.** When a build fails
with makepkg's `One or more files did not pass the validity check!`, the
installer tells that apart from an ordinary build failure and checks the name
against `install-scripts/checksum-skip.conf`:

| in `checksum-skip.conf` | what happens |
|---|---|
| yes | rebuilt once with `--skipchecksums`, loudly, and the run continues unattended |
| no  | left alone; the final check names it and prints the exact command |

`wallust` is listed, so the case that actually recurs no longer interrupts an
unattended install.

It is an allowlist rather than a blanket retry on purpose. A checksum mismatch
means the downloaded bytes are not the bytes the maintainer signed off on -
usually a regenerated tarball, but that is also precisely what a tampered
source looks like, and the failure alone does not tell the two apart. A
PKGBUILD's `build()` runs as your user, and with `nopasswd_sudo="ON"` that is
effectively root, so "retry with verification off" is not something to do
automatically for all ~150 packages.

##### Adding a package to the allowlist

Only after checking the source really is unchanged:

```bash
yay -G <pkg>                      # fetch the PKGBUILD, do not build
cd <pkg> && makepkg -o --skipchecksums   # download + extract only
git clone <upstream-url> /tmp/<pkg>-git
git -C /tmp/<pkg>-git checkout <the tag the PKGBUILD pins>
diff -r src/<pkg>-<version> /tmp/<pkg>-git   # identical apart from VCS metadata
```

Then add the bare name to `install-scripts/checksum-skip.conf` with a comment
saying what you verified and when. Remove it once the AUR maintainer refreshes
the checksum - a stale entry keeps integrity checking off for a package that no
longer needs it.

##### Doing it by hand

```bash
yay -S wallust --mflags --skipchecksums
```

Then re-run `./install.sh --preset custom-preset.conf`; it skips everything
already installed. If the maintainer has already refreshed the checksum, plain
`yay -S wallust` works and the flag is unnecessary.

Note that `One or more PGP signatures could not be verified!` is a *different*
failure - a missing or untrusted signing key - and `--skipchecksums` does not
address it. The installer deliberately does not treat that as a checksum
problem; import the key instead.

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

`02-Final-Check.sh` is the post-install verification, and `install.sh` runs it
for you at the end of every run. To re-run it by hand, with the same selection
the shipped preset makes:

```bash
cd ~/Documents/my_archinstaller
INSTALL_SELECTED_OPTIONS="ly gtk_themes bluetooth thunar quickshell xdph zsh pokemon dots handy nopasswd_sudo printing" \
  ./install-scripts/02-Final-Check.sh
```

`verify-before-transfer.sh` is something else: it checks that the **repo** is
complete before you copy or push it (every script and asset present), not that
anything was installed. Run it on the old machine before you clone on the new one.

## Notes

- The installation backs up existing configs to `~/.config/<app>.backup-<YYYYMMDD-HHMMSS>`
  (one per run, never overwritten)
- Event-based monitoring reduces CPU usage significantly
- All scripts are logged to `Install-Logs/` (untracked - they are per-run output)
- First boot runs `initial-boot.sh` to set the wallpaper, run wallust, and apply
  the GTK, icon, cursor and Kvantum themes. It runs exactly once, guarded by
  `~/.config/hypr/.initial_startup_done`. That marker is gitignored on purpose:
  if it is ever committed, copy.sh deploys it to the new machine and the whole
  first-boot setup silently skips itself.
- Several packages the scripts name have moved from the official repos to the
  AUR since they were written (`wlogout`, `wallust`, `gtk-engine-murrine`). They still install, through `yay`, but they are now
  source builds and the most likely thing to fail on a given day — see
  [When the installer stops without rebooting](#when-the-installer-stops-without-rebooting).
