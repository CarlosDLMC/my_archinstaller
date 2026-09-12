## CHANGELOGS

## September 2026

Fixed (first audit of a fresh-machine run against this machine):

- `Global_functions.sh`: `ISAUR=$(command -v yay || command -v paru)` under `set -e` killed any script that sourced it before an AUR helper existed. `locales.sh` runs before `yay.sh`, so on a fresh install the Russian locale was never generated and the clock, calendar and lock-screen date fell back to English with no error. Now `|| true`
- `01-hypr-pkgs.sh`: `librewolf-bin` → `librewolf` (the -bin package left the AUR when LibreWolf entered `[extra]`; every fresh run failed the final check and never rebooted, and there was no default browser). Added `vim`, which `01-UserDefaults.lua` names as `$EDITOR` but nothing installed
- `nvidia.sh`: `nvidia-dkms` → `nvidia-open-dkms` (the closed module packages are gone from the repos; the old name installed nothing while nouveau still got blacklisted)
- `services.sh`: enables `systemd-resolved` and points `/etc/resolv.conf` at its stub whenever `systemd-resolvconf` is installed. The shim is useless without the daemon, so a fresh machine connected but resolved nothing, and `wg-quick` failed on every `DNS=` line. This machine only worked because resolved had been enabled by hand
- `install.sh`: sudo is authenticated once up front, a `sudo -v` keepalive runs for the whole install, and with `nopasswd_sudo` selected the rule is installed *before* the first package — so a preset run never prompts again. Previously the 5-minute timestamp expired under the spinner and the run appeared to hang
- `install.sh`: aborts if no AUR helper exists after `yay.sh`, instead of running ~150 silent failures with an empty helper name
- `install.sh`: no `clear` before the final check (and none in `ly.sh` / `ly_config.sh`), so errors printed during the run are still on screen at the reboot countdown
- `02-Final-Check.sh`: outcome checks per selected component gate the reboot too — dotfiles in `~/.config`, `ly@tty2` enabled and config matching, zsh the login shell, `ru_RU.UTF-8` generated, resolved enabled, `sudo -n` working, icon/cursor themes extracted, `pokemon-colorscripts`/`handy` on PATH, `cups.socket` enabled. A dead `copy.sh` used to reboot into vanilla Hyprland with every package "installed"
- `initial-boot.sh`: sets the GTK `font-name` / `monospace-font-name` (JetBrainsMono Nerd Font 16) over gsettings; they lived only in this machine's dconf
- `Hyprland-Dots/wallpapers/`: ships all fourteen wallpapers in use here, not only the `sovietpunk/` four
- `pipewire.sh`: the second loop installed `$PIPEWIRE` (stale) instead of `$PIPEWIRE2`
- `yay.sh`: the post-build `-Syu` checked `tee`'s exit status; now `PIPESTATUS[0]`
- `copy.sh`: `mkdir -p ~/.config` before the user-dirs copies, not after
- `.bashrc` / `.bash_profile`: `~/.cargo/env` and `~/.local/bin/env` are sourced guarded, like `.zshrc` already did
- `verify-before-transfer.sh`: checks for `install.sh` next to itself rather than in `$PWD`
- README: swaync → dunst, backup suffix is `.backup-<timestamp>`, `verify-before-transfer.sh` described as the repo check it is, the LICENSE reference removed (no such file), new DNS section, sudo behaviour, `nvidia-open-dkms`, packages that moved to the AUR

Changed:

