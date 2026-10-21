#!/bin/bash
# Desktop packages (the compositor itself is mango.sh's) #

# edit your packages desired here. 
# WARNING! If you remove packages here, dotfiles may not work properly.
# and also, ensure that packages are present in AUR and official Arch Repo

# add packages wanted here
Extra=(

)

hypr_package=(
  #aylurs-gtk-shell
  avahi
  bc
  cliphist
  curl
  foot
  grim
  gvfs
  gvfs-mtp
  gvfs-smb
  gvfs-nfs
  gvfs-dnssd
  # WS-Discovery for Thunar's Network view (network:///): how Windows PCs and
  # current Samba servers announce themselves, now that NetBIOS browsing is
  # gone. gvfs-dnssd + avahi cover the mDNS half. Pulls in wsdd.
  gvfs-wsdd
  # Night light (hypr/scripts/NightLight.sh, behind the bar's ПУЛЬТ card):
  # wlsunset, a wlroots gamma client - hyprsunset speaks only Hyprland's own
  # protocol.
  wlsunset
  # Screens off and on for hypridle (IdleDpms.sh, after_sleep_cmd): wlopm,
  # through the wlroots output-power protocol (Hyprland had `hyprctl dispatch
  # dpms`).
  wlopm
  # The outputs as JSON for the bar's capture dialogs (Monitors.qml): wlr-randr
  # replaces `hyprctl monitors` there.
  wlr-randr
  # The polkit agent is the bar (PolkitState.qml); Polkit.sh starts this one
  # only when the bar is not there to answer.
  hyprpolkitagent
  # The Qt Quick style mango/env.conf names (QT_QUICK_CONTROLS_STYLE
  # org.hyprland.style). hyprpolkitagent pulls it in too, but nothing else
  # would once Hyprland itself is gone.
  hyprland-qt-support
  imagemagick
  inxi
  jq
  kvantum
  libspng
  nano
  networkmanager
  nm-connection-editor
  pamixer
  pavucontrol
  playerctl
  # wtype: the clipboard picker pastes into the window that had focus, which
  # needs a virtual-keyboard typer. It was already a silent dependency of the
  # rofi ClipManager.sh this replaced - installed here, but in no package list,
  # so a fresh machine got a picker that quietly failed to paste.
  wtype
  # qrencode: the bar's network card turns the current Wi-Fi into a join QR
  # (config/quickshell/bar/scripts/network-qr.sh). Without it that button
  # reports the package as missing rather than failing silently.
  qrencode
  # power-profiles-daemon is deliberately NOT here: on CachyOS the API is
  # provided by tuned-cachy-ppd, which conflicts with it, and a conflicting
  # --noconfirm transaction stops the install. power_profiles.sh installs it
  # only when nothing already provides the interface.
  # python-requests: UserScripts/Weather.py and the bar's weather-location.py.
  python-requests
  # python-pyquery is deliberately NOT here any more. Its only consumer was
  # quickshell/bar/scripts/weather.py, which scraped weather.com and has been
  # removed - the bar fetches from Open-Meteo through weather-fetch.sh ->
  # weather-location.py, which needs requests and nothing else.
  # SovietLockGen.py imports gi/Pango (python-gobject) and cairo (python-cairo)
  # to measure text before it sizes the lock screen widgets. It runs from
  # mango/startup.conf on every login, and without these it fails silently -
  # hyprlock-monitors.conf is then never regenerated and the lock screen keeps
  # whatever geometry the committed file was built for.
  python-gobject
  python-cairo
  # notify-send. 82 call sites across the hypr scripts. It used to be listed
  # only in three battery/disk/temp monitor scripts that install.sh never
  # called, so it was never actually installed; those scripts have since been
  # deleted and libnotify belongs here, in the list that always runs.
  libnotify
  qt5ct
  qt6ct
  qt6-svg
  rofi
  # The launcher's ФАЙЛЫ tab (hypr/scripts/RofiFiles.sh) lists files with fd.
  # neovim.sh also installs it, but that option is off by default.
  fd
  slurp
  satty
  dunst
  awww
  systemd-resolvconf
  unzip # needed later
  # rust BEFORE wallust. wallust is an AUR build that makedepends on `cargo`,
  # and with no Rust installed yay picks the first repo package that provides
  # it. On CachyOS that is now cachyos-extra's rustup (the CachyOS rebuild of
  # rust is gone and rust itself is only in [extra], which comes later), and
  # rustup arrives with no default toolchain: wallust still builds (its PKGBUILD
  # exports RUSTUP_TOOLCHAIN=stable), but afterwards every bare cargo/rustc
  # fails with "no default is configured", neovim.sh cannot add rust-analyzer,
  # and AUR builds that run a bare `cargo build` die. Asked for by name,
  # `rust` resolves to [extra] on both distros; where rustup is already the
  # user's choice, `-Q rust` finds it through its provides and this is skipped.
  rust
  wallust
  wget
  wf-recorder
  wireguard-tools
  wl-clipboard
  xdg-user-dirs
  xdg-utils
  yad
)

