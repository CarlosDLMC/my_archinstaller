#!/bin/bash
# Hyprland Packages #

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
  hyprsunset
  hyprpolkitagent
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
  # Startup_Apps.lua on every login, and without these it fails silently -
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
  slurp
  satty
  dunst
  awww
  systemd-resolvconf
  unzip # needed later
  wallust
  wget
  wf-recorder
  wireguard-tools
  wl-clipboard
  wlogout
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
  fastfetch
  gnome-system-monitor
  # librewolf, not librewolf-bin: the -bin package left the AUR when LibreWolf
  # entered [extra]. Asking for the old name fails every fresh install, which
  # trips the final check and blocks the auto-reboot - and mimeapps.list points
  # http/https at librewolf.desktop, so there was no default browser either.
  librewolf
  mousepad
  # vim is the editor UserConfigs/01-UserDefaults.lua names and ENVariables.lua
  # exports as $EDITOR. Only nano was installed, so $EDITOR pointed at nothing.
  vim
  mpv
  mpv-mpris
  # UserScripts/WallpaperSelect.sh lists *.mp4/.mkv/.mov/.webm from
  # ~/Pictures/wallpapers alongside the images and builds thumbnails for them,
  # so video wallpapers are an offered feature - but mpvpaper, the only thing
  # that can play one as a background, was in no package list at all. Picking a
  # video rewrote Startup_Apps.lua to launch it and the next login came up with
  # no wallpaper. The script now refuses when this is missing; installing it
  # means it does not have to.
  mpvpaper
  # Gaming overlay and micro-compositor. mangohud is the fps cap / frametime
  # HUD the Steam launch option `mangohud %command%` pulls in, and it reads
  # config/MangoHud/MangoHud.conf that copy.sh lays down - without the package
  # that config is inert. lib32-mangohud is needed because 32-bit games load
  # the 32-bit Vulkan layer; multilib is already enabled by pacman.sh.
  # gamescope is not needed for a normal game, but it is what provides FSR 1.0
  # upscaling and the resolution/cursor isolation a misbehaving title needs -
  # and Keybinds.lua already frees SUPER + U/N/I/S/G for it. See GAMES_README.md.
  mangohud
  lib32-mangohud
  gamescope
  nvtop
  nwg-look
  nwg-displays
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
if ! source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi



# Set the name of the log file to include the current date and time
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_hypr-pkgs.log"

# conflicting packages removal
overall_failed=0
printf "\n%s - ${SKY_BLUE}Removing some packages${RESET} as they conflict with these Hyprland dotfiles \n" "${NOTE}"
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
  _req="$(pacman -Qi openresolv 2>/dev/null | sed -n 's/^Required By *: *//p')"
  if [ -z "$_req" ] || [ "$_req" = "None" ]; then
    echo "${NOTE} openresolv is installed and conflicts with systemd-resolvconf - removing it first." | tee -a "$LOG"
    uninstall_package openresolv 2>&1 | tee -a "$LOG"
  else
    echo "${WARN} openresolv is required by: ${_req}. systemd-resolvconf conflicts with it and will fail to install;" | tee -a "$LOG"
    echo "${WARN} DNS stays on openresolv. Remove those packages and re-run if you want systemd-resolved." | tee -a "$LOG"
  fi
fi

# Installation of main components
printf "\n%s - Installing ${SKY_BLUE}the necessary Hyprland packages${RESET} .... \n" "${NOTE}"

for PKG1 in "${hypr_package[@]}" "${hypr_package_2[@]}" "${Extra[@]}"; do
  install_package "$PKG1" "$LOG"
done

printf "\n%.0s" {1..2}
