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
  inotify-tools
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
  # power-profiles-daemon is deliberately NOT here: on CachyOS the API is
  # provided by tuned-cachy-ppd, which conflicts with it, and a conflicting
  # --noconfirm transaction stops the install. power_profiles.sh installs it
  # only when nothing already provides the interface.
  python-requests
  python-pyquery
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
  swappy
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
  librewolf-bin
  mousepad
  mpv
  mpv-mpris
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
cd "$PARENT_DIR" || { echo "${ERROR} Failed to change directory to $PARENT_DIR"; exit 1; }

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
  if [ $? -ne 0 ]; then
    overall_failed=1
  fi
done

if [ $overall_failed -ne 0 ]; then
  echo -e "${ERROR} Some packages failed to uninstall. Please check the log."
fi

printf "\n%.0s" {1..1}

# Installation of main components
printf "\n%s - Installing ${SKY_BLUE}the necessary Hyprland packages${RESET} .... \n" "${NOTE}"

for PKG1 in "${hypr_package[@]}" "${hypr_package_2[@]}" "${Extra[@]}"; do
  install_package "$PKG1" "$LOG"
done

printf "\n%.0s" {1..2}