# the following packages can be deleted. however, dotfiles may not work properly
hypr_package_2=(
  brightnessctl
  btop
  cava
  loupe
  # The default image and PDF viewers in mimeapps.list. Without them xdg-open
  # fell back to whatever the system cache picked: Chromium for both.
  imv
  papers
  fastfetch
  gnome-system-monitor
  # librewolf, not librewolf-bin: the -bin package left the AUR when LibreWolf
  # entered [extra]. Asking for the old name fails every fresh install, which
  # trips the final check and blocks the auto-reboot - and mimeapps.list points
  # http/https at librewolf.desktop, so there was no default browser either.
  librewolf
  mousepad
  # GLib (Thunar, every GTK "open") runs a Terminal=true app - nvim, vim, micro,
  # btop - through xdg-terminal-exec, or else through a fixed list of terminals
  # that has no foot. Without it, "Open With > Neovim" failed with "Unable to
  # find terminal required for application"; it picks foot.desktop on its own.
  xdg-terminal-exec
  # vim is the editor mango/env.conf exports as $EDITOR. Only nano was
  # installed, so $EDITOR pointed at nothing.
  vim
  mpv
  mpv-mpris
  # UserScripts/WallpaperSelect.sh lists *.mp4/.mkv/.mov/.webm from
  # ~/Pictures/wallpapers alongside the images and builds thumbnails for them,
  # so video wallpapers are an offered feature - but mpvpaper, the only thing
  # that can play one as a background, was in no package list at all. Picking a
  # video set the next login to play it (WallpaperStart.sh), and the login came
  # up with no wallpaper. The script now refuses when this is missing;
  # installing it means it does not have to.
  mpvpaper
  # Gaming overlay and micro-compositor. mangohud is the fps cap / frametime
  # HUD the Steam launch option `mangohud %command%` pulls in, and it reads
  # config/MangoHud/MangoHud.conf that copy.sh lays down - without the package
  # that config is inert. lib32-mangohud is needed because 32-bit games load
  # the 32-bit Vulkan layer; multilib is already enabled by pacman.sh.
  # gamescope is not needed for a normal game, but it is what provides FSR 1.0
  # upscaling and the resolution/cursor isolation a misbehaving title needs -
  # and mango/keybinds.conf leaves SUPER + U/N/I/S/G free for it. See
  # GAMES_README.md.
  mangohud
  lib32-mangohud
  gamescope
  nvtop
  nwg-look
  # Monitor layout GUI for wlroots compositors (Quick Settings "Мониторы"):
  # nwg-displays drives only sway and Hyprland. wdisplays applies a layout for
  # the session; ~/.config/mango/monitors.conf is the one that lasts.
  wdisplays
  pacman-contrib
  qalculate-gtk
  yt-dlp
  # avahi is installed above and thunar.sh enables avahi-daemon, but the daemon
  # alone does not make .local names resolve: glibc only asks it if nss-mdns is
  # installed AND wired into /etc/nsswitch.conf. services.sh does the wiring.
  nss-mdns
)