- Hyprland config migrated from hyprlang `.conf` to Hyprland's Lua format (`hyprland.lua`, `configs/*.lua`, `UserConfigs/*.lua`, animation presets, monitor profiles). Hyprland 0.55 deprecated `.conf` and 0.57 removes it; there is no switch to silence the startup warning, only the migration
  - Same file layout as before; `configs/Vars.lua` replaces the `$mainMod`/`$scriptsDir` variables, `UserConfigs/01-UserDefaults.lua` is a plain data table so shell scripts can read it with `lua`
  - `hyprctl keyword` and legacy `hyprctl dispatch <string>` do not exist under Lua, so every caller was rewritten to `hyprctl eval 'hl.config({...})'` / `hyprctl dispatch 'hl.dsp.…'`: ChangeBlur, ChangeLayout, GameMode, TouchPad, Dropterminal, Tak0-Autodispatch, IdleDpms, MoveWorkspaceWindows.py, SovietLockGen.py, WallpaperSelect, hypridle.conf, swaync, wlogout's exit button and the quickshell bar/overview QML
  - `KeyBinds.sh` / `KeyHints.sh` list the live binds from `hyprctl binds` instead of parsing config text; every bind carries a description
  - Number-row workspace binds are by keysym (`SUPER + 1`) rather than keycode — identical keys on us/es/ru, and `hyprctl binds` cannot report keycodes for Lua binds
  - `KeybindsLayoutInit.sh` removed: SUPER+J/K are plain binds now
  - wallust renders `wallust-hyprland.lua` (a Lua module) instead of a `.conf`; the seed in `defaults/` follows
  - Two animation presets clamped to Lua's limits (`borderangle` speed 180 → 100, one bezier point 6.9 → 2); `XF86AudioPlayPause` bind dropped (the keysym never existed)
  - `TouchPad.sh` finds the touchpad through udev instead of a hard-coded ASUS device name that never matched
- Clipboard manager (`SUPER ALT V`) pastes the chosen entry into the focused window (Ctrl+Shift+V in terminals, Ctrl+V elsewhere) via `wtype`
- Bar: layout widget and switcher ignore `activelayout` events from virtual keyboards (`hl-virtual-keyboard-*`) — every `wtype`/Handy paste used to open the layout popup and flash "ER"/"NO"

Added:

- Soviet-brutalist TUI lock screen, replacing the stock blurred-wallpaper hyprlock
  - Deliberately matches the **ly** login screen (`assets/ly/config.ini` with `lang = soviet`), so login and unlock look like the same machine: pure black, one monospace face, block-glyph clock, Russian labels
  - `config/hypr/scripts/SovietLock.py` — draws the bordered status panel, the Russian date line and the key-hint footer, emitted as one block with real newlines (hyprlock ignores literal `\n` in a `text =` field and only renders multi-line output from `cmd[...]`)
  - `config/hypr/scripts/SovietClock.sh` — the ly-style bigclock in block glyphs
  - Panel carries everything the old screen showed plus kernel, load, memory and AC state; wrong password gives ly's own `НЕВЕРНЫЙ КОД ДОСТУПА · ПОПЫТКА N` in red
  - Keyboard layout is shown on its own panel row and is clickable, dispatching `global quickshell:layoutNext` so the bar's MRU ordering and OSD stay in sync
- Per-monitor widget generation — the lock screen sizes itself to any display
  - `config/hypr/scripts/SovietLockGen.py` rewrites `config/hypr/hyprlock-monitors.conf` from `hyprctl monitors` before every lock, emitting one widget set per attached monitor, so a 1080p laptop and a 2K external each get their own font size from one file
  - `hyprlock.conf` holds no geometry at all (183 → 53 lines), only colours, background and cursor, and `source`s the generated file
  - Font size is searched, not solved: the largest that keeps the stack inside 85% of height and the panel inside 40% of width. Verified by rendering at 720p, 1080p, 1440p and 4K, with every overlaid widget landing 0px off its panel row
  - Text metrics come from Pango, the engine hyprlock renders with, with an exact metrics table baked in for fonts 8–44 so no `python-gobject` dependency is added — output is byte-identical either way
  - A machine-agnostic seed of the generated file ships in the repo, because a missing `source =` target makes hyprlock render a blank screen on a fresh machine
