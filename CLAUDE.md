# my_archinstaller

## What this project is

This repo is a personal Arch/CachyOS installer and dotfiles set. It is meant to
be run on **every fresh install of CachyOS or Arch Linux** to reproduce *this
computer's* setup — the Hyprland desktop, apps, theming, and configuration —
so a brand-new machine ends up behaving exactly like the one this repo was
built from.

The top-level `*.sh` scripts (`install.sh`, `auto-install.sh`, plus helpers
like `diagnose.sh` and `verify-before-transfer.sh`) drive the install. The
actual desktop configuration lives under `Hyprland-Dots/config/`, which mirrors
`~/.config/` on the running machine (e.g. `Hyprland-Dots/config/hypr` →
`~/.config/hypr`, `Hyprland-Dots/config/rofi` → `~/.config/rofi`, and so on).

## Development workflow (important)

There are **two copies** of every config file: the **live machine** copy under
`~/.config/...` and the **repo** copy under
`~/Documents/my_archinstaller/Hyprland-Dots/config/...`. The keybinds and the
running desktop use the *live* copy, so editing only the repo changes nothing
until it is deployed.

Always work in this order:

1. **Change the live machine first** (`~/.config/...`) so I can test the change
   in the real running desktop. Keybinds run the live file immediately, so most
   changes can be tried right away.
2. **Once I confirm the change works**, copy the same change into the repo
   (`Hyprland-Dots/config/...`) so it becomes part of the installer and lands on
   the next fresh install.

Do not commit or push a change to the repo before it has been confirmed working on the
live machine.

### Live vs. repo differences to preserve

The live copies may carry small differences the repo intentionally keeps or
drops — notably upstream **JaKooLit / KooL** credit comment lines and naming.
When deploying between the two, preserve each side's convention: keep the credit
lines in the live files, and match whatever the surrounding repo files already
do. Back up a live file before overwriting it.

## Notes

- The Hyprland config is **Lua**, not the classic `hypr.conf` syntax, both on the
  machine and in the repo. Keybinds, startup apps, etc. are `.lua` under
  `Hyprland-Dots/config/hypr/configs/`.
- The wallpaper daemon (swww) ships here under the renamed binary `awww` /
  `awww-daemon`. Theming after a wallpaper change goes through `wallust`.
- The bar/overview is `quickshell` (QML) under `Hyprland-Dots/config/quickshell/`.
