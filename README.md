# My Arch Installer

Automated Arch Linux installation with custom Hyprland setup.

Dates and times run on a Russian time locale (`LC_TIME=ru_RU.UTF-8`), which is
what gives the 24-hour clock, the Monday-first calendar and the Cyrillic day and
month names that match the Soviet theme. `LANG` stays `en_US.UTF-8`, so
interfaces are in English and only dates and times are localised. See
[Locales](#locales) to change it.

For the best results, you may want to:
-Install windows first (in case yo want to double boot), and limine as boot loader.
-Make sure Secure Boot is OFF!!
-Set on the BIOS Resizable Bar -> ON
-Set on the BIOS Memory Context restore (or DRAM Timing Control) to enabled.
This allows the computer not to check fully the RAM while booting which saves 50 seconds
-Set Power Down Enable to enabled

## Also works on CachyOS

This installs cleanly on top of a **CachyOS "No Desktop"** install and was
written with it in mind (it already knows about `tuned-cachy-ppd` and
`cachyos-hyprland-settings`). On the installer's **Additional packages** page,
select exactly this and nothing else:

- **CachyOS Packages**: keep `cachyos-settings`, `cachyos-micro-settings` and
  `cachyos-kernel-manager`. Uncheck `cachyos-hello`, `cachyos-packageinstaller`
  and `cachyos-wallpapers` (the dots ship their own wallpapers).
- **Base-devel + Common packages**: keep the **Network** and **hardware**
  sub-groups. Network gives you NetworkManager to get online on first boot.
  (`linux-firmware` itself comes with the installer's base packages whatever
  is ticked.) The other sub-groups are *not* all put back by the install
  scripts. The one that matters is **firewall**: CachyOS installs `ufw` and
  enables it with incoming connections denied, and nothing in this repo adds
  a firewall - untick it and the machine has none. Keep it ticked if you want
  one. Also gone for good when unticked: `rsync`, `alsa-utils`, `cpupower`,
  `upower`, `reflector` and some fonts.
- **Plymouth** (a group of its own in the installer's source since
  2026-09-23): leave it as it comes. The shipped preset boots in text
  ([Text boot](#text-boot)): `text-boot.sh` takes CachyOS's `quiet splash` off
  the kernel command line, so its watermark splash never shows, and plymouth -
  installed with the base packages even with the group unticked - just runs in
  text mode. With `plymouth="ON"` instead, `plymouth.sh` puts the repo's logo
  in place of the CachyOS one, and adds and wires plymouth itself if a later
  installer release no longer ships it.
- Uncheck everything else: the shell configuration, every desktop entry
  (especially **Hyprland** - it brings SDDM and its own bar, which would fight
  ly and the Quickshell bar), Firefox, both printing groups and accessibility.

If the machine has an NVIDIA GPU, the CachyOS installer already puts its
prebuilt kernel module (`linux-cachyos-nvidia-open`) on it. `nvidia.sh` sees
that and keeps it instead of installing `nvidia-open-dkms`, which would
conflict with it. That package covers one kernel, so any other installed kernel
without a module (a `linux-cachyos-lts` fallback, say) gets its own matching
prebuilt package (`linux-cachyos-lts-nvidia-open`). The rest of the NVIDIA setup
(mkinitcpio modules, modeset options, nouveau blacklist) runs the same either way. The NVIDIA environment
variables in `configs/ENVariables.lua` turn themselves on when every GPU in the
machine is NVIDIA *and* the proprietary driver is actually loaded, and stay off on
hybrid laptops. The driver check matters on the machines the installer leaves on
nouveau (`nvidia="OFF"`, Kepler-or-older cards, a DKMS build that failed on every kernel): forcing
NVIDIA's GLX library there broke every XWayland OpenGL app.

git is not part of that selection, so after the first login:

```bash
sudo pacman -Syu git
```

`-Syu`, not `-S`: against the package database from install day, the git
version it names may no longer be on the mirrors (404), once git has been
updated since.

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
- **Text Boot**: the kernel and systemd `[  OK  ]` lines on screen instead of the CachyOS splash - or, with `plymouth="ON"`, a **Boot Splash** with the repo logo (Plymouth, wired into boot where the distro did not set it up)
- **All Essential Packages** pre-configured

## Quick Install (Fresh Arch System)

### Prerequisites

- Fresh Arch Linux installation with the `base` system and a kernel
- Internet connection
- git installed (`sudo pacman -Syu git`; only `auto-install.sh` installs it for you)
- **A normal user account that can `sudo`** — see below

With `archinstall`, the choices that matter:

- **Profile: Minimal** - no desktop. Any desktop profile brings its own greeter
  (SDDM, GDM, ...), and while another login manager is running the installer
  skips ly.
- **Network configuration: Use NetworkManager.** Left at its default, the
  installed system boots with no network manager and no Wi-Fi tools - not even
  `pacman -Syu git` can work.
- **User account: mark it as superuser**, which gives it sudo (see below).
- Audio, power management and bootloader can stay as they are. PulseAudio is
  swapped for PipeWire by the installer, the bar's power widget works with
  `tuned` as well as `power-profiles-daemon`, and text-boot.sh (or plymouth.sh,
  for the splash) edits the kernel command line for systemd-boot, GRUB, Limine
  and rEFInd. With EFISTUB they say what to change in the boot entry by hand.
- **In a virtual machine**, turn on 3D acceleration: Hyprland needs it.

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
pacman -S --needed sudo nano                # base ships no editor, and visudo needs one
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
   mkdir -p ~/Documents && cd ~/Documents
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

   **You type your sudo password exactly once**, at the very start of the run
   (before anything is installed or detected), and never again. With `nopasswd_sudo="ON"` (the shipped preset)
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
   the session. With no terminal on stdin (nohup, `ssh host ./install.sh`
   without `-t`) it still waits the 15 seconds; Ctrl-C aborts. That works once
   passwordless sudo is in place (a re-run); the first run asks for the sudo
   password once, so it needs a terminal. The reboot goes
   through sudo, so it also works from an SSH session, where polkit would
   otherwise ask for a password. An interactive run (no `--preset`) still asks.

   If anything is missing, the installer **stops instead of rebooting** and
   leaves the list on screen. This matters because a package or script failure
   is not fatal on its own — the install carries on — so rebooting would
   scroll the only warning away and hand you a desktop that is subtly wrong
   with nothing on screen saying why. The screen is no longer cleared before
   the check, so whatever a script printed during the run is still above it. See
   [When the installer stops without rebooting](#when-the-installer-stops-without-rebooting).

4. **Fill in your machine-local secrets.**

   The installer creates `~/.config/zsh/secrets.zsh` for you from
   `Hyprland-Dots/config/zsh/secrets.zsh`, mode `600`, with **every line
   commented out** and fake values. Open it, uncomment the keys you use and
   replace their values with the real ones:

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
- ly display manager with large font. Its session list is Hyprland only: ly
  ignores `TryExec` and uwsm is not installed, so `pacman.sh` adds
  `NoExtract = usr/share/wayland-sessions/hyprland-uwsm.desktop` to
  `/etc/pacman.conf`, and `ly_config.sh` removes any copy already on disk.
  Delete that line if you ever install uwsm. The login-screen flag is cut per
  console grid (768p, 900p, 1080p, 1440p, 2160p), and the largest cut that fits
  the panel is installed. Which flag waves is the preset's `ly_flag` (or, when
  ly is ticked, an fzf picker with a live preview of each flag), one of the `<name>-flag-*.dur` sets in `assets/ly` -
  most of Europe, the Soviet Union and Russian Empire, China, Vietnam, both
  Koreas and Israel (the full list is `FLAGS` in `assets/ly/soviet-flag.py`).
  Colours the console lacks - near-black, gold, light blue, orange - come from
  palette slots set in `assets/ly/start.sh`. All of them are installed;
  `flag-switch.sh <flag>` changes it later and `flag-preview.sh <flag> animated`
  shows one on a spare VT.
- PipeWire audio
- NetworkManager, as the only network manager (see [Network](#network)), plus
  `nss-mdns`, wired into `nsswitch.conf` for `.local` names, and
  `systemd-resolved` — see [DNS](#dns)
- `wireless-regdb`, the Wi-Fi regulatory database (`00-base.sh`). Plain Arch's
  pacstrap leaves it out, so Wi-Fi stays on the restrictive world domain;
  CachyOS already has it through `cachyos-settings`.
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
- LibreWolf (browser, `extra/librewolf` — `librewolf-bin` no longer exists in the AUR).
  Set up from `config/librewolf/`: `copy.sh` puts `librewolf.overrides.cfg` in the
  profile root, and `chrome/userContent.css` and `chrome/userChrome.css` in the
  profile. On a fresh install it starts LibreWolf once headless so that the
  profile exists. What that gives you:
  - the new tab page has 2 rows × 10 pinned sites with wider gaps between them,
    and it is also the start page;
  - the pre-157 look (the "Nova" redesign off), in LibreWolf's own dark colours
    rather than the GTK theme's;
  - the drop-down of saved logins under a field stays dark (157 started to colour
    it like the page's input box, which resistFingerprinting makes white);
  - Google's sign-in skips resistFingerprinting, so it can be dark;
  - WebRTC is locked off.
- vim (the `$EDITOR` the Hyprland config names) and nano
- Thunar (file manager)
- btop, cava, fastfetch
- mpv, pavucontrol
- satty (screenshot annotation editor)
- Handy (offline speech-to-text — Parakeet V3, auto-detects 25 languages)
- Herdr (terminal workspace manager for AI coding agents — a static binary from
  herdr.dev, not a repo or AUR package, see [Herdr](#herdr-terminal-workspace-manager))
- Neovim + LazyVim, with ripgrep, fd, lazygit, tree-sitter-cli, stylua, shfmt
  and rust-analyzer (the LazyVim Rust extra is enabled)
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
`Qt.locale()`. The bar's *clock* does not — `components/CenterInfo.qml` formats `"HH:mm"`
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
| `JetBrainsMono Nerd Font` | `ttf-jetbrains-mono-nerd` | dunst |
| `Fira Code` | `ttf-fira-code` | `gtk-3.0/settings.ini` - but see below |

`gtk-3.0/settings.ini` asks for `Fira Code Semi-Bold`, and two things stand in
its way: `fontconfig/conf.d/99-no-ligatures.conf` maps every `Fira Code` request
to `JetBrains Mono NL` (Fira Code has no ligature-free cut), and on Wayland
GTK takes its font from gsettings, which `initial-boot.sh` sets, rather than
from `settings.ini`.

To change the bar's font, edit `fontFamily` in
`Hyprland-Dots/config/quickshell/bar/Theme.qml` — every widget renders through
it — and add the package to `fonts.sh` and the family to `required_families`
in the same file.

One place names a font that is **not** installed and never has been:
`config/rofi/themes/LonerOrZ.rasi` asks for `Iosevka`. It renders substituted
here already, so this is inherited from upstream rather than something the
install broke. (The quickshell overview takes its fonts from
`overview/common/Appearance.qml`, which asks for plain `sans-serif`.)

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
Intel (plus `libva-intel-driver` for pre-Broadwell chips, which
`intel-media-driver` does not support; libva picks whichever one fits), `vulkan-radeon` on AMD (VA-API for AMD now comes from `mesa` itself,
which is why there is no `libva-mesa-driver` here: `mesa` provides that name, so
asking for it only resolves to `mesa`), plus the `lib32-` variants (multilib is
enabled by `pacman.sh`, which runs first). The proprietary NVIDIA driver is not
handled here - `nvidia.sh` owns that, and the preset's `nvidia` option defaults
to `auto`, see [Hardware options](#hardware-options) - but an NVIDIA card that
stays on nouveau gets Mesa's Vulkan driver for it (`vulkan-nouveau`).

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
edited. The microcode step does not write to any bootloader, on purpose: a malformed
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

After rebooting:

```bash
journalctl -k -b | grep microcode      # "Current revision: 0x..."
```

"microcode updated early" appears only when the package carries a newer
revision than your firmware already has. With current firmware a correct setup
never prints it - the line above with no "updated early" is normal, not a sign
that the microcode image is not loaded.

### Network

`services.sh` makes NetworkManager the only network manager. A plain Arch installed
with archinstall's *Copy ISO network configuration* comes up with iwd +
systemd-networkd enabled (a hand-rolled one may use dhcpcd), and leaving those
enabled next to NetworkManager made wpa_supplicant fight iwd for the Wi-Fi card and
two DHCP clients fight over each link after the reboot. So when iwd is enabled,
NetworkManager is switched to the iwd Wi-Fi backend
(`/etc/NetworkManager/conf.d/wifi_backend.conf`, `wifi.backend=iwd`, the same
layout archinstall's *NetworkManager (iwd backend)* choice writes) and
`iwd.service` is disabled, since NetworkManager starts iwd itself. The Wi-Fi
networks iwd already saved keep working. systemd-networkd and dhcpcd are disabled.
None of it is stopped during the install: NetworkManager takes over at the reboot,
so the running install keeps its connection. On CachyOS none of this applies
(NetworkManager already runs alone).

A networkd link with a static `Address=` (archinstall's *Manual configuration*) is
carried over rather than dropped, since NetworkManager would only run DHCP there:
each such `.network` file becomes a NetworkManager profile,
`/etc/NetworkManager/system-connections/networkd-<file>.nmconnection`, built with
`nmcli --offline`, and networkd is then disabled like the rest. The original
`.network` files stay where they are, unused. The conversion only runs when it can be
exact: one `[Match] Name=` naming a physical ethernet card, `Address=` with a prefix
length, at most one gateway per address family, plain `DNS=` / `Domains=` entries,
and nothing else. IPv6 stays on router advertisements with EUI-64 addresses, as it
was under networkd, and the profile gets `autoconnect-priority=100` so an older DHCP
profile cannot win the link. A glob or MAC match, an extra route, `DHCP=` next to the
static address, a `.netdev` (bridge, VLAN, bond), a drop-in (`*.network.d/`), another
`.network` file that could match the same card (networkd only applies the first
match) or any other key keeps networkd, and then
`services.sh` does not enable NetworkManager at all, the same as for netctl below. The
reason is printed, and the final check stops the preset's auto-reboot.

netctl, connman, `wpa_supplicant@<if>`, and dhcpcd with its `10-wpa_supplicant`
hook linked into `/usr/lib/dhcpcd/dhcpcd-hooks/` are **not** handed over: they keep
the Wi-Fi password in `/etc/netctl/`, `/var/lib/connman/` or `/etc/wpa_supplicant/`,
which NetworkManager cannot import, so switching would boot a Wi-Fi-only laptop
with no network. With one of those enabled, `services.sh` changes nothing and does
not enable NetworkManager; the final check then stops the preset's auto-reboot, and
a reboot by hand comes back on the old setup. The warning prints the commands to
switch by hand (`sudo systemctl disable --now <units> && sudo systemctl enable --now
NetworkManager.service`, then `nmcli device wifi connect <SSID> password
<password>`). Check with:

```bash
systemctl is-enabled systemd-networkd iwd dhcpcd 2>/dev/null   # disabled / not-found
NetworkManager --print-config | grep wifi.backend             # wifi.backend=iwd if iwd was in use
```

Known limit: the bar's Wi-Fi share-QR cannot read the password of a network that
only iwd saved; reconnecting to it once through the bar or nmcli fixes that.

### DNS

`01-hypr-pkgs.sh` installs `systemd-resolvconf`, which replaces the classic
`resolvconf` with a shim over `resolvectl` — and that shim only works while
`systemd-resolved` is running. Arch's NetworkManager never goes through
resolvconf (it is built to write `/etc/resolv.conf` itself), so ordinary DNS
keeps working either way. What needs the daemon is `wg-quick`: it hands the
`DNS=` line of every WireGuard config here to resolvconf, and without resolved
that fails - the bar's VPN selector brings a tunnel up whose DNS goes nowhere.

`services.sh` therefore enables `systemd-resolved` and points `/etc/resolv.conf`
at its stub whenever `systemd-resolvconf` is installed. This machine only ever
worked because resolved had been enabled by hand, months before the installer
existed — which is exactly the kind of gap a fresh install exposes. Check with:

```bash
resolvectl status | head -5     # should list a DNS server per link
readlink /etc/resolv.conf       # /run/systemd/resolve/stub-resolv.conf
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
`power-profiles-daemon` only when nothing does. The bar's widget talks to the
daemon over D-Bus (`busctl`) rather than through `powerprofilesctl`, so
`tuned-ppd` - archinstall's "tuned" choice, which serves the same API but ships
no `powerprofilesctl` - works as well as `power-profiles-daemon`.

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
| `/etc/sudoers.d/battery-charge-limit` | Lets the bar run exactly that helper without a password, so the picker works even with `nopasswd_sudo="OFF"`. Validated with `visudo` before it is installed |
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

On ASUS laptops `asusd` (installed by the `rog` option) keeps a charge limit of
its own and writes it back at boot and after resume. The helper therefore also
sets asusd's limit (`asusctl battery limit N`) whenever it sets or re-applies
yours, and the unit runs after `asusd.service`, so the two never disagree. The
charge slider in rog-control-center drives the same setting; the bar's picker
wins at the next boot or resume, so pick one of them and stick to it.

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

### Text boot

The shipped preset has `text_boot="ON"` and `plymouth="OFF"` (also the defaults
in the interactive menu). After the bootloader menu the screen shows the
kernel's messages and systemd's `[  OK  ] Started ...` lines up to ly, as on a
plain Arch install, instead of a splash.

CachyOS boots with `quiet splash`: `quiet` hides those lines, and `splash` starts
plymouth's graphical screen - the CachyOS watermark - over them.
`install-scripts/text-boot.sh` takes those two words off the kernel command
line wherever the machine keeps one: `KERNEL_CMDLINE` in `/etc/default/limine`
(or `/etc/limine-entry-tool.conf`) for Limine's entry tool, a `limine.conf`
nothing generates, `/etc/kernel/cmdline` (UKIs), this system's systemd-boot
entries and `/etc/sdboot-manage.conf`, `refind_linux.conf`, and
`GRUB_CMDLINE_LINUX(_DEFAULT)` in `/etc/default/grub` (then `grub-mkconfig`).
Each edit removes the two words and nothing else: it is checked line by line
before it is written, and for Limine's entry tool and GRUB the command line
the tool itself computes has to come out as before minus the two words, or the
file goes back. The original is kept as `<file>.pre-text-boot`. Limine's
entries (and UKIs) are then regenerated, and the generated `limine.conf` is read
back. A failure is recorded as `text-boot` and stops the preset's auto-reboot.
Snapshot boot entries (limine-snapper-sync on btrfs) and GRUB entries of other
systems (os-prober) or written by hand (40_custom) are left as they are and not
counted: no edit here reaches them, and a snapshot boots the way the system was
when it was taken.

Plymouth is not removed where the distro installed it: without `splash` it runs
in text mode, and the LUKS password prompt is a plain text one. Selecting both
options keeps the splash: install.sh drops `text_boot` from the run.

It also takes the `kms` hook out of the initramfs, through
`/etc/mkinitcpio.conf.d/zz-my_archinstaller-text-boot.conf`. That hook packs the
GPU drivers into the image, so the driver took the screen over while the LUKS
prompt was up - on the RX 6700 XT about 2.5 s of black screen (the card's own
initialisation; `amdgpu.seamless=1` does not avoid it) in the middle of typing
the password. Without it the prompt stays on the firmware framebuffer, and the
driver loads from the root filesystem after the unlock, so the blackout moves
to among the `[  OK  ]` lines. The image also gets much smaller (no GPU
firmware). The NVIDIA proprietary driver is not in that hook either way. Delete
the drop-in and rebuild to put `kms` back.

To go back to a splash, run `./install-scripts/plymouth.sh` (it adds `splash`;
add `quiet` yourself if you want it), or copy the `.pre-text-boot` files back
and regenerate (`sudo limine-mkinitcpio` with Limine's entry tool).

### Boot splash (Plymouth)

The `plymouth` preset option installs a Plymouth theme (`assets/plymouth/soviet/`)
that paints the repo logo (from `icons/`) on black, with the stock spinner
and the LUKS password prompt underneath. It is what you see between the
firmware and ly.

On CachyOS the stock theme keeps the motherboard's own logo (the ACPI BGRT
image) as background and adds a CachyOS watermark at the bottom. This theme
ignores the firmware image entirely, so disabling **Boot Logo Display** in the
BIOS leaves only black, then the logo. That is the closest you can get to a
custom vendor logo without flashing modified firmware, which ASUS boards reject
through every official path.

- `plymouth="ON"` (`OFF` in the shipped preset and unticked in the interactive
  menu since 2026-10-08, which boot in [text](#text-boot) instead) puts the logo
  on every machine. It installs plymouth and the theme, and
  where the distro did not set plymouth up - plain Arch - it also wires it into
  boot, since a theme alone is never drawn:
  - **the hook:** a drop-in, `/etc/mkinitcpio.conf.d/zz-my_archinstaller-plymouth.conf`,
    puts `plymouth` right after `systemd` (or `udev`) in whatever `HOOKS` you
    have, which also keeps it ahead of `encrypt`/`sd-encrypt` for the LUKS
    prompt. A preset that runs mkinitcpio with its own config file (`-c`, which
    skips drop-ins) gets the same lines appended to that file instead. Whether
    it took is checked the way mkinitcpio reads its config - the files joined
    in its own order and sourced once - so a later drop-in that sets `HOOKS`
    again is caught, not missed.
  - **`splash` on the kernel command line**, wherever the machine keeps one:
    the `options` line of each systemd-boot entry that boots one of this
    system's kernels (another system's entries on a shared ESP are left alone),
    `LINUX_OPTIONS` in CachyOS's `/etc/sdboot-manage.conf`,
    `GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub` (then `grub-mkconfig`,
    with `grub.cfg` backed up first), the `cmdline:` lines of a `limine.conf`
    that nothing generates, a `KERNEL_CMDLINE[default]+="splash"` line in
    `/etc/default/limine` where Limine's entry tool writes the entries
    (CachyOS), each boot option of rEFInd's `refind_linux.conf`, and
    `/etc/kernel/cmdline` for UKIs. Each edit adds that one word
    and nothing else, and that is checked on the command line the boot tool
    actually computes, not only on the file's text: Limine's entry tool is
    asked for every kernel's command line before and after
    (`limine-entry-tool --get-cmdline`), and GRUB's file is sourced the way
    `grub-mkconfig` reads it. An edit that would change anything else - a
    blank `KERNEL_CMDLINE` that would leave the kernel with only `splash`, an
    `export`ed GRUB variable - is not written, or is put back. The original is
    kept as `<file>.pre-plymouth`. `quiet` is not added, and a `splash=verbose`
    (plymouth's "text, please") is kept.

  When one of these cannot be done (a form of the file it does not edit, a
  per-kernel `KERNEL_CMDLINE` override), the script says what to add by hand,
  and the final check stops the auto-reboot with `plymouth-splash` or
  `plymouth-hook`. A bootloader it does not know at all (EFISTUB) does not
  stop the reboot: when this boot's own command line has no `splash` either,
  the script says to add it to the boot entry by hand, and until then
  plymouth shows its text screen instead of the logo.
- `plymouth="auto"` acts only where plymouth is already installed **and** in the
  mkinitcpio `HOOKS`, as on CachyOS, and does nothing on plain Arch.

To take the wiring out again: delete the drop-in, remove the word `splash` from
the command line in the files the run reported, then rebuild with
`sudo mkinitcpio -P` (and `sudo grub-mkconfig -o /boot/grub/grub.cfg` on GRUB,
`sudo limine-mkinitcpio` with Limine's entry tool). Removing the word is safer
than copying the `.pre-plymouth` files back: a `limine.conf.pre-plymouth` was
taken before `limine.sh` added its theme, and an entry file may have been
rewritten by a kernel update since.

Only `soviet.plymouth` and the pictures are in the repo; the spinner frames and
dialog artwork are copied at install time from plymouth's own `spinner` theme.
The pictures sit with `LOGO.JPG` in `icons/`, and the one that matches the
screen is installed as the theme's `watermark.png`:

| Panel | File | Size |
|---|---|---|
| 1080p | `icons/gopnik-watermark-1080p.png` | 468x620 |
| 1440p | `icons/gopnik-watermark-1440p.png` | 649x860 |
| 2160p (4K) | `icons/gopnik-watermark-2160p.png` | 1011x1340 |

Plymouth draws the watermark at its native pixel size - only the anchor
(`WatermarkVerticalAlignment`) is a fraction of the screen - so the height has
to match the panel. `plymouth.sh` reads the preferred mode of every connected
DRM connector from `/sys/class/drm/*/modes` (which works in a TTY, with no
compositor running) and picks by the **smallest** connected screen, since
plymouth paints the same image on every display. Each cut is the tallest that
still clears the password prompt, so all three fill the same fraction of their
screen.

A 4K panel small enough to be HiDPI (plymouth's own guess, roughly >192 dpi)
makes plymouth double everything, which halves the logical screen and makes the
1080p cut the right one; `plymouth.force-scale=1` on the kernel command line
overrides that guess.

To change the picture, re-render from `icons/aisaka.icon` (the 1920x1920
original, so the cuts stay downscales) at the heights in the table and re-run:

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
shipped preset) applies it wherever a `limine.conf` exists - `/boot`, `/efi` or
`/boot/efi` (also in a `limine/` subdirectory), or next to the EFI binary in
`<ESP>/EFI/<dir>/`, where archinstall puts it (`EFI/arch-limine/`, or `EFI/BOOT/`):
wallpaper onto the root of the partition holding the conf (Limine's `boot():/`),
theme block prepended, and `timeout: no` so the menu waits for a choice instead of
booting the default after a countdown. This is one of the two places the repo edits a
bootloader config (the other is the `splash` word [Plymouth](#boot-splash-plymouth)
adds), added knowingly on 2026-09-13; the safeguards are a backup kept
as `limine.conf.pre-theme` (a record, not a restore point - see the revert note
below), an edit confined to the marked block plus the `timeout:`
line, a before/after comparison of the OS entries that aborts the write if they
differ, and a re-enroll when `ENABLE_ENROLL_LIMINE_CONFIG` is on. That setting
is read from `/etc/default/limine` only, the one place `limine-entry-tool` takes it
from (it blanks the value after reading `/etc/limine-entry-tool.conf` and its
drop-ins). An unenrolled hash is a menu Limine refuses at boot. Re-running replaces the block rather than duplicating it, and keeps
anything that sits above it (a `default_entry:` at the very top, for example).
To do it by hand instead:

```bash
sudo cp assets/limine/limine-wallpaper.png /boot/limine-wallpaper.png   # /boot is the ESP on CachyOS
sudo cp /boot/limine.conf /boot/limine.conf.pre-theme
cat assets/limine/theme.conf <(sudo cat /boot/limine.conf) | sudo tee /boot/limine.conf.new >/dev/null && sudo mv /boot/limine.conf.new /boot/limine.conf
sudo sed -i 's/^timeout: .*/timeout: no/' /boot/limine.conf
# Enrolled config (ENABLE_ENROLL_LIMINE_CONFIG=yes in /etc/default/limine)? Then
# the new hash must be enrolled, or Limine refuses the edited file at boot:
grep -qE '^\s*ENABLE_ENROLL_LIMINE_CONFIG\s*=\s*"?yes' /etc/default/limine 2>/dev/null && sudo limine-enroll-config
```

`limine-entry-tool` only rewrites the kernel entries under the CachyOS heading, so
the global block survives kernel updates (`timeout` and `default_entry` already do).
A missing wallpaper is skipped silently, an unknown key is ignored, so a typo
degrades the look rather than the boot. The selected entry is drawn in reverse video,
which is why the highlight bar takes the `term_foreground` colour. Limine still draws
its box frame around the entries; that is part of the program, not the theme.

Revert it with `./install-scripts/limine.sh --revert`. That takes the marked block
out of the *current* limine.conf, puts back the `timeout:` line from before the
theme (recorded inside the block when it was written), and removes the wallpaper.
Do not copy `limine.conf.pre-theme` back instead: it is the first-ever backup, and
on CachyOS every entry carries a BLAKE2 hash (`ENABLE_VERIFICATION=yes` in
`/etc/limine-entry-tool.conf`). After the next kernel or initramfs update those
hashes are stale, and Limine panics on every entry of the restored file.

### Windows boot logo (HackBGRT)

On a Limine dual boot, Windows showed its own logo at boot instead of the
firmware's. Windows does not keep a logo of its own choosing: it redraws the
firmware's (the ACPI BGRT image), but only when the firmware says it is still
on screen - and started through Limine it is not, since Limine's menu was drawn
over it. The `hackbgrt` option (`install-scripts/hackbgrt.sh`, `auto` in the
shipped preset: on wherever `limine.conf` has a Windows entry whose partition
the script can find - `guid()`, `uuid()`, `fslabel()`, `boot()` or `boot(<n>)`,
not the firmware-numbered `hdd()` - and Secure Boot is
off) installs [HackBGRT](https://github.com/Metabolix/HackBGRT) (MIT), a small
EFI program that runs right before Windows' boot manager and hands it our
picture. Windows draws it pixel for pixel, with its spinner underneath.

- HackBGRT 2.6.0 is downloaded and checked against a pinned sha256.
- `splash.bmp` is rendered for the panel: the Plymouth watermark cut that
  `plymouth.sh` would pick (`icons/gopnik-watermark-*.png`), at the place the
  soviet Plymouth theme draws it (centred, 5 % from the top), on a black image
  the size of the panel - so Windows' boot screen looks exactly like the
  Plymouth splash did. `config.txt` sets that resolution explicitly: with
  "current" HackBGRT cropped the picture to the lower mode Limine leaves the
  screen in, and only a corner of it showed.
- `loader.efi`, `config.txt` and `splash.bmp` go to `EFI/HackBGRT/` on the
  partition Windows' boot manager is on; `boot=MS` starts
  `\EFI\Microsoft\Boot\bootmgfw.efi` from there. Windows' own files are not
  touched.
- The Windows entry's path in `limine.conf` is pointed at
  `EFI/HackBGRT/loader.efi` (the original kept as `limine.conf.pre-hackbgrt`;
  an enrolled config is re-enrolled). Limine's tools never regenerate that
  entry, so kernel updates leave it alone. If one ever adds a second, plain
  Windows entry (limine-entry-tool's `FIND_BOOTLOADERS`), a re-run of the script
  points that one at HackBGRT too.

The firmware's own boot menu (F8 on ASUS -> Windows Boot Manager) still starts
Windows without HackBGRT. To take it out: point the entry back at
`/EFI/Microsoft/Boot/bootmgfw.efi` and delete `EFI/HackBGRT/` on that partition.
With Secure Boot on, HackBGRT needs shim and a key enrolled by hand at boot (its
`shim.md`), so the script skips it. After a monitor change, re-run
`./install-scripts/hackbgrt.sh` to render the picture for the new panel.

### BIOS logo

The very first picture at power-on, before Limine, is drawn by the motherboard
firmware. `bios-logo/mod-bios-logo.sh` puts our own picture into a copy of the
board's stock firmware file, so a USB stick can flash it. It is vendor-independent
for the image surgery (AMI Aptio V, which ASUS, Gigabyte, MSI and ASRock all use);
the vendor-specific parts - where to download the stock file, what to name it,
which button flasher writes a modified image - are in `bios-logo/README.md` and
`bios-logo/boards.conf`. Not part of `install.sh` on purpose: it is a firmware
flash, and the user presses the button. The target look is the same picture, at
the same size and place, as the Plymouth splash and the Windows boot screen
([HackBGRT](#windows-boot-logo-hackbgrt)).

**The pictures in `icons/`**

| File | What it is |
|---|---|
| `aisaka.icon` | The source: the girl, 1920x1920 PNG with transparency (content 1449x1920). Everything below is cut from it. |
| `gopnik-watermark-1080p.png` | 468x620 cut, for panels under 1440 px tall |
| `gopnik-watermark-1440p.png` | 649x860 cut, for 1440p panels (the one Plymouth showed on the desktop) |
| `gopnik-watermark-2160p.png` | 1011x1340 cut, for 4K panels |
| `gopnik-bios.bmp` | The 1080p cut as a 24-bit BMP, 468x620 - the logo of an earlier flash (too small; see "Auto vs Full Screen") |
| `LOGO.JPG` | The potato - `mod-bios-logo.sh`'s default `--logo`, and the first logo flashed |

The cuts are what `plymouth.sh` and `hackbgrt.sh` pick from by panel height, so
the firmware logo should use the same one.

**Auto vs Full Screen** (learned on the ASUS TUF B650M; check on other boards)

The firmware does not draw the stored bitmap 1:1. With *Boot Logo Display = Auto*
it fits any logo into a 1024x576 box in the middle of a 2560x1440 screen - the
stock 672x378 logo was enlarged into it, a 468x620 one shrunk to 434x576. With
*Full Screen* it scales the logo to the whole screen. So the logo that looks right
is a **full-screen image at the panel's resolution** - drawn 1:1 in Full Screen
mode - with the girl at her Plymouth size and place: the watermark cut, centred,
5 % from the top (the soviet theme's `WatermarkVerticalAlignment=.05`), on black.
It is 10 MB as a BMP but mostly black, so it LZMA-compresses to ~176 KB in the
firmware.

**Making a flashable BIOS on a new computer** (for an agent; the user only
presses the button at the end)

1. Board, vendor, BIOS version, current logo:
   ```bash
   bios-logo/mod-bios-logo.sh detect
   ```
   Look the board up in `bios-logo/boards.conf`, else in the vendor table in
   `bios-logo/README.md`. **Stop if the board has no button-driven recovery
   flasher** (ASUS FlashBack, Gigabyte Q-Flash Plus, MSI Flash BIOS Button,
   ASRock BIOS Flashback): most laptops and budget boards can only flash signed
   images, and a bad flash there is not recoverable. ThinkPads take a custom logo
   through Lenovo's own updater instead.
2. Get the stock firmware: the vendor's download for that exact board, normally
   the **same version** the board runs now (`detect` shows it), so the logo is the
   only change. The README's vendor table and `boards.conf` give the download URL
   and the file name the flasher wants (ASUS: e.g. `TG650MPW.CAP`). Unzip it.
3. The panel's resolution - the preferred (first) mode of the connected display:
   ```bash
   for c in /sys/class/drm/card*-*; do [ "$(cat $c/status)" = connected ] && head -1 $c/modes; done
   ```
4. The full-screen picture: a black image the size of the panel, with the
   watermark cut made for that panel pasted at the place Plymouth draws it.

   - **Which cut:** the one named after the panel's height - 4K
     (3840x2160) takes `gopnik-watermark-2160p.png`, 1440p takes
     `gopnik-watermark-1440p.png`, 1080p takes `gopnik-watermark-1080p.png`. A
     panel between those sizes takes the cut for the next size *down* (a 1600 px
     tall one, the 1440p cut), so she is never taller than Plymouth made her for
     that height.
   - **Where it goes** (`x`, `y` = the cut's top-left corner, in pixels from the
     screen's top-left corner):
     - `x` = (screen width - cut width) / 2: the space left over, half on each
       side, so she is centred left-to-right. Rounded down.
     - `y` = (screen height - cut height) * 0.05: the soviet Plymouth theme puts
       her 5 % of the way down the leftover space (`WatermarkVerticalAlignment=.05`
       in `assets/plymouth/soviet/soviet.plymouth`), i.e. near the top, where the
       password box used to be below her. Rounded down.

   | Panel | Cut | Cut size | x | y |
   |---|---|---|---|---|
   | 1920x1080 | `gopnik-watermark-1080p.png` | 468x620 | (1920 - 468) / 2 = **726** | (1080 - 620) * 0.05 = **23** |
   | 2560x1440 | `gopnik-watermark-1440p.png` | 649x860 | (2560 - 649) / 2 = 955.5 -> **955** | (1440 - 860) * 0.05 = **29** |
   | 3840x2160 | `gopnik-watermark-2160p.png` | 1011x1340 | (3840 - 1011) / 2 = 1414.5 -> **1414** | (2160 - 1340) * 0.05 = **41** |

   Then, for the panel in the table's middle row (the desktop's):
   ```bash
   magick -size 2560x1440 xc:black icons/gopnik-watermark-1440p.png \
          -geometry +955+29 -composite -type TrueColor PNG24:logo.png
   ```
   `-size 2560x1440 xc:black` is the black screen, `-geometry +955+29` is `+x+y`
   from the table, and `-composite` pastes the cut there (its transparent
   background lets the black through). For 4K: `-size 3840x2160`, the 2160p
   cut, `+1414+41`.
   (Saved as a BMP instead - `-define bmp:format=bmp3 -compress none
   BMP3:new-logo.bmp` - this is byte for byte the `new-logo.bmp` in the desktop's
   firmware.)
5. Build. Never flashes anything; every check failing says "do NOT flash":
   ```bash
   bios-logo/mod-bios-logo.sh build --image <stock file> --logo logo.png --colors full --keep-size
   ```
   Output in `~/Downloads/bios-mod-<board>/`: `modded/<NAME>` (to flash),
   `stock/<NAME>` (the recovery file), `modded/new-logo.bmp` and a preview -
   look at the preview. `--keep-size` (a logo of a size other than the stock
   one) is only proven on the TUF B650M. On another board the first flash is the
   test; if the logo then does not show, the safe build is the same command
   without `--keep-size` (fitted into the stock logo's size: works anywhere, but
   small in Auto mode). If full colour does not fit the board's free space, the
   build steps down to 64, 32 and 16 colours by itself; `--colors 256` is the
   better first step down for a cartoon (indistinguishable at boot).
6. The stick. **Erases it** - say which device and what is on it, and get the
   user's OK first:
   ```bash
   bios-logo/mod-bios-logo.sh usb --device /dev/sdX --file ~/Downloads/bios-mod-<board>/modded/<NAME>
   ```
7. The user flashes with the vendor's button procedure (README vendor table).
   Before: suspend BitLocker if Windows uses it, and note the BIOS settings -
   the flash resets them all.
8. After: in the BIOS set **Boot Logo Display = Full Screen**, and the settings
   from before again (on the desktop: EXPO, Memory Context Restore, integrated
   graphics off, Limine first in the boot order).
9. Check from Linux what the firmware drew: `/sys/firmware/acpi/bgrt/image` (a
   BMP), `xoffset`, `yoffset`. Full Screen with a matching logo shows the full
   `W`x`H` image at 0,0. Once it is confirmed, record the board, the command and
   the sha256 in `bios-logo/boards.conf` - that file is the record of which
   boards accept what.

Redo it after every BIOS update: a stock update puts the vendor logo back. The
build for the desktop (TUF GAMING B650M-PLUS WIFI, BIOS 3886) is in `boards.conf`,
and reproduces its sha256.

### Printing

`install-scripts/printing.sh` installs `cups`, `cups-filters` and `cups-pdf`.
Nothing else in the install pulls in a print stack, so without it every
application's print dialog opens with an empty printer list and no way to add
one — which is easy to miss for weeks, because nothing looks broken until the
first time you try to print. `cups-pdf` also gets a `PDF` queue (`lp -d PDF`, or
pick it in any print dialog); its files land in `/var/spool/cups-pdf/$USER/`.

Like Docker, CUPS is **socket-activated** rather than enabled at boot: `cupsd`
is idle almost all the time on a laptop, so `cups.socket` and `cups.path` start
it on demand — the first print dialog, `lp` or `lpadmin` call brings it up.
Port 631 is not a trigger: `cups.socket` listens only on `/run/cups/cups.sock`,
so where cupsd has never run, <http://localhost:631> is refused until
`sudo systemctl start cups`. Once cupsd has run it stays up (with the stock
`WebInterface Yes` it never idle-exits), and `cups.path` starts it at every later
boot. The installer adds the `PDF` printer, which is that first run, so after the
install reboot the web UI is simply there.

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
It ships the full set in use on this machine (51 files, about 138 MB,
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
  whatever monitors the new machine has. Once you have, a re-run of the
  installer keeps it: `copy.sh` restores `monitors.lua` and `workspaces.lua`
  from the `hypr` backup instead of resetting them to the template.
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
  `wallust/output/colors-waybar.css` and
  `quickshell/bar/wallust-colors.json`. Every one is a `target` in
  `wallust.toml`, rewritten in full each time the wallpaper changes, so they are
  runtime state and are gitignored — otherwise whichever palette happened to be
  up got committed and the next wallpaper change dirtied the tree, which
  `auto-install.sh` then refuses to pull over.

  Most of them still have to *exist*: twelve rofi themes `@theme`
  `colors-rofi.rasi` and wlogout's `style.css` `@import`s `colors-waybar.css` —
  a missing file there is an error on first launch, not a silent fallback.
  (`UserDecorations.lua` is the exception: it loads `wallust-hyprland.lua`
  through `pcall` and falls back to a built-in palette.) So a rendered snapshot
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
end up owned by your user and world-readable. `wg-quick` does not refuse such a
config: it prints a warning (only when the folder is world-accessible too) and
brings the tunnel up anyway, with the private key readable by everyone. The
chmod is what protects the key:

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

**Add the killswitch.**
Once the configs are in /etc/wireguard/, run the script that adds the
killswitch, so that if a tunnel drops while you use it, your real IP is never
shown.

The installer puts two helpers in `/usr/local/bin`
(from `assets/vpn/`, via `install-scripts/vpn_tools.sh`). Run the first once,
after the configs are in place:

```bash
sudo add-wireguard-killswitch-to-configs
```

It adds `FwMark = 51820` and a `PostUp`/`PostDown` pair under `[Interface]` of
every full-tunnel config (`0.0.0.0/0` in `AllowedIPs`), so while such a tunnel
is up, any traffic that does not leave through it is rejected - the host's own,
and what Docker containers and VMs route through the host (anything but
private and LAN addresses, so containers still reach each other). A split tunnel
(one subnet: a work or home LAN) gets none - it would cut everything else off -
and the script lists which configs got one. Re-running it is safe: it removes
its own lines before adding them again. It re-runs itself through `sudo`.

If a tunnel dies without taking its killswitch rule down, nothing gets out at
all. Then use:

```bash
vpn-recover            # pick a config from a list
vpn-recover de-ber     # or name it - the one that died, or any other
vpn-recover --off      # no VPN: just unblock the network
```

It brings down any WireGuard interface still up, removes every killswitch rule
left behind (whichever config put it there), and brings the chosen tunnel up.
If that fails, the rules that were in force go back - nothing leaks - and
`vpn-recover --off` is the way out; if none were, nothing is blocked. It
re-runs itself through `sudo`.

**Check the two things the widget depends on.** Both commands must succeed —
the first without a password prompt, the second printing `active`:

```bash
sudo -k; sudo -n true && echo "passwordless sudo OK"
systemctl is-active systemd-resolved
```

`sudo -k` first: without it, a `sudo` you ran in the last few minutes leaves a
cached timestamp and `sudo -n true` succeeds even with no passwordless rule.

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

Nothing needs restarting: the bar's VPN dropdown reads `/etc/wireguard` again
every time it opens. (To restart the bar anyway, use SUPER+CTRL+B. A
`pkill qs; qs -c bar &` in a terminal also kills the overview, and leaves the
new bar a job of that terminal, which takes it down when it closes.)

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
- `CTRL + ALT + Delete` - Exit Hyprland
- `SUPER + M` - Split ratio 0.3 (the focused split on dwindle, the master width on master)
- `SUPER + SPACE` - Switch keyboard layout. Most recent first, like Alt+Tab: a
  tap toggles between the last two (US ⇄ ES); press again while the popup is
  open to go further (RU)
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

**Paste settings are pinned.** Before Handy starts, the keybind and `handy-start.sh` both run `UserScripts/handy-paste-settings.sh`, which sets Handy's paste method to **External Script** with `UserScripts/handy-type.sh` as the script: it waits **700 ms**, then types the transcript with `wtype`. Ctrl+V paste does not reach terminals, so typing it is. The wait matters because `wtype` types through its own keymap and Hyprland matches binds by key position: with SUPER/CTRL still held from the stop press, a long transcript fires binds (`a` → SUPER+4, `t` → SUPER+Q, `p` → SUPER+CTRL+R). Handy's own **Direct** method cannot do this: it types at once, and its paste-delay setting only applies to the clipboard methods. The script edits `settings_store.json` only while Handy is not running, and only once the file exists, so the very first Handy session after an install still uses Handy's defaults.

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
manifest and `02-Final-Check.sh` reports it at the end. If a Herdr binary is
already installed, it is kept and still configured; only the update is skipped.

The binary is the only thing `herdr.sh` downloads. The config, the sounds and
the five helper scripts are dotfiles, which is why `install.sh` runs `herdr.sh`
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
| `ALT + W` | New workspace |
| `ALT + Q` | Close workspace — a popup that also removes the git worktree if it is one |
| `ALT + B` | Previous workspace (there is no next-workspace key; use `ALT + 1…9` or the picker) |
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
  The dotfile ships `__HOME__`, and `copy.sh` substitutes it in the *installed*
  copy as it deploys it (`herdr.sh` does it again, as a safety net), so running
  `dotfiles-main.sh` on its own can no longer leave the tab binds pointing at
  `__HOME__/.local/bin`. Re-running is a no-op once no placeholders are left.
- **`~/.config/herdr` is updated, never replaced.** It is also herdr's runtime
  directory — the running server's sockets, `session.json` and its logs sit
  next to `config.toml` — so `copy.sh` copies the config and sounds into it
  instead of moving the directory aside like the others. A `config.toml` that
  differs from the repo is backed up next to itself first.
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

The same file also defines **`herdr-off`**, which is not a layout: it stops the
Herdr server, waits for the process to actually exit, confirms the session was
saved rather than cleared, and only then powers off. It exists because Herdr
0.9.0 deletes `session.json` on shutdown when its workspace list is already
empty - at poweroff systemd tears down the user session first, every pane shell
exits, the emptied workspaces auto-close, and the shutdown save removes the
snapshot instead of writing one. Upstream's fix for that race only covers panes
killed by a signal, and these exit with a status instead. **Run it from a plain
terminal, not from inside a pane** - anything after the stop runs in a shell
Herdr would have killed.

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

`neovim.sh` installs `tree-sitter-cli` from the repos so nvim-treesitter's `main`
branch can build parsers before nvim ever starts. Left to mason.nvim, the CLI was
fetched in the background during the headless pre-fetch, which quit first and
left a hard `❌ tree-sitter (CLI)` with no parsers and no highlighting. `stylua`
and `shfmt` come from the repos too, but they save mason no work: LazyVim asks
mason's own registry, not PATH, so mason still fetches its own copies. What fixes
the race is that the pre-fetch no longer quits when lazy.nvim is done. The same
headless nvim waits until mason's tools (`stylua`, `shfmt`, and `codelldb` from
the Rust extra) and LazyVim's treesitter parsers have finished installing. If
something did not make it, the script prints a WARN naming what is missing
instead of OK.

**The Neovim config is deliberately not tracked here.** The LazyVim starter is
meant to be forked and grown - `lua/plugins/*.lua` is yours - and vendoring a copy
would both freeze someone else's template and put `copy.sh`'s wholesale directory
replacement on top of your own plugin files on every re-run. `neovim.sh` clones
the starter once and never re-clones it; an existing LazyVim config is kept, and
any other `~/.config/nvim` is backed up rather than merged over. Two files are the
exception: `colors/pycharm-dark.lua` (the PyCharm-matched palette, from
`assets/nvim/`) is rewritten on every run, and `lua/plugins/colorscheme.lua`,
which selects it, is written only when it does not exist - change the scheme
there and re-runs keep your choice.

**Rust looks like RustRover.** `pycharm-dark.lua` carries a Rust-only section with
RustRover's own colours, read out of
`intellij.rustrover.common.jar!/org/rust/ide/colors/RustDark.xml`: blue functions,
green structs, purple traits, gold macros, pink `self`, italic teal lifetimes,
underlined `let mut`. Most of it only works with rust-analyzer running, since
treesitter cannot tell a trait from a struct, so `neovim.sh` installs rust-analyzer
(as a rustup component when rustup is present - its `~/.cargo/bin` proxy would
otherwise shadow the Arch package) and seeds `lazyvim.json` with the
`lang.rust` extra. Like `colorscheme.lua`, `lazyvim.json` is written only if absent:
on an existing config, turn the extra on yourself with `:LazyExtras`.

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
published `SHA256SUMS`, and installs the whole release - the binary and its
bundled agent skills - as `~/.local/bin/.hunk-release/`, with `~/.local/bin/hunk`
a symlink into it, so `hunk skill path` finds the review skill. That is the same
checked path `herdr.sh` takes. A mismatch installs nothing. Update later by
re-running `install-scripts/hunk.sh`. `hunk update` does not recognise this
install: hunk works out how it was installed from where its binary lives.

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
uncomment it to get a 10-minute auto-lock back. **Going idle does not blank the display
either**: the "Turn off screen" listener is commented out too, on purpose, so the only
live listener is the 9-minute idle notification. The session is still locked before
suspend (`before_sleep_cmd`), which is separate from idle.

**If you turn idle blanking back on**, point its `on-timeout` at `scripts/IdleDpms.sh`
(the commented listener already does) rather than at `dpms off` directly: it skips the
blank while locked *and* on AC, so the panel stays readable at the desk but still
blanks on battery.

**Files** (in `~/.config/hypr/`, from `Hyprland-Dots/config/hypr/`):
- `hyprlock.conf` — colours and background only
- `hyprlock-monitors.conf` — generated, do not edit
- `scripts/SovietLock.py` — draws the panel, date, footer
- `scripts/SovietClock.sh` — draws the block-glyph clock
- `scripts/SovietLockGen.py` — sizes the widgets per monitor
- `scripts/IdleDpms.sh` — idle blanking policy (only used if you re-enable the blank listener)
- `scripts/LockRun.sh` — starts hyprlock, logs its output and exit code
- `hypridle.conf` — calls `LockRun.sh` before sleep; the idle lock and blank listeners are commented out

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

Seven options take a third value, **`auto`**, resolved from this machine:
`nvidia`, `nouveau`, `rog`, `bluetooth`, `plymouth`, `limine` and `hackbgrt`. It is their
default, and the shipped preset uses it for all but `plymouth` (`OFF`). Values
are checked when the preset loads: `ON`, `OFF` (yes/no and any case work too)
and `auto` where allowed - anything else stops the run before it starts,
instead of quietly counting as `OFF`.

A preset is carried from machine to machine, which makes it the worst possible
place to record what hardware a machine has. This one was written on a laptop
with Intel graphics, so it used to say `nvidia="OFF"` — and run unchanged on an
NVIDIA machine that silently skipped `nvidia.sh` entirely. No driver, no
prompt, and `02-Final-Check.sh` could not report it, because nothing had been
attempted. The same applied to `rog="OFF"` on an ASUS laptop.

With `auto`, the installer answers these from the machine instead: `lspci` for
the GPU, `/sys/class/dmi/id/sys_vendor` for ASUS hardware. On an ASUS laptop
`asusctl` and `rog-control-center` are installed. `supergfxctl` is not: asusctl
6.x switches the GPU itself, and supergfxd's default config switched a dGPU that
Eco mode had turned off back on at every boot. `ON` and `OFF` still
force the decision, for when you mean it — `nvidia="OFF"` to stay on the
open-source driver, for instance. For `nvidia` and `nouveau` a forced `ON` is
still ignored with a note if the hardware is not there, so a stale preset cannot
install an NVIDIA driver on an AMD box - and a forced `nvidia="ON"` is ignored the
same way on a Kepler-or-older card, which no maintained driver supports. `rog` and
`bluetooth` are not gated: `ON` there installs them whatever the hardware (for a
Bluetooth controller whose firmware is not loaded yet, say).

One case `auto` cannot see: an ASUS hybrid laptop left in **Eco mode**
(`/sys/devices/platform/asus-nb-wmi/dgpu_disable` = 1) keeps its dGPU powered off,
so it is not on the PCI bus and no NVIDIA driver is detected or installed. Even a
forced `nvidia="ON"` is skipped. The installer warns about this at detection time
and again at the end. Switch to Hybrid (ROG Control Center -> GPU Configuration,
or `asusctl armoury set dgpu_disable 0`; asusd writes it at shutdown), reboot,
then run `install-scripts/nvidia.sh`. Both need the kernel's asus-armoury driver
(mainline since 6.19, and in the CachyOS kernels); on an older kernel without it,
`echo 0 | sudo tee /sys/devices/platform/asus-nb-wmi/dgpu_disable` and reboot.

A machine that got `supergfxctl` from an older run of this installer still has
it, and it keeps undoing Eco mode. `rog.sh` warns about it; to remove it:
`sudo systemctl disable --now supergfxd && sudo pacman -Rns supergfxctl && sudo rm -f /etc/modprobe.d/supergfxd.conf`.

This is also why there is no CPU/GPU vendor prompt: `--preset` runs
unattended by design, so a dialog could only appear in the interactive path —
the one that already worked.

Which driver gets installed depends on the GPU's generation, which
`install-scripts/nvidia_detect.sh` reads from the PCI device ID:

| GPU | Driver |
| --- | --- |
| Turing (GTX 16xx / RTX 20xx) and newer | `nvidia-open-dkms` + `nvidia-utils` + `lib32-nvidia-utils` |
| Maxwell, Pascal, Volta (GTX 9xx / 10xx, Titan V) | `nvidia-580xx-dkms` + `nvidia-580xx-utils` + `lib32-nvidia-580xx-utils` (AUR — the 580 branch is the last to support them) |
| Kepler and older | nothing: no maintained driver supports them, so `auto` leaves nouveau alone |

The open modules only bind to Turing and newer. They used to be installed for
every NVIDIA card, so a GTX 1060 rebooted with a module that never loaded *and*
nouveau blacklisted — no GPU driver at all. With several NVIDIA GPUs the oldest
one decides.

`nvidia.sh` then checks that every installed kernel actually has an NVIDIA
module (`modinfo -k <kver> nvidia`), because a DKMS build that fails inside
pacman's hook still leaves the package "installed". If any kernel is missing
one, the script fails, and what happens to nouveau depends on how many kernels are
affected. `nvidia-utils` (and `nvidia-580xx-utils`) ships its own
`blacklist nouveau` in `/usr/lib/modprobe.d/`. If **no** kernel got the module, the
script masks that file (`/etc/modprobe.d/nvidia-utils.conf -> /dev/null`) and
rebuilds the initramfs, so nouveau drives the card meanwhile. Anything else that
still blacklists it, such as `/etc/modprobe.d/nouveau.conf` from an earlier run, is
named but not removed. If only **some** kernels got it, the package's blacklist
stays so those kernels keep the NVIDIA driver, and a kernel without the module
boots with no driver for the card. Either way the final check names that kernel
and blocks the reboot. A later run of `install-scripts/nvidia.sh` in which every
kernel has the module removes the mask again. If you fix DKMS by hand instead
(`dkms autoinstall`, a kernel update that builds), the final check flags the
leftover mask, because with it nouveau and nvidia compete for the card on every
boot. The modules go into the initramfs through
`/etc/mkinitcpio.conf.d/99-nvidia.conf` (`MODULES+=(...)`), and the initramfs is
rebuilt once, after the nouveau blacklist is written, so the image that boots
carries both.

Note that enabling `nvidia` does **not** touch your bootloader. The driver's
`modeset=1 fbdev=1` settings are written to
`/etc/modprobe.d/my_archinstaller-nvidia.conf`, which the module reads when it
loads and which works identically under systemd-boot, limine, GRUB, rEFInd or a
UKI. `nvidia.sh` used to also add those as kernel parameters by editing
`/etc/default/grub` and rewriting every systemd-boot entry's `options` line; that
was redundant with the modprobe drop-in and is gone.

The file used to be `/etc/modprobe.d/nvidia.conf`. A file in `/etc/modprobe.d`
replaces the one with the same name in `/usr/lib/modprobe.d`, and on CachyOS
`cachyos-settings` ships `/usr/lib/modprobe.d/nvidia.conf` with its own NVreg
tuning, which that one-liner silently switched off. A re-run moves the line out
of the old file and deletes it if nothing else is in it.

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
[WARN] NOT rebooting: the final check found missing packages or a component that did not land.
```

did most of its work, but at least one package or component did not land. The
names are printed above that line and saved to
`Install-Logs/00_CHECK-*_installed.log`.

Four things feed that list. `02-Final-Check.sh` verifies a hardcoded set of
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
`ru_RU.UTF-8` locale is generated, `systemd-resolved` is enabled, the
passwordless sudo rule is in place (`sudo -n -l` lists `NOPASSWD: ALL` - a bare
`sudo -n true` also passes on a cached timestamp), the icon and cursor themes are
extracted. Each failure names the script
to re-run. These exist because the failures that hurt most were never
packages: a `copy.sh` that died left vanilla Hyprland with every package
"installed", and a `locales.sh` that was killed before it ran left the clock in
English — and both used to reboot as if nothing were wrong.

The fourth is a failed **initramfs rebuild**. `rebuild_initramfs()` records the
script that hit it, because a rebuild failing (a full ESP, say) leaves the old
image in place: the NVIDIA driver's own checks still pass, and the machine would
reboot into an initramfs without its modules or the nouveau blacklist.

In practice these are almost always AUR builds - on plain Arch `wallust`,
`wlogout`, `mpvpaper`, `pokemon-colorscripts-git` and `handy-bin`; on CachyOS,
whose repos carry the others, `wallust` and `handy-bin` - which break for
reasons that have nothing to do with this repo: an upstream tarball moved, a
dependency bumped its soname. (`awww` is not one of them: it is in `[extra]`,
so a failed `awww` means a mirror or repo problem.) Retry them by hand and
read the real error:

```bash
yay -S wallust       # replace with whatever was listed
```

Then reboot yourself:

```bash
systemctl reboot
```

Re-running `./install.sh --preset custom-preset.conf` is also safe — every
package step skips what is already installed, and `copy.sh` will not overwrite
a `secrets.zsh` you have filled in. It also keeps your wallust palette, your
active wallpaper, the first-boot marker, your monitor layout (`monitors.lua`,
`workspaces.lua`) and herdr's saved session. Everything else under a copied
`~/.config` directory is reset to the repo version — edits you made there
(`UserConfigs/*.lua`, say) are in the `<dir>.backup-<stamp>` copy next to it.

#### "Validating source files with sha256sums... FAILED"

Seen with `wallust` (2026-09-13). The package is hosted on Codeberg, and
Codeberg regenerates its release tarballs from time to time: same source,
different archive bytes, so the checksum written into the AUR PKGBUILD stops
matching. Nothing on your machine is wrong.

**The installer now handles this for allowlisted packages.** When a build fails
with makepkg's `One or more files did not pass the validity check!`, the
installer tells that apart from an ordinary build failure and checks the name
and version against `install-scripts/checksum-skip.conf`:

| in `checksum-skip.conf` | what happens |
|---|---|
| yes, that version | rebuilt once with `--skipchecksums`, loudly, and the run continues unattended |
| no, or another version | left alone; the final check names it and prints the exact command |

`wallust 3.5.2-1` is listed, so the case that actually recurs no longer
interrupts an unattended install. An entry covers only the version that was
checked: when the AUR moves wallust on and its checksum fails again, the run
stops on it until the new source has been checked and the line updated.

Two details make that reliable. The AUR helper runs under `LC_ALL=C.UTF-8`,
because makepkg translates that message and on a non-English system the
installer would never see it. And the failure is pinned to the package whose
build printed it (the last `==> Making package:` before it), so when the
mismatch is in an AUR *dependency* of what was asked for, it is that
dependency's name that is checked against the allowlist and reported. For a
split package (one PKGBUILD, several packages) makepkg names the pkgbase, which
is often not installable, so the installer reads the helper's cached
`.SRCINFO` to find the package names behind it and retries, reports and
records those. The allowlist accepts either the pkgbase or a package name.

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

Then add `<name> <version>` (as makepkg prints it in `==> Making package:`) to
`install-scripts/checksum-skip.conf` with a comment
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
hyprctl dispatch 'hl.dsp.exit()'  # Restart Hyprland (the Lua form - plain 'dispatch exit' no longer exists)
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
- ✅ zsh (the shell the dotfiles are written for)
- ✅ thunar (the file manager the binds and bookmarks expect)
- and the rest as `custom-preset.conf` has them: herdr, neovim, hunk, docker and
  text_boot `ON`, plymouth `OFF`; nvidia, nouveau, rog, bluetooth, limine and hackbgrt are resolved from the
  hardware when you pick `auto` in a preset

## Verification

`02-Final-Check.sh` is the post-install verification, and `install.sh` runs it
for you at the end of every run. To re-run it by hand:

```bash
cd ~/Documents/my_archinstaller
./install-scripts/02-Final-Check.sh
```

It checks the selection the last `install.sh` run saved in
`Install-Logs/.selected-options`, with every `auto` option already resolved for this
machine. A hardcoded list used to give false failures where `auto` had turned an
option off (plymouth on plain Arch, bluetooth without a controller) and skipped the
NVIDIA checks where it had turned one on. To check a different selection, set it
yourself: `INSTALL_SELECTED_OPTIONS="ly dots ..." ./install-scripts/02-Final-Check.sh`.

If the last `install.sh` run stopped part-way (a failed `pacman.sh`, `locales.sh` or
AUR helper build, or Ctrl-C), its failure lists only cover part of the run, so the
check does not pass on them: it reports that the run did not finish
(`Install-Logs/.run-in-progress` is still there) until a run completes.

Do that too after running one install script by hand for something the last run
did not select - `install-scripts/nvidia.sh` after switching an ASUS laptop out of
Eco mode, say. The saved selection does not know about it, so the NVIDIA module
checks would be skipped: add `nvidia` to the list you pass.

`verify-before-transfer.sh` is something else: it checks that the **repo** is
complete before you copy or push it (every script and asset present), not that
anything was installed. Run it on the old machine before you clone on the new one.

## Notes

- The installation backs up existing configs to `~/.config/<app>.backup-<YYYYMMDD-HHMMSS>`
  (one per run, never overwritten). Single files it replaces get the same
  stamped `<file>.backup-<stamp>` beside them: the shell files in `~`
  (`.zshrc`, `.zprofile`, `pokefetch_perfect`, ...) when they differ from the repo copy, and
  `~/.config/mimeapps.list`, `xdg-terminals.list` and `user-dirs.dirs` when they
  hold a line the repo copy lacks (your own "open with" choices, another
  terminal, a moved Downloads).
- Event-based monitoring reduces CPU usage significantly
- All scripts are logged to `Install-Logs/` (untracked - they are per-run output)
- First boot runs `initial-boot.sh` to set the wallpaper, run wallust, and apply
  the GTK, icon, cursor and Kvantum themes. The marker is only written when
  wallust and every `gsettings` write succeeded, so a first login where dconf was
  not ready yet retries at the next login (with a notification) instead of
  leaving the themes unapplied for good. Once it has worked it runs exactly once, guarded by
  `~/.config/hypr/.initial_startup_done`. That marker is gitignored on purpose:
  if it is ever committed, copy.sh deploys it to the new machine and the whole
  first-boot setup silently skips itself.
- Several packages the scripts name have moved from the official repos to the
  AUR since they were written (`wlogout`, `wallust`). They still install, through `yay`, but they are now
  source builds and the most likely thing to fail on a given day — see
  [When the installer stops without rebooting](#when-the-installer-stops-without-rebooting).
  `gtk-engine-murrine` used to be on this list; it is no longer installed at all,
  because on plain Arch it dragged in a from-source GTK 2 build (gtk2 left [extra]
  too) for an engine none of the bundled Flat-Remix themes use.
