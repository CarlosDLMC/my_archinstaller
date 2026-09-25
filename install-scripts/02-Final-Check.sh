#!/bin/bash
# Final checking if packages are installed
#
# Two sources are checked, and the script exits non-zero if either reports
# something missing - install.sh keys its auto-reboot off that exit code.
#
#   1. The hardcoded list below. This is a floor, not the whole check: it
#      catches a package that never got attempted at all, e.g. because its
#      install script was skipped by the preset or died before reaching it.
#   2. Install-Logs/.failed-packages, written by record_package_failure() in
#      Global_functions.sh every time an install_* function's post-install
#      verification fails. That covers every package any script actually tried
#      to install - roughly a hundred of them - rather than only these sixteen.

packages=(
  cliphist
  kvantum
  # rofi, not rofi-wayland: rofi-wayland was merged back into rofi and is what
  # 01-hypr-pkgs.sh installs.
  rofi
  imagemagick
  # dunst, not mako: dunst is the notification daemon this setup runs
  # (configs/Startup_Apps.lua). Checking for mako made the final screen of every
  # single install report a missing essential package.
  dunst
  awww
  wallust
  wl-clipboard
  wlogout
  foot
  hypridle
  hyprlock
  hyprland
  hyprpolkitagent
  # wtype: the clipboard picker pastes into the window that had focus, and
  # clip-paste.sh exits quietly when wtype is absent - so without it Enter
  # copies and nothing appears, with no error anywhere. Exactly the kind of
  # missing package this check exists to catch.
  wtype
  # qrencode: the network card's share-QR. It reports its own absence rather
  # than failing silently, but it is a one-line package and a dead button on a
  # fresh machine is still a bad first impression.
  qrencode
)

# Local packages that should be in /usr/local/bin/
local_pkgs_installed=(

)

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
# Determine the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Change the working directory to the parent directory of the script
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "[ERROR] Failed to change directory to $PARENT_DIR"; exit 1; }

# Source the global functions script
source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"

# Set the name of the log file to include the current date and time
LOG="Install-Logs/00_CHECK-$(date +%Y%m%d-%H%M%S)_installed.log"

printf "\n%s - Final Check if all ${SKY_BLUE}Essential packages${RESET} were installed \n" "${NOTE}"
# Initialize an empty array to hold missing packages
missing=()
local_missing=()

# Function to check if a packages are installed using pacman
is_installed_pacman() {
    pacman -Qi "$1" &>/dev/null
}

# Loop through each package
for pkg in "${packages[@]}"; do
    # Check if the packages are installed
    if ! is_installed_pacman "$pkg"; then
        missing+=("$pkg")
    fi
done

# Check for local packages
for pkg1 in "${local_pkgs_installed[@]}"; do
    if ! [ -f "/usr/local/bin/$pkg1" ]; then
        local_missing+=("$pkg1")
    fi
done

# Fold in everything any install script failed on.
#
# Re-verified rather than trusted: a package can fail its own install and then
# be pulled in later as a dependency of something else, and reporting it as
# missing when it is sitting there installed would train you to ignore this
# screen. Only what is genuinely still absent is reported.
if [ -f "$FAILED_PACKAGES_MANIFEST" ]; then
    while read -r pkg; do
        [ -n "$pkg" ] || continue
        is_installed_pacman "$pkg" && continue
        # Skip anything the hardcoded list above already reported.
        already="no"
        for seen in "${missing[@]}"; do
            [ "$seen" == "$pkg" ] && already="yes" && break
        done
        [ "$already" == "yes" ] && continue
        missing+=("$pkg")
    done < "$FAILED_PACKAGES_MANIFEST"
fi

# Outcome checks: did each selected component actually produce what it exists
# to produce? Package presence alone missed the failures that matter most. A
# copy.sh that died left vanilla Hyprland with every package "installed"; a
# locales.sh killed by set -e left LC_TIME pointing at a locale that was never
# generated; a chsh that failed left bash as the login shell. None of those is
# a package, so none of them stopped the reboot, and install.sh used to clear
# the screen right before this point so the evidence was gone as well.
#
# install.sh exports the selection as INSTALL_SELECTED_OPTIONS. Checks that
# do not depend on a selection always run.
outcome_failures=()
sel=" ${INSTALL_SELECTED_OPTIONS:-} "

selected() { [[ "$sel" == *" $1 "* ]]; }