# List of packages to uninstall as it conflicts some packages
uninstall=(
  aylurs-gtk-shell
  # dunst deliberately NOT listed here: it is the notification daemon this
  # setup uses and is installed above. It was in both arrays, so every run
  # removed it and immediately reinstalled it.
  cachyos-hyprland-settings
  # CachyOS's own mango editions (Noctalia and DankMaterialShell): their shell
  # and settings would sit on top of this one. mangowm itself stays - mango.sh
  # marks it as explicitly installed.
  cachyos-mango-noctalia
  cachyos-mangowc-dms
  swaync
  # rofi deliberately NOT listed here: it is the launcher this setup uses and
  # is installed above. Being in both arrays meant every re-run removed it and
  # immediately reinstalled it - the same churn dunst used to have.
  wallust-git
  rofi-lbonn-wayland
  rofi-lbonn-wayland-git
)

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Change the working directory to the parent directory of the script
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "[ERROR] Failed to change directory to $PARENT_DIR"; exit 1; }

# Source the global functions script
if ! source "$SCRIPT_DIR/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi



# Set the name of the log file to include the current date and time
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_hypr-pkgs.log"

# conflicting packages removal
overall_failed=0
printf "\n%s - ${SKY_BLUE}Removing some packages${RESET} as they conflict with these dotfiles \n" "${NOTE}"
for PKG in "${uninstall[@]}"; do
  uninstall_package "$PKG" 2>&1 | tee -a "$LOG"
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    overall_failed=1
  fi
done

if [ $overall_failed -ne 0 ]; then
  echo -e "${ERROR} Some packages failed to uninstall. Please check the log."
fi

printf "\n%.0s" {1..1}

# systemd-resolvconf conflicts with openresolv, and `--noconfirm` cannot answer
# the "remove openresolv?" prompt - the transaction just fails, the package
# lands in .failed-packages, and services.sh (which keys resolved off
# systemd-resolvconf being installed) never enables resolved either. A stock
# archinstall + NetworkManager box has no openresolv, but netctl, openfortivpn
# and some dhcpcd setups pull it in. Remove it up front when nothing needs it;
# when something does, leave both alone and say so rather than break that.
if pacman -Qi openresolv &>/dev/null && ! pacman -Qi systemd-resolvconf &>/dev/null; then
  # LC_ALL=C: pacman localises its field names ("Requerido por", "Krävs av"), and
  # on a non-English system this came back empty - read as "nothing needs it".
  _req="$(LC_ALL=C pacman -Qi openresolv 2>/dev/null | sed -n 's/^Required By *: *//p')"
  if [ -z "$_req" ] || [ "$_req" = "None" ]; then
    echo "${NOTE} openresolv is installed and conflicts with systemd-resolvconf - removing it first." | tee -a "$LOG"
    uninstall_package openresolv 2>&1 | tee -a "$LOG"
  else
    echo "${WARN} openresolv is required by: ${_req}. systemd-resolvconf conflicts with it and will fail to install;" | tee -a "$LOG"
    echo "${WARN} DNS stays on openresolv. Remove those packages and re-run if you want systemd-resolved." | tee -a "$LOG"
  fi
fi

# Installation of main components
printf "\n%s - Installing ${SKY_BLUE}the desktop packages${RESET} .... \n" "${NOTE}"

for PKG1 in "${hypr_package[@]}" "${hypr_package_2[@]}" "${Extra[@]}"; do
  install_package "$PKG1" "$LOG"
done

# ttfx draws the screensaver (hypr/scripts/Screensaver.sh). AUR only, and not in
# the lists above because it is built without its tests: one of them compares
# the animation curves with Python-made values bit for bit, and on CachyOS's
# CPU-tuned glibc one sample of ~34,000 differs in the last bits, so the build
# failed. Harmless - the effects snap to whole cells and colours. An update
# through the AUR helper runs the tests again; on CachyOS that is
# `yay -S ttfx --mflags --nocheck`.
if pacman -Q ttfx &>/dev/null; then
  echo -e "${INFO} ${MAGENTA}ttfx${RESET} is already installed. Skipping..."
else
  (
    stdbuf -oL env --default-signal=INT $AUR_ENV $ISAUR -S --noconfirm --mflags --nocheck ttfx 2>&1
  ) >> "$LOG" 2>&1 &
  PID=$!
  show_progress $PID "ttfx"
  if pacman -Q ttfx &>/dev/null; then
    echo -e "${OK} Package ${YELLOW}ttfx${RESET} has been successfully installed!"
    clear_package_failure ttfx
  else
    echo -e "\n${ERROR} ${YELLOW}ttfx${RESET} failed to install - the screensaver will not start. See $LOG."
    record_package_failure ttfx
  fi
fi

printf "\n%.0s" {1..2}