- `config/hypr/scripts/IdleDpms.sh` — idle-blanking policy: the screen stays lit while locked *and* on AC, and blanks as before in every other case
- `config/hypr/scripts/LockRun.sh` — hypridle's `lock_cmd`; records hyprlock's output and exit code to `~/.cache/hypr-logs/hyprlock.log`, keeping one previous generation. The exit code is what distinguishes hyprlock crashing from hyprlock choosing to quit
- `config/hypr/scripts/SessionLogKeep.sh` — mirrors ly's session log, which ly truncates at every login, so a failed session leaves evidence
- Whole-workspace move — `$mainMod ALT + <1-0>` sends *every* window of the current workspace to that workspace and follows it there, with the tiling layout rebuilt window for window
  - `config/hypr/UserScripts/MoveWorkspaceWindows.py` — Hyprland exposes no way to read or write the dwindle tree, so the layout is recovered from the window rectangles: they always form a guillotine partition, and a recursive cut search turns them back into the split tree that produced them
  - The tree is replayed in the target workspace as a pre-order sequence of `focuswindow` + `layoutmsg preselect r|d` + `movetoworkspace`, then the split ratios are restored with `resizewindowpixel exact` (`splitratio` no longer exists in 0.56.2). Verified at 0px position and size error on a five-window mixed tree with hand-mangled ratios, down to a 94px-wide sliver
  - Naive moves are cursor-dependent, which is what made the layout look scrambled: with `dwindle:force_split = 0` dwindle takes both the split side and the node to split from the pointer, so the same move gave a different layout depending on where the mouse sat. The script pins `dwindle:force_split` and `animations:enabled` for the duration and restores both in a `finally`, so the rebuild is invisible and mouse-independent
  - Floating windows keep their exact geometry, a fullscreen window keeps its state *and* the tile hidden underneath it, and merging into a populated workspace scales the incoming tree into the slot it receives instead of squeezing it to 61px slivers. Grouped/tabbed windows fall back to a plain batch move, and a cross-monitor move (2560x1440 → 1920x1080) keeps the proportions within 0.8%
  - Takes ~1s for five windows; `--simple` skips the reconstruction, `--follow` is what the binds pass, and a source workspace can be named explicitly (`MoveWorkspaceWindows.py 2 5` moves 5 into 2 without leaving the current workspace)
- Capture dialogs for screen recording and screenshots, in the style of the keyboard-layout OSD rather than a rofi list
  - `config/quickshell/bar/components/RecordOsd.qml` on `$mainMod SHIFT R` and `ShotOsd.qml` on `$mainMod Print` / `$mainMod SHIFT S`, both centred layer-shell boxes over a dimmed desktop: two 283x202 buttons (whole monitor / drag a region), then the monitor picker, which is hidden when only the laptop panel is attached
  - State lives in `RecordState.qml` and `ShotState.qml`; the capture itself is still `scripts/ScreenRecord.sh` and `scripts/ScreenShot.sh`, so the dialogs and the bare keybinds cannot drift apart. Both dialogs take keyboard focus: `F` whole screen, `R` region, `W` active window, `Esc` dismiss, plus `S`/`M` for the recorder's audio switches and `E` for satty
  - `$mainMod SHIFT R` pressed *while* recording stops the recording instead of opening the dialog, so the one-press stop survives. Recording state is polled back out of `ScreenRecord.sh --status` rather than assumed, so a wf-recorder that died on startup does not leave the UI claiming to record
  - `ShotState.settleMs` (300ms) waits for the overlay to leave the screen before grim runs, comfortably above the 160ms fade. Verified by counting pixels of the panel's exact background colour: ~183,300 while the dialog is up, 3,743 in a capture taken from it, against 2,567 in a clean grab
  - `config/quickshell/bar/Monitors.qml` — one shared monitor list behind both dialogs, replacing a `hyprctl monitors` query per dialog. `resolveTarget()` keeps a remembered monitor only while it is still attached and otherwise falls back to the focused one, so neither dialog can aim at a display that has been unplugged
  - `BigButton.qml` and `ToggleRow.qml` are shared by both dialogs
- System-audio and microphone switches on the recording dialog, persisted to `~/.cache/screenrecord_audio` so the bare keybinds record with the same setting
  - wf-recorder accepts a single `-a` device, so "both" cannot be passed through: `ScreenRecord.sh` loads a `module-null-sink` plus one `module-loopback` from the default sink's monitor and one from the default source, records the null sink's monitor, and unloads all three on stop
  - Teardown also matches modules by sink name, not just the ids it recorded, so a crashed run cannot leave loopbacks behind — this machine has hit the pulse client cap before and lost audio to leaked `pactl` children
  - All four states verified end to end (`none`, `system`, `mic`, `both`): the first produces a video-only file, the rest an `aac` stereo track, and `both` measured -17.9 dB mean / -5.6 dB peak with a test sound playing rather than a silent track. `pactl list short modules` was clean after every run
