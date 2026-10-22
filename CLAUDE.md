# my_archinstaller

## What this project is

This repo is a personal Arch/CachyOS installer and dotfiles set. It is meant to
be run on **every fresh install of CachyOS or Arch Linux** to reproduce *this
computer's* setup — the desktop (mango), apps, theming, and configuration —
so a brand-new machine ends up behaving exactly like the one this repo was
built from.

The top-level `*.sh` scripts (`install.sh`, `auto-install.sh`, plus helpers
like `diagnose.sh` and `verify-before-transfer.sh`) drive the install. The
actual desktop configuration lives under `dotfiles/config/`, which mirrors
`~/.config/` on the running machine (e.g. `dotfiles/config/mango` →
`~/.config/mango`, `dotfiles/config/rofi` → `~/.config/rofi`, and so on).

## Working with Claude (important)

**Do not change anything unless I ask you to.** When I ask a question — including
diagnostic questions like "why is this slow?" or "is it because of X?" — answer
the question only. Do not edit files, run fixes, revert, clear caches, or
regenerate state as part of answering. Investigating read-only is fine;
modifying my live system or the repo is not, until I explicitly ask for a
change. A conditional "you can do X if I'm not happy" from earlier is not
standing permission to act the next time I ask something — wait for a clear go.
When a fix seems obvious, propose it and wait.

## Development workflow (important)

There are **two copies** of every config file: the **live machine** copy under
`~/.config/...` and the **repo** copy under
`~/Documents/my_archinstaller/dotfiles/config/...`. The keybinds and the
running desktop use the *live* copy, so editing only the repo changes nothing
until it is deployed.

Always work in this order:

1. **Change the live machine first** (`~/.config/...`) so I can test the change
   in the real running desktop. Keybinds run the live file immediately, so most
   changes can be tried right away.
2. **Once I confirm the change works**, copy the same change into the repo
   (`dotfiles/config/...`) so it becomes part of the installer and lands on
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

- The compositor is **mango** (mangowm, wlroots/dwl-based), patched to behave
  like the Hyprland setup this desktop came from: `pkgbuilds/mangowm` (one
  patch per behaviour, each an option the config turns on), built by
  `install-scripts/mango-patched.sh` and kept in pacman's `IgnorePkg`. Its
  config is `key=value` files under `dotfiles/config/mango/`
  (`keybinds.conf`, `startup.conf`, `rules.conf`, `settings.conf`, ...), all
  sourced by `config.conf`. mango reloads by itself when any of them changes;
  check one with `mango -c ~/.config/mango/config.conf -p`. Control it with
  `mmsg` (`mmsg dispatch ...`, `mmsg get all-clients`).
- The scripts every bind runs stay in `~/.config/hypr/scripts` and
  `~/.config/hypr/UserScripts`, next to `hyprlock.conf` and `hypridle.conf`
  (hyprlock and hypridle are kept on mango).
- The wallpaper daemon (swww) ships here under the renamed binary `awww` /
  `awww-daemon`. Theming after a wallpaper change goes through `wallust`.
- The bar is `quickshell` (QML) under `dotfiles/config/quickshell/bar/`;
  the overview (SUPER+A) is part of the bar now (`bar/overview/`). It talks to
  mango through `bar/Mango.qml` (the IPC socket) and gets the keybinds' calls
  through `qs -c bar ipc call <target> <function>`.