# check_outcome <what failed> <command...>
check_outcome() {
    local what="$1"; shift
    if ! "$@" &>/dev/null; then
        outcome_failures+=("$what")
    fi
}

# Always: these run on every install regardless of the preset.
check_outcome "ru_RU.UTF-8 locale not generated - clock, calendar and lock screen fall back to English (install-scripts/locales.sh)" \
    bash -c 'locale -a | grep -qi "^ru_RU\.utf8$"'
# Runs it rather than only finding it: a helper that is on PATH but cannot start
# (paru-bin against a newer libalpm) passed `command -v` while every AUR install
# failed.
check_outcome "no working AUR helper - yay/paru missing or does not start (install-scripts/yay.sh)" \
    bash -c 'yay --version || paru --version'
check_outcome "NetworkManager.service is not enabled (install-scripts/services.sh)" \
    systemctl is-enabled NetworkManager.service
if pacman -Qi systemd-resolvconf &>/dev/null; then
    check_outcome "systemd-resolvconf is installed but systemd-resolved is not enabled - DNS will fail (install-scripts/services.sh)" \
        systemctl is-enabled systemd-resolved.service
fi

# A failed initramfs rebuild boots the previous image: no NVIDIA modules, no
# nouveau blacklist, no new plymouth theme. Nothing else here can see that.
if [ -s "$INITRAMFS_FAILED_MANIFEST" ]; then
    outcome_failures+=("initramfs rebuild failed in: $(sort -u "$INITRAMFS_FAILED_MANIFEST" | tr '\n' ' ')- fix the error in Install-Logs/ and rebuild it (sudo limine-mkinitcpio on CachyOS+Limine, else sudo mkinitcpio -P)")
fi

if selected dots; then
    check_outcome "dotfiles not deployed: ~/.config/hypr/hyprland.lua is missing (install-scripts/dotfiles-main.sh)" \
        test -f "$HOME/.config/hypr/hyprland.lua"
    check_outcome "dotfiles not deployed: ~/.config/quickshell/bar/shell.qml is missing (install-scripts/dotfiles-main.sh)" \
        test -f "$HOME/.config/quickshell/bar/shell.qml"
    check_outcome "dotfiles not deployed: ~/.zshrc is missing (install-scripts/dotfiles-main.sh)" \
        test -f "$HOME/.zshrc"
    check_outcome "wallpaper not seeded: ~/.config/hypr/wallpaper_effects/.wallpaper_current is missing (Hyprland-Dots/copy.sh)" \
        test -f "$HOME/.config/hypr/wallpaper_effects/.wallpaper_current"
    check_outcome "dotfiles not deployed: ~/.config/zsh/herdr-layouts.zsh is missing - hdl/hds/hdlm/hsl will not exist (Hyprland-Dots/copy.sh)" \
        test -f "$HOME/.config/zsh/herdr-layouts.zsh"
fi

if selected ly; then
    check_outcome "ly@tty2.service is not enabled (install-scripts/ly.sh)" \
        systemctl is-enabled ly@tty2.service
    check_outcome "/etc/ly/config.ini does not match assets/ly/config.ini (install-scripts/ly_config.sh)" \
        cmp -s /etc/ly/config.ini "assets/ly/config.ini"
fi

if selected zsh; then
    check_outcome "login shell is not zsh (install-scripts/zsh.sh)" \
        bash -c '[[ "$(getent passwd "$USER" | cut -d: -f7)" == */zsh ]]'
    check_outcome "~/.oh-my-zsh is missing (install-scripts/zsh.sh)" \
        test -f "$HOME/.oh-my-zsh/oh-my-zsh.sh"
    # .zshrc loads both from the plugins list; a failed clone is now reported by
    # zsh.sh and the script carries on, so this is where it stops the reboot.
    for _plugin in zsh-autosuggestions zsh-syntax-highlighting; do
        check_outcome "oh-my-zsh plugin $_plugin was not cloned (install-scripts/zsh.sh)" \
            test -d "$HOME/.oh-my-zsh/custom/plugins/$_plugin"
    done
fi