- `ScreenShot.sh --monitor [output]` — a shot of one whole monitor, defaulting to the focused one
- Bare `Print` takes an immediate shot of the monitor the *pointer* is on, via `ScreenShot.sh --mouse`. Deliberately the pointer and not the focused monitor: those can sit on different screens, and "the screen my mouse is in" means the pointer. `output_at_cursor()` resolves `hyprctl cursorpos` against the monitor rectangles, dividing by `.scale` because hyprctl reports positions in layout coordinates but sizes in pixels. Verified with focus and pointer deliberately split — pointer on the 2560x1440 monitor, focus on the 1920x1080 panel — which captured 2560x1440

Changed:

- Notifications now split by kind: anything a person sent you waits until it is clicked (left click dismisses one, middle click dismisses all), while feedback for something you just did - a screenshot, a recording, a toggle - fades on its own. `config/dunst/dunstrc` had been holding *everything* open with a catch-all `[never_expire]` rule, which made a touchpad toggle as sticky as a direct message. The catch-all is gone. There are three lifetimes now. A toast that only confirms an action you just took - a screenshot, a recording starting or stopping, the handy transcription toggle, satty saving - lasts 1s, because you already know what you did: `[flash_*]` rules set `override_dbus_timeout = 1s`, matching on the `x-canonical-private-synchronous` stack tags the scripts already send (`shot-notify`, `record-notify`) and on summary or body for the paths that send none. The handy toggle is matched on its body rather than its "Handy" summary, so `handy-start.sh`'s first-run "pick a model" hint keeps its 8s. Everything else unclassified gets the global `timeout`, now 5s - the remaining toggles (touchpad, gamemode, blur, layout, theme) land here. Staying on screen is now opt-in, through three rules that each set `override_dbus_timeout = 0` - the only thing that beats a client's own requested duration - plus `set_transient = no`, so a client cannot mark a notification transient and have it expire anyway: `[messages]` matches chat clients by `appname`, `[messages_by_category]` catches any client that labels itself with the freedesktop `im`/`email` categories, and `[critical_never_expires]` holds errors from any source. The match is on appname because that is the field that actually separates the two classes here - every script in this repo notifies through `notify-send` and reports that name, while a chat client reports its own; `dunstctl history` prints the appname of anything worth adding to the list. `ignore_dbusclose = true` and `notification_limit = 20` stay: an app still cannot withdraw a message before it has been read, and the queue is still generous because the persistent class only drains as it is clicked away. Note that `override_dbus_timeout = 1000` would have meant 1000 *seconds*: dunst reads a bare number as seconds, and `dunstctl rules` prints the parsed value in microseconds, which is how to check it. Verified live against a running dunst 1.13.2 by replaying the exact `notify-send` command lines the scripts use: the screenshot, recording, satty and handy-toggle toasts were all in history by 2s despite asking for 1.5-10s, "Gamemode: enabled" died at 5s, handy's model hint kept its 8s, and Slack- and Telegram-named notifications requesting 500-1000ms were still on screen at 30s, as was a critical one. Disable temporarily with `dunstctl rule messages disable`
- Going idle no longer locks the session. `hypridle.conf`'s screenlock listener (10 min → `loginctl lock-session`) is commented out, so the lock screen is only raised deliberately with `CTRL+ALT+L`. Idle still blanks the display at 10.5 min via `IdleDpms.sh`, it just leaves the session unlocked; `before_sleep_cmd` still locks before suspend, which is a separate path
- The bigclock moved from `SovietLock.py --clock` to `SovietClock.sh`. It is the one widget hyprlock re-runs every second per monitor, and Python's interpreter startup dominated its cost: ~45 ms a run became ~5 ms. Measured end-to-end as hyprlock's own CPU over a 60s lock, which includes re-reading and re-rendering the label rather than just running the command, that is 7.4% → 2.4% of one core per monitor, so a locked two-monitor session costs ~4.7% instead of ~14.8%. A hyprlock with every widget static uses no measurable CPU, so the clock accounts for the entire cost of a locked screen, and ~18 ms of the remaining 23.5 ms per tick is hyprlock's own work rather than the script's. The shell version forks nothing (the time comes from bash's `printf` builtin, not `date`) and its output is byte-identical for all 86,400 times of day
- `SHIFT_L+ALT_L` in `configs/Keybinds.conf` now dispatches `global quickshell:layoutNext` like its `ALT_L+SHIFT_L` counterpart, so ALT+SHIFT switches layout whichever modifier is pressed first
- Recording and screenshot filenames are now `%Y-%m-%d_%H-%M-%S`, so name order is time order. They were `%d-%b_%H-%M-%S`: day first, no year, and a *localized* month name. `config/environment.d` deliberately sets `LC_TIME=ru_RU.UTF-8` for the graphical session, and it has been other locales before, so `~/Videos/Recordings` held German, English and Russian month abbreviations side by side (`03-Mai`, `15-Mär`, `11-Feb`, `10-сен`) and sorted by name put May before July. Filenames should not depend on a locale setting whose whole purpose is the on-screen calendar. The 24 existing recordings were renamed off their mtimes rather than by parsing three languages of month abbreviation, with the reversal kept as a script; name-sort and mtime-sort of the folder are now byte-identical under `diff`
- `ScreenShot.sh`'s satty path had a *third* format, `Screenshot_%Y%m%d_%H%M%S.png`, passed to `--output-filename` and so applied by satty rather than the script. Now aligned with the rest
- `$mainMod Print` and `$mainMod SHIFT S` open the screenshot dialog; `$mainMod SHIFT R` opens the recording dialog. The direct paths all survive — `$mainMod SHIFT Print` (region), `$mainMod CTRL`/`CTRL SHIFT Print` (5s/10s), `ALT Print` (active window), `ALT R` (record active window), `$mainMod CTRL SHIFT R` (stop) — and satty moved from `$mainMod SHIFT S` to `$mainMod ALT S`, which was free. `$mainMod S` (web search) and `$mainMod CTRL S` (window switcher) are untouched

Fixed:

- The lock screen showed weather that was 45 days old. It read `~/.cache/.weather_cache`, written only by `UserScripts/Weather.py` — run by `scripts/LockScreen.sh` and nothing else, so an idle lock never refreshed it and nothing refreshed it at all between manual locks. The bar meanwhile reads its own `~/.cache/quickshell/weather.json`, which quickshell refreshes hourly, so the two screens disagreed. `SovietLock.py` now reads the bar's file first and falls back to the legacy one only where quickshell is absent, parsing the tooltip markers that `weather-location.py` documents as a contract with `CenterInfo.qml`. As a side effect the location reads `TBILISI` rather than `GEORGE W. BUSH STREET, GEORGIA`
- A weather reading older than two hours (twice the bar's refresh interval) is now labelled with its age in the section header instead of being presented as current. Both fetchers have failed silently before — the bar's previous weather.com scraper broke when weather.com changed its CSS classes — and a stale reading shown as live is worse than no reading
- `scripts/LockScreen.sh` ran the weather fetch synchronously before `loginctl lock-session`, so `CTRL+ALT+L` waited on the network — measured at up to 3s, and able to block far longer on a dead network. It is now detached and capped with `timeout`, and only warms the legacy fallback
- `hyprlock.conf` — stray `}` left behind when an `image {` block was commented out, which made hyprlock log "Stray category close" on every lock
- `general:grace` does not exist in hyprlock 0.9.6 and was silently ignored, so there was never a grace period; it is set via `--grace` in `hypridle.conf` instead
- The battery row was printed twice on a two-battery machine, because `Battery.sh` loops `BAT0`–`BAT3` and prints a line per match. Each pack now gets its own row
- Clock digits sheared apart at some times: hyprlock centres each line of a multi-line label independently and Pango trims trailing whitespace before measuring, so rows are padded with non-breaking spaces. The clock also centres on its own ink rather than its character box, so a `1` in the first or last position no longer drifts the whole clock sideways
- Recording "the whole screen" recorded the laptop panel. `ScreenRecord.sh`'s fullscreen path called `wf-recorder -f <file>` with no `-o`, and wf-recorder does not default to the focused or the cursor monitor: with more than one output it prints `Please select an output from the list to capture` and reads stdin, where `eDP-1` is entry 1. Launched from a Hyprland `exec` bind there is no terminal, so it either exits on the spot or takes the laptop. Every path now passes `-o` explicitly, defaulting to `hyprctl -j monitors | jq -r '.[] | select(.focused) | .name'`. Confirmed against the recordings that prompted it — 1920x1080, the panel's exact resolution — and the fix verified by content, not just by size: frames from a capture of the external monitor match `grim -o HDMI-A-2` at 3.6% RMSE against 14.7% for `eDP-1`
- `$mainMod Print` never captured one screen either: `grim` with no `-o` grabs the entire layout, which on this desk is **4480x1440** — a 1920x1080 panel and a 2560x1440 monitor stitched together with the dead space between them. The dialog and `--monitor` both name an output

Removed:

- `config/hypr/hyprlock-2k.conf` — superseded by the generator, which covers every resolution and cannot drift out of sync with the 1080p file
- `config/hypr/scripts/Tak0-Per-Window-Switch.sh` and its keybind — it read `kb_layout` from `UserConfigs/UserSettings.conf` while this setup defines it in `configs/SystemSettings.conf`, so it exited immediately and had been dead since the quickshell layout switcher superseded it. Its focus listener also required `socat`, which this installer does not ship, and its single-listener guard could never match, so it leaked a listener per keypress
- `README-CUSTOM.md`, `INSTALLATION-ISSUE-SUMMARY.md`, `SETUP-COMPLETE-SUMMARY.md` and `commit-message.txt` — four scratch documents that only ever referenced each other, superseded by `README.md`
  - `README-CUSTOM.md` and `INSTALLATION-ISSUE-SUMMARY.md` told you to `cd ~/Documents/Arch-Hyprland`, a directory that does not exist and never did under that name here — 15 references between them, 17 of the lines being commands you would paste, including the `./diagnose.sh` invocation offered as the fix for a broken install
  - `SETUP-COMPLETE-SUMMARY.md` and `commit-message.txt` carried no wrong paths; they were session scratch ("I've updated your repo…", a staged commit message from 8 months ago) that was never meant to be committed
  - They also documented a workflow the repo abandoned: transferring the directory by USB or `rsync` rather than `git clone`, and SDDM rather than **ly**, as the thing that starts on boot
  - `INSTALLATION-ISSUE-SUMMARY.md` diagnosed a dotfiles-copy failure that has since been fixed, so the top-level docs of a public repo led with an unresolved bug report
  - `README-CUSTOM.md` claimed the volume widget watches `pactl subscribe`; `VolumeWidget.qml` uses `Quickshell.Services.Pipewire` and its comment records the move away from a `pactl subscribe` child process
  - Nothing outside the cluster linked to any of them, and `README.md` already carries the same troubleshooting steps with correct paths

## May 2026

Added:

- `handy.sh` install script for Handy offline speech-to-text
  - Installs `handy-bin` (AUR), `wtype`, `gtk-layer-shell`
  - Appends `CTRL+SUPER+F8` toggle keybind to `UserConfigs/UserKeybinds.conf` (idempotent — uses `notify-send` for feedback, then `handy --toggle-transcription`)
  - Writes `UserScripts/handy-start.sh` launcher that opens Handy visibly until a model is selected, then `--start-hidden` on subsequent logins (so the user sees the model picker on first login without the UI re-opening every boot)
  - Appends `exec-once = ~/.config/hypr/UserScripts/handy-start.sh` to `UserConfigs/Startup_Apps.conf`
  - Must run after `dotfiles-main.sh` (depends on the `UserConfigs/` files existing)
  - Wired into `install.sh` whiptail menu and `custom-preset.conf` (default `ON`)

## Dec 2025

Added:

- `qt5-quickcontrols2` to sddm.sh - User reported w/o this SDDM crashed on login
  Fixed:
- AGS v1
  - It now does the following:
  - Clone upstream AGS 1.9.0.
  - Stub out PAM/GUtils via pam.ts.
  - Build and install AGS.
  - Install the known-good launcher from install-scripts/ags.launcher.com.github.Aylur.ags.
  - Points /usr/local/bin/ags at that launcher.
  - AGS is no longer removed when you add quickshell.
  - AGS overview is a backup if quickshell overview fails.
- meson build errors
- `rofi-wayland` package changed to 'rofi'
- Add missing monitor scripts from Fedora-Hyprland PR #234

## 22 July 2025

- Updated sddm theme and script to work with the updated simple_sddm_2 theme

## 17 July 2025

- added quickshell script to replace ags for desktop overview

## 08 June 2025

- updated SDDM theme.

## 20 March 2025

- adjusted hyprland installation script. This is great for those who are using -git packages
- added findutils as dependencies

## 11 March 2025

- Added uninstall script
- forked AGS v1 into JakooLit repo. This is just incase Aylur decide to take down v1

## 10 March 2025

- Dropped pyprland in favor of hyprland built in tool for a drop down like terminal and Desktop magnifier

## 06 March 2025

- Switched to whiptail version for Y & N questions
- switched eza to lsd

## 23 Feb 2025

- added Victor Mono Font for proper hyprlock font rendering for Dots v2.3.12
- added Fantasque Sans Mono Nerd for Kitty

## 22 Feb 2025

- replaced eog with loupe
- changed url for installing oh-my-zsh to get wider coverage. Some countries are blocking github raw url's

## 20 Feb 2025

- Added nwg-displays for the upcoming Kools dots v2.3.12

## 18 Feb 2025

- Change default zsh theme to adnosterzak
- pokemon coloscript integrated with fastfetch when opted with pokemon to add some bling
- additional external oh-my-zsh theme

## 06 Feb 2025

- added semi-unattended function.
- move all the initial questions at the beginning

## 04 Feb 2025

- Re-coded for better visibility
- Offered a new SDDM theme.
- script will automatically detect if you have nvidia but script still offer if you want to set up for user

## 29 Jan 2025

- enhanced nvidia.sh to add additional systemd-bootloader entries for nvidia

## 16 Jan 2025

- updated nvidia.sh to install non-git libva-nvidia-driver

## 13 Jan 2025

- replaced polkit-gnome with hyprpolkitagent

## 12 Jan 2025

- switch to final version of aylurs-gtk-shell-v1

## 11 Jan 2025

- added cachyos-hyprland-settings to uninstall

## 06 Jan 2025

- added copying of modified fastfetch-compact for Arch
- default theme for oh my zsh theme is now "funky"

## 26 Dec 2024

- Removal of Bibata Ice cursor on assets since its integrated in the GTK Themes and Icons extract from a separate repo
- integrated hyprcursor in Bibata Ice Cursor

## 15 Nov 2024

- revert Aylurs GTK Shell (AGS) to install older version
- added aylurs-gtk-shell to uninstall

## 20 Sep 2024

- User will be ask if they want to set Thunar as default file manager if they decided to install it

## 19 Sep 2024

- Added fastfetch on tty. However, will be disabled if user decided to install pokemon colorscripts

## 18 Sep 2024

- dotfiles will now be downloaded from main or master branch instead of from the releases version.

## 14 Sep 2024

- remove the final error checks instead, introduced a final check of essential packages to ran Hyprland

## 08 Sep 2024

- Added final error checks on install-logs

## 07 Sep 2024

- added pulseaudio check
- added sof-firmware

## 29 Aug 2024

- switched over to non-git wallust package
- improved indentions on some install scripts

## 28 Aug 2024

- Added final check if hyprland is installed and will give an error to user

## 26 Aug 2024

- Set to uninstall rofi as conflicts with rofi-wayland
- added nvidia_drm.fbdev=1 for grub

## 14 Aug 2024

- added archlinux-keyring on base.sh

## 08 Aug 2024

- Increased to 1 sec delay for installing base-devel

## 07 Jul 2024

- added eza (ls replacement for tty). Note only on .zshrc

## 25 Jun 2024

- added fbdev=1 for nvidia.sh on `/etc/modprobe.d/nvidia.conf`. see here `https://wiki.hyprland.org/Nvidia/#drm-kernel-mode-setting`

## 26 May 2024

- Added fzf for zsh (CTRL R to invoke FZF history)

## 23 May 2024

- added qalculate-gtk to work with rofi-calc. Default keybinds (SUPER ALT C)
- added power-profiles-daemon for ROG laptops. Note, I cant add to all since it conflicts with TLP, CPU-Auto-frequency etc.
- added fastfetch

## 22 May 2024

- nwg-look is now in extra repo so replaced with nwg-look from nwg-look-bin
- change the sddm theme destination to /etc/sddm.conf.d/10-theme.conf to theme.conf.user

## 19 May 2024

- Disabled the auto-login in .zprofile as it causes auto-login to Hyprland if any wayland was chosen. Can enabled if only using hyprland

## 10 May 2024

- added wallust-git and remove python-pywal for migration to wallust on Hyprland-Dots v2.2.11

## 08 May 2024

- Adjusted sddm.sh since it does not respect preset.sh
- install.sh have been rearranged so it quits if user choose not to proceed

## 07 May 2024

- Minor typo change on nvidia.sh
- switch back to cava since installing cava-git keep it hanging (see known-issue on readme)

## 05 May 2024

- switched to rofi-wayland Extra Repo

## 04 May 2024

- separated fonts installation script for easy debugging

## 03 May 2024

- added python3-pyquery for new weather-waybar python based on Hyprland-Dots

## 02 May 2024

- Added pyprland (hyprland plugin)

## 26 Apr 2024

- Updated sddm.sh for Qt6 variant

## 23 Apr 2024

- Dropping swayidle and swaylock in favor of hypridle and hyprlock

## 20 Apr 2024

- Change default Oh-my-zsh theme to xiong-chiamiov-plus

## 16 Mar 2024

- added hyprcursor

## 1 Mar 2024

- replaced sddm-git with sddm

## 11 Jan 2024

- dropped wlsunset

## 05 Jan 2024

- Added a preset feature
- Added templates for contributing, and reporting, etc

## 01 Jan 2024

- Re-coded complete and test
- Added to spice up pacman.conf including adding of ILoveCandy on it :)

## 30 Dec 2023

- Install scripts reconstructed

## 29 December 2023

- Remove dunst in favor of swaync. NOTE: Part of the script is to also uninstall mako and dunst (if installed) as on my experience, dunst is sometimes taking over the notification even if it is not set to start

## 16 Dec 2023

- zsh theme switched to `agnoster` theme by default
- pywal tty color change disabled by default

## 13 Dec 2023

- switched hyprland to Extra Repo hyprland (both nvidia and non-nvidia). Seeing they are updating all the time :)

## 11 Dec 2023

- Changing over to zsh automatically if user opted
- If chose to install zsh and have no login manager, zsh auto login will auto start Hyprland
- added as optional, with zsh, pokemon colorscripts
- improved zsh install scripts, so even the existing zsh users of can still opt for zsh and oh-my-zsh installation :)

## 03 Dec 2023

- Added kvantum for qt apps theming
- return of wlogout due to theming issues of rofi-power

## 01 Dec 2023

- Added pipewire to install

## 30 Nov 2023

- switched to swaylock-effects-git as non-git does not seem to work

## 29 Nov 2023

- nvidia.sh edited to remove hyprland-nvidia-git as well

## 26 Nov 2023

- nvidia - Move to hyprland-git. see [`commit`](https://github.com/hyprwm/Hyprland/commit/cd96ceecc551c25631783499bd92c6662c5d3616)

## 25 Nov 2023

- drop wlogout since Hyprland-Dots v2.1.9 uses rofi-power

## 23-Nov-2023

- Added Bibata cursor to install if opted for GTK Themes. However, it is not pre-applied. Use nwg-look utility to apply

## 19-Nov-2023

- Adjust dotfiles script to download from releases instead of from upstream