if selected nvidia; then
    # The module, not the package: a DKMS build that failed inside pacman's hook
    # still leaves the dkms package "installed". One check per installed kernel,
    # so a fallback kernel with no module is named too.
    for _moddir in /usr/lib/modules/*/; do
        [ -f "$_moddir/pkgbase" ] || continue
        # Installed kernels only (vmlinuz owned by a package) - see nvidia.sh.
        pacman -Qqo "${_moddir}vmlinuz" &>/dev/null || continue
        _kver=$(basename "$_moddir")
        check_outcome "no NVIDIA kernel module for $(cat "$_moddir/pkgbase") ($_kver) - that kernel boots without the NVIDIA driver (install-scripts/nvidia.sh)" \
            modinfo -k "$_kver" -n nvidia
    done
fi

if selected pokemon; then
    check_outcome "pokemon-colorscripts is not on PATH - every terminal prints an error (install-scripts/zsh_pokemon.sh)" \
        command -v pokemon-colorscripts
fi

if selected gtk_themes; then
    check_outcome "icon theme Flat-Remix-Blue-Dark not extracted to ~/.icons (GTK-themes-icons/auto-extract.sh)" \
        test -d "$HOME/.icons/Flat-Remix-Blue-Dark"
    check_outcome "cursor theme Bibata-Modern-Ice not extracted to ~/.icons (GTK-themes-icons/auto-extract.sh)" \
        test -d "$HOME/.icons/Bibata-Modern-Ice"
fi

if selected nopasswd_sudo; then
    # Not `sudo -n true`: the installer's keepalive refreshes the sudo timestamp,
    # so that passes whether or not the rule landed. Look for the rule itself.
    # "NOPASSWD: ALL", not "NOPASSWD:" - bluetooth.sh installs a rule of its own
    # (rfkill and systemctl start/stop bluetooth only), and a bare "NOPASSWD:"
    # matched that one too, so a failed wheel rule passed whenever bluetooth
    # was also selected.
    check_outcome "no NOPASSWD: ALL rule applies to $USER - the bar's VPN widget will not work (install-scripts/sudoers_nopasswd.sh)" \
        bash -c 'sudo -n -l 2>/dev/null | grep -q "NOPASSWD: ALL"'
fi

if selected bluetooth; then
    check_outcome "bluez is not installed (install-scripts/bluetooth.sh)" \
        pacman -Qi bluez
    check_outcome "bluetooth.service is not enabled - Bluetooth is off at every boot (install-scripts/bluetooth.sh)" \
        systemctl is-enabled bluetooth.service
    check_outcome "/etc/sudoers.d/bluetooth-toggle is missing - the bar's bluetooth toggle will not work (install-scripts/bluetooth.sh)" \
        sudo test -f /etc/sudoers.d/bluetooth-toggle
fi

if selected quickshell; then
    check_outcome "quickshell is not installed (install-scripts/quickshell.sh)" \
        pacman -Qi quickshell
fi

if selected xdph; then
    check_outcome "xdg-desktop-portal-hyprland is not installed (install-scripts/xdph.sh)" \
        pacman -Qi xdg-desktop-portal-hyprland
fi

if selected printing; then
    check_outcome "cups.socket is not enabled (install-scripts/printing.sh)" \
        systemctl is-enabled cups.socket
fi

if selected docker; then
    check_outcome "docker.socket is not enabled (install-scripts/docker.sh)" \
        systemctl is-enabled docker.socket
    # Membership is what makes `docker` usable without sudo, and usermod only
    # takes effect at the next login - so check the group file, not `id`.
    check_outcome "$USER is not in the 'docker' group (install-scripts/docker.sh)" \
        bash -c 'getent group docker | cut -d: -f4 | tr "," "\n" | grep -qx "$USER"'
fi

if selected handy; then
    check_outcome "handy is not on PATH (install-scripts/handy.sh)" \
        command -v handy
fi

# herdr and hunk install into ~/.local/bin, which is NOT on PATH during the
# install - nothing in the installer puts it there, and the .zshrc guard only
# applies to shells started afterwards. So these test the path directly; a
# `command -v` here would report a failure on a perfectly good install.
if selected herdr; then
    check_outcome "herdr is not installed at ~/.local/bin/herdr (install-scripts/herdr.sh)" \
        test -x "$HOME/.local/bin/herdr"
    check_outcome "~/.config/herdr/config.toml is missing (Hyprland-Dots/copy.sh)" \
        test -f "$HOME/.config/herdr/config.toml"
    # An unsubstituted __HOME__ leaves every CTRL+ALT+N tab bind and the ALT+Q
    # close-workspace popup pointing at a path that does not exist. herdr reports
    # nothing for it - the keys simply do nothing - so it has to be checked here.
    check_outcome "__HOME__ placeholders left in ~/.config/herdr/config.toml - the tab and close-workspace binds will do nothing (install-scripts/herdr.sh)" \
        bash -c '! grep -q "__HOME__" "$HOME/.config/herdr/config.toml"'
    check_outcome "herdr-workspace-numbers.service is not enabled - the sidebar's number column stops updating after a server restart (install-scripts/herdr.sh)" \
        systemctl --user is-enabled herdr-workspace-numbers.service
    # Every [[keys.command]] entry names a helper script by absolute path, and a
    # binding whose script did not ship does nothing and reports nothing - the
    # same silent failure the __HOME__ check above exists to catch. Reading the
    # bindings out of the installed config rather than listing the helpers here
    # means a binding added later is covered without touching this file.
    check_outcome "a herdr keybinding points at a helper script that is not installed or not executable (Hyprland-Dots/.local/bin, Hyprland-Dots/copy.sh)" \
        python3 -c 'import tomllib, os, sys; cfg = os.path.expanduser("~/.config/herdr/config.toml"); d = tomllib.load(open(cfg, "rb")); cmds = d.get("keys", {}).get("command", []); missing = [c["command"] for c in cmds if not os.access(c["command"].split()[0], os.X_OK)]; print("\n".join(missing)); sys.exit(1 if missing else 0)'
fi

if selected neovim; then
    check_outcome "nvim is not installed (install-scripts/neovim.sh)" \
        command -v nvim
    check_outcome "LazyVim config missing: ~/.config/nvim/lua/config/lazy.lua - Space E has no file tree (install-scripts/neovim.sh)" \
        test -f "$HOME/.config/nvim/lua/config/lazy.lua"
    # The colorscheme is two files and they fail differently. A missing
    # colors/pycharm-dark.lua while lua/plugins/colorscheme.lua names it is the
    # bad case: LazyVim asks for a scheme that does not exist and nvim opens on
    # an error, so check the palette itself rather than only the opts file.
    check_outcome "colors/pycharm-dark.lua is missing or differs from assets/nvim/pycharm-dark.lua (install-scripts/neovim.sh)" \
        cmp -s "$HOME/.config/nvim/colors/pycharm-dark.lua" "assets/nvim/pycharm-dark.lua"
    # Only warns if nothing selects a colorscheme at all - a file of your own
    # choosing a different scheme is a deliberate choice, not a failure.
    check_outcome "no colorscheme set: ~/.config/nvim/lua/plugins/colorscheme.lua is missing, so nvim falls back to LazyVim's tokyonight (install-scripts/neovim.sh)" \
        test -f "$HOME/.config/nvim/lua/plugins/colorscheme.lua"
    # nvim-treesitter's `main` branch builds parsers with the tree-sitter CLI and
    # fails hard without it. mason cannot supply it from a headless run, which is
    # why neovim.sh takes it from the repos - verify that actually happened.
    check_outcome "tree-sitter CLI is not installed - nvim-treesitter cannot build parsers, so there is no syntax highlighting (install-scripts/neovim.sh)" \
        command -v tree-sitter
fi

if selected hunk; then
    check_outcome "hunk is not installed at ~/.local/bin/hunk (install-scripts/hunk.sh)" \
        test -x "$HOME/.local/bin/hunk"
fi

if selected plymouth; then
    check_outcome "plymouth default theme is not 'soviet' (install-scripts/plymouth.sh)" \
        bash -c '[ "$(plymouth-set-default-theme 2>/dev/null)" = soviet ]'
fi

if selected limine; then
    # The wallpaper goes to the partition ROOT (limine.sh steps out of a limine/
    # subdirectory, because theme.conf names it boot():/limine-wallpaper.png), so
    # the check has to look there too - next to the conf, a correct install on the
    # /boot/limine/ or /efi/limine/ layout failed here and blocked the reboot.
    check_outcome "limine.conf has no theme block / wallpaper missing (install-scripts/limine.sh)" \
        bash -c 'for c in /boot/limine.conf /efi/limine.conf /boot/efi/limine.conf /boot/limine/limine.conf /efi/limine/limine.conf; do sudo test -f "$c" || continue; sudo grep -q "my_archinstaller Limine theme" "$c" || continue; d=$(dirname "$c"); [ "$(basename "$d")" = limine ] && d=$(dirname "$d"); sudo test -f "$d/limine-wallpaper.png" && exit 0; done; exit 1'
fi

# Packages that failed their SOURCE CHECKSUM rather than their build.
#
# Reported apart from the list above because the cause and the fix are
# different: not a missing dependency or a compiler error, but a source archive
# whose bytes no longer match what the AUR PKGBUILD pins - almost always an
# upstream forge regenerating a release tarball. Telling you that here saves
# digging it out of a 40MB install log, and the command to finish the job is
# one line. Re-verified like the others, so a package that was pulled in later
# as somebody's dependency is not reported as outstanding.
checksum_failed=()
if [ -f "$CHECKSUM_FAILURES_MANIFEST" ]; then
    while read -r pkg; do
        [ -n "$pkg" ] || continue
        is_installed_pacman "$pkg" && continue
        already="no"
        for seen in "${checksum_failed[@]}"; do
            [ "$seen" == "$pkg" ] && already="yes" && break
        done
        [ "$already" == "yes" ] && continue
        checksum_failed+=("$pkg")
    done < "$CHECKSUM_FAILURES_MANIFEST"
fi

# Log missing packages
# checksum_failed is in this condition on purpose. In a normal run a package
# that failed its checksum is recorded in BOTH manifests, so `missing` already
# covers it - but the two are written by different code paths, and if one ever
# records without the other, leaving it out here would report a clean install
# and exit 0, which is what lets a preset run reboot. Cheap insurance.
if [ ${#missing[@]} -eq 0 ] && [ ${#local_missing[@]} -eq 0 ] && [ ${#outcome_failures[@]} -eq 0 ] \
   && [ ${#checksum_failed[@]} -eq 0 ]; then
    echo "${OK} GREAT! All ${YELLOW}essential packages${RESET} are installed and every selected component checked out." | tee -a "$LOG"
    exit 0
fi

if [ ${#outcome_failures[@]} -ne 0 ]; then
    echo "${WARN} The following components did NOT land as expected:"
    for f in "${outcome_failures[@]}"; do
        echo "  ${WARNING}$f${RESET}"
        echo "OUTCOME: $f" >> "$LOG"
    done
fi

if [ ${#missing[@]} -ne 0 ]; then
    echo "${WARN} The following packages are NOT installed and will be logged:"
    for pkg in "${missing[@]}"; do
        echo "${WARNING}$pkg${RESET}"
        echo "$pkg" >> "$LOG"
    done
fi

if [ ${#local_missing[@]} -ne 0 ]; then
    echo "${WARN} The following local packages are missing from /usr/local/bin/ and will be logged:"
    for pkg1 in "${local_missing[@]}"; do
        echo "${WARNING}$pkg1${RESET} is not installed. Can't find it in /usr/local/bin/"
        echo "$pkg1" >> "$LOG"
    done
fi

if [ ${#checksum_failed[@]} -ne 0 ]; then
    echo
    echo "${WARN} These failed their ${WARNING}source checksum${RESET}, not their build:"
    for pkg in "${checksum_failed[@]}"; do
        echo "  ${WARNING}$pkg${RESET}"
        echo "CHECKSUM: $pkg" >> "$LOG"
    done
    echo "${NOTE} The downloaded source did not match what the AUR PKGBUILD pins. That is"
    echo "${NOTE} usually an upstream tarball that was regenerated - same code, different"
    echo "${NOTE} archive bytes - but it is also what a tampered source looks like, so check"
    echo "${NOTE} before overriding it. The repo README has the procedure under"
    echo "${NOTE} \"Validating source files with sha256sums... FAILED\"."
    echo "${NOTE} Once you are satisfied, build it with:"
    for pkg in "${checksum_failed[@]}"; do
        echo "   ${MAGENTA}$(basename "${ISAUR:-yay}") -S $pkg --mflags --skipchecksums${RESET}"
    done
    echo "${NOTE} To let future runs do that unattended, add the name to"
    echo "${NOTE} ${MAGENTA}install-scripts/checksum-skip.conf${RESET}."
fi

echo "${NOTE} Missing packages logged at $(date)" >> "$LOG"

printf "\n%s Full list also in %s\n" "${NOTE}" "$LOG"

# Non-zero so install.sh knows not to reboot out from under an incomplete
# install. Before this, the warning above scrolled past and a preset run
# rebooted 15 seconds later regardless.
exit 1
