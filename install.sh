#!/bin/bash

clear

# Set some colors for output messages
OK="$(tput setaf 2)[OK]$(tput sgr0)"
ERROR="$(tput setaf 1)[ERROR]$(tput sgr0)"
NOTE="$(tput setaf 3)[NOTE]$(tput sgr0)"
INFO="$(tput setaf 4)[INFO]$(tput sgr0)"
WARN="$(tput setaf 1)[WARN]$(tput sgr0)"
CAT="$(tput setaf 6)[ACTION]$(tput sgr0)"
MAGENTA="$(tput setaf 5)"
ORANGE="$(tput setaf 214)"
WARNING="$(tput setaf 1)"
YELLOW="$(tput setaf 3)"
GREEN="$(tput setaf 2)"
BLUE="$(tput setaf 4)"
SKY_BLUE="$(tput setaf 6)"
RESET="$(tput sgr0)"

# Check if running as root. If root, script will exit.
#
# Before anything touches the filesystem: this used to come after the
# Install-Logs mkdir, so a stray `sudo ./install.sh` created a root-owned
# Install-Logs/ and log file, exited here, and the next (correct) run as the
# user died with "permission denied" truncating the failed-package manifest.
if [[ $EUID -eq 0 ]]; then
    echo "${ERROR}  This script should ${WARNING}NOT${RESET} be executed as root!! Run it as your user: ./install.sh ... - it calls sudo itself. Exiting......."
    printf "\n%.0s" {1..2} 
    exit 1
fi

# Everything below is relative to the repo root (Install-Logs/, install-scripts/,
# Hyprland-Dots/), so run from there wherever the script was invoked from. A
# relative --preset path is resolved first, against the caller's directory.
#
# A --preset with no file, or one readlink cannot resolve (its folder does not
# exist), used to fall through to an INTERACTIVE run: readlink printed nothing,
# $2 became empty, and the -n "$2" test below skipped load_preset - and with it
# the "Preset file not found" exit. A preset that cannot be found is an error.
if [[ "${1:-}" == "--preset" ]]; then
    if [ -z "${2:-}" ]; then
        echo "${ERROR} --preset needs a file: ./install.sh --preset custom-preset.conf"
        exit 1
    fi
    if [ "${2:0:1}" != "/" ]; then
        if ! _preset_abs=$(readlink -f "$2") || [ -z "$_preset_abs" ]; then
            echo "${ERROR} Preset file not found: $2"
            exit 1
        fi
        set -- "$1" "$_preset_abs"
    fi
    # readlink -f also resolves a file that does not exist in a folder that
    # does, so a typo (custom-preset.cof) passed here and was only reported by
    # load_preset - after the sudo prompt and the base installs, sometimes a
    # full -Syu.
    if [ ! -f "$2" ]; then
        echo "${ERROR} Preset file not found: $2"
        exit 1
    fi
fi
# Resolved once, before the cd: "$0" is relative to the caller's directory, and
# resolving it again after the cd gave the wrong folder whenever this was started
# as ../install.sh (from Install-Logs/ or install-scripts/, where the README sends
# you after a failed run). nvidia_detect.sh was then not found and nvidia="auto"
# quietly resolved to no NVIDIA at all.
SCRIPT_PATH=$(readlink -f "$0")
cd "$(dirname "$SCRIPT_PATH")" || { echo "${ERROR} Cannot cd to the repo directory"; exit 1; }

# A re-run from this setup's zsh inherits .zshrc's CARGO_TARGET_DIR (one shared
# cargo cache for development). makepkg hands it on to cargo, so an AUR Rust
# build whose PKGBUILD does not set its own target dir would look for
# target/release/<bin> in package() and fail.
unset CARGO_TARGET_DIR

# Create Directory for Install Logs
if [ ! -d Install-Logs ]; then
    mkdir Install-Logs
fi

# Set the name of the log file to include the current date and time
LOG="Install-Logs/01-Hyprland-Install-Scripts-$(date +%Y%m%d-%H%M%S).log"

# Authenticate sudo once, first thing, and keep the timestamp alive for the whole
# run. This used to happen halfway down, after hardware detection - but the
# base-devel, libnewt and pciutils installs below it already call sudo, so on a
# fresh Arch box the first password prompt came from one of those, with no
# message saying why, and the "once" happened somewhere else. Everything after
# this point, including the ESP-only Limine detection, reuses this one prompt.
echo "${INFO} Authenticating ${SKY_BLUE}sudo${RESET} once for the whole run..." | tee -a "$LOG"
# `sudo -n true` first. `sudo -v` asks for a password unless EVERY sudoers rule
# that matches the user is NOPASSWD (verifypw=all), and archinstall, Calamares
# and the README's prerequisite all leave a password rule next to this
# installer's wheel NOPASSWD one - so even a re-run asked, and a run with no
# terminal (`ssh host ./install.sh` without -t) died here, blaming sudo
# membership. Running a command uses the last matching rule instead.
if ! sudo -n true 2>/dev/null && ! sudo -v; then
    if [ -t 0 ]; then
        echo "${ERROR} sudo did not accept your password, or $USER is not allowed to sudo. See README: Prerequisites." | tee -a "$LOG"
    else
        echo "${ERROR} sudo needs a password here and there is no terminal to ask on. Run it from a terminal (ssh -t) once; after that the passwordless rule lets it run without one." | tee -a "$LOG"
    fi
    exit 1
fi
# Off the script's output: the EXIT trap below ends the loop, but not the
# `sleep 60` it is in, and that orphan kept `./install.sh ... | tee log` from
# returning for up to a minute after every stop that was not a reboot.
( while true; do sudo -n true 2>/dev/null; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) >/dev/null 2>&1 &
sudo_keepalive_pid=$!

# No suspend while it runs. logind suspends on lid close by default
# (HandleLidSwitch=suspend, on a bare TTY too), so closing a laptop's lid on the
# hour-long unattended run stopped it mid-download, and it came back with
# timed-out installs. The lock belongs to a root loop that ends within seconds
# of this script, however it exits; the trap ends it at once. Through sudo, so
# it is granted from SSH as well.
sudo -n systemd-inhibit --what=sleep:idle:handle-lid-switch --who=my_archinstaller --why="Installing" --mode=block \
    sh -c "while kill -0 $$ 2>/dev/null; do sleep 5; done" >/dev/null 2>&1 &
inhibit_pid=$!
trap 'kill "$sudo_keepalive_pid" "$inhibit_pid" 2>/dev/null' EXIT

# Install a package before pacman.sh's full upgrade has run.
#
# base-devel, libnewt and pciutils/usbutils are needed before the menus and the
# hardware detection, i.e. before the first `pacman -Syu`. A plain `pacman -S`
# there resolves against the package database from the day the OS was
# installed, so on a machine that sat for a week the mirrors no longer carry
# those versions: 404s, and the installer exited with "base-devel not found nor
# cannot be installed" - with an unsynced database as the real cause. Try the
# cheap way first; on failure refresh the keyring(s) and upgrade the system
# (the same full upgrade pacman.sh would do moments later), then retry.
early_install() {
    sudo pacman -S --needed --noconfirm "$@" && return 0
    echo "${NOTE} Install failed - syncing the package databases and upgrading first, then retrying..." | tee -a "$LOG"
    local _keyrings=(archlinux-keyring)
    pacman -Q cachyos-keyring &>/dev/null && _keyrings+=(cachyos-keyring)
    sudo pacman -Sy --needed --noconfirm "${_keyrings[@]}" \
        && sudo pacman -Su --noconfirm \
        && sudo pacman -S --needed --noconfirm "$@"
}

# PulseAudio -> PipeWire.
#
# pipewire.sh installs pipewire-pulse, which conflicts with pulseaudio, and under
# --noconfirm pacman answers "Remove pulseaudio?" with its default, no. So this
# used to stop the run right here, and archinstall's "Audio: PulseAudio" choice
# was all it took; the advice it printed (comment out pipewire.sh) could not
# help, because this check ran whatever was commented out. Swap it here instead.
# First the modules that need pulseaudio itself (pulseaudio-bluetooth and the
# like: the pulseaudio-* names in its "Required By"), with pulseaudio, and without
# dependency checks - desktop packages that only need *a* pulse server
# (pulse-native-provider) are satisfied again a moment later by pipewire-pulse.
# That goes in right away, so nothing installed below can pick PulseAudio as the
# provider again. A preset run does this unattended; an interactive run asks.
if pacman -Qq pulseaudio &>/dev/null; then
    _pa_pkgs=(pulseaudio)
    for _p in $(pacman -Qi pulseaudio | sed -n 's/^Required By *: //p'); do
        case "$_p" in pulseaudio-*) _pa_pkgs+=("$_p") ;; esac
    done
    echo "${NOTE} PulseAudio is installed, and this setup uses PipeWire: replacing ${_pa_pkgs[*]} with pipewire-pulse." | tee -a "$LOG"
    if [[ "${1:-}" != "--preset" ]]; then
        read -r -p "Replace PulseAudio with PipeWire now? [y/N] " _pa_answer
        if [[ "$_pa_answer" != [yY]* ]]; then
            echo "${ERROR} This setup needs PipeWire. Uninstall PulseAudio, or answer y, and run it again." | tee -a "$LOG"
            exit 1
        fi
    fi
    systemctl --user disable --now pulseaudio.socket pulseaudio.service >> "$LOG" 2>&1 || true
    if sudo pacman -Rdd --noconfirm "${_pa_pkgs[@]}" >> "$LOG" 2>&1 && early_install pipewire-pulse >> "$LOG" 2>&1; then
        echo "${OK} PulseAudio replaced by PipeWire." | tee -a "$LOG"
    else
        echo "${ERROR} Could not replace PulseAudio with PipeWire - see $LOG" | tee -a "$LOG"
        exit 1
    fi
fi

# Check if base-devel is installed
if pacman -Q base-devel &> /dev/null; then
    echo "base-devel is already installed."
else
    echo "$NOTE Install base-devel.........."

    if early_install base-devel; then
        echo "👌 ${OK} base-devel has been installed successfully." | tee -a "$LOG"
    else
        echo "❌ $ERROR base-devel not found nor cannot be installed."  | tee -a "$LOG"
        echo "$CAT Please install base-devel manually before running this script... Exiting" | tee -a "$LOG"
        exit 1
    fi
fi

# install whiptails if detected not installed. Necessary for this version
if ! command -v whiptail >/dev/null; then
    echo "${NOTE} - whiptail is not installed. Installing..." | tee -a "$LOG"
    early_install libnewt
    printf "\n%.0s" {1..1}
fi

## Default values for the options (will be overwritten by preset file if available)
gtk_themes="OFF"
bluetooth="auto"
thunar="OFF"
quickshell="OFF"
# No sddm/sddm_theme keys here any more. They were defaults for options that
# have no menu entry, no preset-loop entry, no case branch and no install
# script - setting sddm="ON" in a preset did precisely nothing, silently. The
# unknown-key warning in load_preset() now reports that instead of hiding it.
xdph="OFF"
zsh="OFF"
pokemon="OFF"
# "auto" on the hardware-gated options, not "OFF".
#
# A preset is carried between machines, which makes it exactly the wrong place
# to record what hardware a machine has. This preset was written on a box with
# Intel graphics, so it used to say nvidia="OFF"; run that unchanged on an
# NVIDIA machine and nvidia.sh simply never executed - no driver, no prompt, and
# 02-Final-Check.sh cannot flag it because nothing was ever attempted.
#
# So these three follow detection unless the preset overrides them. "ON" and
# "OFF" still mean force-on and force-off, for the cases where you genuinely
# want to decide (keeping nouveau, or skipping the proprietary driver).
rog="auto"
dots="OFF"
input_group="OFF"
nvidia="auto"
nouveau="auto"
handy="OFF"
ly="OFF"
nopasswd_sudo="OFF"
printing="OFF"
# Docker, with socket activation. "ON" because the call site below used to be
# unconditional, so this is what every install has been doing already - the
# difference is that it is now a choice you can see and switch off.
#
# Worth knowing what it grants: docker.sh adds you to the "docker" group, and
# that group can talk to a root-owned daemon socket, so a member can start a
# container that mounts / and become root without a password or a sudo log
# entry. On a box where wheel already has NOPASSWD that changes nothing. On one
# where it does not, this is a second, quieter path to root - set docker="OFF"
# there.
docker="ON"
# "auto": only where plymouth is already installed and hooked into the initramfs.
plymouth="auto"
# Takes `quiet` and `splash` off the kernel command line, so the boot shows the
# kernel and systemd messages. Skipped when plymouth is selected too.
text_boot="OFF"
# "auto": only where a limine.conf exists (Limine is the bootloader).
limine="auto"

# Every option name the installer acts on. Kept next to load_preset() because
# its only job is to catch a preset key that no longer matches one - see below.
known_options="ly nvidia nouveau input_group gtk_themes bluetooth thunar \
quickshell xdph zsh pokemon rog dots handy nopasswd_sudo printing plymouth \
text_boot limine docker herdr neovim hunk"
# The ones that also take "auto" (resolved from the hardware further down).
auto_options="nvidia nouveau rog bluetooth plymouth limine"

# Function to load preset file
load_preset() {
    if [ -f "$1" ]; then
        echo "✅ Loading preset: $1"
        # Without its CRs: a preset saved with Windows line endings made every
        # blank line a command named $'\r' ("command not found").
        source <(tr -d '\r' < "$1")

        # Collect any key the preset sets that this installer does not use.
        #
        # A preset is just a sourced shell file, so a retired option (sddm), a
        # renamed one, or a plain typo (quickshel="ON") assigns a variable
        # nobody ever reads and the installer carries on as if the line were not
        # there. That is indistinguishable from the option being off, which is
        # the worst way for a preset to fail: you get a machine missing a
        # component you explicitly asked for, and nothing anywhere says so.
        #
        # Collected, not printed here: there is a `clear` between this function
        # and the first thing anyone actually reads, so a warning printed at
        # this point is wiped off the screen a second later. Reported below the
        # banner instead, and into the log.
        while IFS= read -r _key; do
            [ -n "$_key" ] || continue
            [[ " $known_options " == *" $_key "* ]] && continue
            preset_unknown_keys+=("$_key")
        # No [[:space:]] before the '=': a shell assignment cannot have one, so
        # `docker = "OFF"` is not setting docker at all (it tries to *run*
        # docker) and must not be counted as though it had.
        done < <(grep -oE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=' "$1" | tr -d '[:blank:]=')

        # The values, normalised and checked. Only the exact strings ON and auto
        # ever meant anything: nvidia="Auto", dots="on", thunar="yes", ly="ON "
        # (a trailing space) or a CRLF line ending from a Windows editor all read
        # as OFF without a word - the NVIDIA driver included. Case, spaces and
        # the CR are dropped now and yes/no spellings accepted; anything else
        # stops the run here, before it has done anything.
        local _opt _v _bad=()
        for _opt in $known_options; do
            [ -n "${!_opt+x}" ] || continue
            _v=$(printf '%s' "${!_opt}" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            case "${_v,,}" in
                on|yes|true|1)  _v=ON ;;
                off|no|false|0) _v=OFF ;;
                auto)
                    if [[ " $auto_options " == *" $_opt "* ]]; then
                        _v=auto
                    else
                        _bad+=("$_opt=\"${!_opt}\" - auto only works for: $auto_options")
                        continue
                    fi
                    ;;
                *)  _bad+=("$_opt=\"${!_opt}\" - use ON or OFF"); continue ;;
            esac
            printf -v "$_opt" '%s' "$_v"
        done
        if [ ${#_bad[@]} -gt 0 ]; then
            echo "❌ $1 has values this installer does not understand:"
            printf '   %s\n' "${_bad[@]}"
            exit 1
        fi
    else
        # Do not fall through to the defaults here: they are all "OFF", so a
        # mistyped preset path would run a fully non-interactive install that
        # installs nothing and looks like it succeeded.
        echo "❌ Preset file not found: $1"
        exit 1
    fi
}

# Check if --preset argument is passed
preset_mode="false"
preset_unknown_keys=()
if [[ "$1" == "--preset" && -n "$2" ]]; then
    load_preset "$2"
    preset_mode="true"
fi

clear

printf "\n%.0s" {1..2}  
echo -e "\e[35m
	╦╔═┌─┐┌─┐╦    ╦ ╦┬ ┬┌─┐┬─┐┬  ┌─┐┌┐┌┌┬┐
	╠╩╗│ ││ │║    ╠═╣└┬┘├─┘├┬┘│  ├─┤│││ ││ 2025
	╩ ╩└─┘└─┘╩═╝  ╩ ╩ ┴ ┴  ┴└─┴─┘┴ ┴┘└┘─┴┘ Arch Linux
\e[0m"
printf "\n%.0s" {1..1} 

# Preset keys this installer does not act on. Printed here rather than in
# load_preset() because the `clear` above would have eaten them.
if [ ${#preset_unknown_keys[@]} -ne 0 ]; then
    for _key in "${preset_unknown_keys[@]}"; do
        echo "${WARN} Preset sets ${YELLOW}${_key}${RESET}, which this installer does not use - ignored." | tee -a "$LOG"
    done
    echo "${NOTE} Retired or mistyped key? Valid options: ${SKY_BLUE}${known_options}${RESET}" | tee -a "$LOG"
    printf "\n%.0s" {1..1}
fi

# The point of --preset is "git clone and hit install", so a preset run shows no
# dialogs at all: not this welcome box, not the confirmation, not the AUR-helper
# picker below, and not the component menu further down. Without a preset the
# interactive path is unchanged.
if [ "$preset_mode" != "true" ]; then
    # Welcome message using whiptail (for displaying information)
    whiptail --title "Hyprland Install Script" \
        --msgbox "Welcome to the Hyprland install script!\n\n\
ATTENTION: Run a full system update and Reboot first !!! (Highly Recommended)\n\n\
NOTE: If you are installing on a VM, ensure to enable 3D acceleration else Hyprland may NOT start!" \
        15 80

    # Ask if the user wants to proceed
    if ! whiptail --title "Proceed with Installation?" \
        --yesno "Would you like to proceed?" 7 50; then
        echo -e "\n"
        echo "❌ ${INFO} You 🫵 chose ${YELLOW}NOT${RESET} to proceed. ${YELLOW}Exiting...${RESET}" | tee -a "$LOG"
        echo -e "\n" 
        exit 1
    fi
fi

echo "👌 ${OK} ${SKY_BLUE}Continuing with the installation...${RESET}" | tee -a "$LOG"

sleep 1
printf "\n%.0s" {1..1}

# install pciutils if detected not installed. Necessary for detecting GPU.
# usbutils too: the Bluetooth detection below falls back to lsusb, and a fresh
# base system does not ship it - so that fallback was silently a no-op.
for _tool in pciutils usbutils; do
    if ! pacman -Qq "$_tool" &> /dev/null; then
        echo "${NOTE} - $_tool is not installed. Installing..." | tee -a "$LOG"
        early_install "$_tool"
        printf "\n%.0s" {1..1}
    fi
done

# Path to the install-scripts directory
script_directory=install-scripts

# Function to execute a script if it exists and make it executable
execute_script() {
    local script="$1"
    local script_path="$script_directory/$script"
    if [ -f "$script_path" ]; then
        chmod +x "$script_path"
        if [ -x "$script_path" ]; then
            env "$script_path"
        else
            echo "Failed to make script '$script' executable."
            return 1
        fi
    else
        echo "Script '$script' not found in '$script_directory'."
        return 1
    fi
}


# Check if yay or paru is installed - and actually starts. `command -v` alone
# took a helper that is on PATH but broken (linked against a libalpm soname
# pacman no longer ships) as installed, so nothing rebuilt it, and every re-run
# ended at "No working AUR helper ... read the build error above" with no build
# having run at all.
aur_helper_works() {
    local _h
    for _h in yay paru; do
        if command -v "$_h" &>/dev/null && "$_h" --version &>/dev/null; then
            return 0
        fi
    done
    return 1
}
echo "${INFO} - Checking if yay or paru is installed"
if ! aur_helper_works; then
    if [ "$preset_mode" == "true" ]; then
        # A preset run must not stop to ask. yay is the default because yay.sh
        # builds it from the yay-bin/ PKGBUILD that is vendored in this repo, so
        # it works even before any AUR helper exists on the machine - which is
        # exactly the fresh-install case this branch handles.
        aur_helper="yay"
        echo "${NOTE} - No AUR helper found. Preset mode: installing ${SKY_BLUE}yay${RESET} automatically." | tee -a "$LOG"
    else
    echo "${CAT} - Neither yay nor paru found. Asking 🗣️ USER to select..."
    while true; do
        aur_helper=$(whiptail --title "No working AUR helper" --checklist "Neither yay nor paru is installed (or it no longer starts). Choose one AUR helper.\n\nNOTE: Select only 1 AUR helper!\nINFO: spacebar to select" 12 60 2 \
            "yay" "AUR Helper yay" "OFF" \
            "paru" "AUR Helper paru" "OFF" \
            3>&1 1>&2 2>&3)

        if [ $? -ne 0 ]; then  
            echo "❌ ${INFO} You cancelled the selection. ${YELLOW}Goodbye!${RESET}" | tee -a "$LOG"
            exit 0 
        fi

        if [ -z "$aur_helper" ]; then
            whiptail --title "Error" --msgbox "You must select at least one AUR helper to proceed." 10 60 2
            continue 
        fi

        echo "${INFO} - You selected: $aur_helper as your AUR helper"  | tee -a "$LOG"

        aur_helper=$(echo "$aur_helper" | tr -d '"')

        # Check if multiple helpers were selected
        if [[ $(echo "$aur_helper" | wc -w) -ne 1 ]]; then
            whiptail --title "Error" --msgbox "You must select exactly one AUR helper." 10 60 2
            continue  
        else
            break 
        fi
    done
    fi
else
    echo "${NOTE} - AUR helper is already installed. Skipping AUR helper selection."
fi

# List of services to check for active login managers
# greetd, lemurs, plasmalogin and cosmic-greeter too: with only the classic five
# listed, a machine already running greetd got ly enabled next to it and booted
# into greetd anyway. Keep in step with the disable list in install-scripts/ly.sh.
services=("gdm.service" "gdm3.service" "lightdm.service" "lxdm.service" "sddm.service"
          "greetd.service" "lemurs.service" "plasmalogin.service" "cosmic-greeter.service")

# Function to check if any login services are active
check_services_running() {
    active_services=()  # Array to store active services
    for svc in "${services[@]}"; do
        if systemctl is-active --quiet "$svc"; then
            active_services+=("$svc")  
        fi
    done

    if [ ${#active_services[@]} -gt 0 ]; then
        return 0  
    else
        return 1  
    fi
}

if check_services_running; then
    active_list=$(printf "%s\n" "${active_services[@]}")

    if [ "$preset_mode" == "true" ]; then
        # Same information, but printed instead of shown in a box that has to be
        # dismissed. The preset loop below skips ly on its own in this case.
        echo "${WARN} Active login manager(s) detected: ${active_services[*]}" | tee -a "$LOG"
        echo "${NOTE} ly will be skipped. Disable them and re-run if you want ly." | tee -a "$LOG"
    else
        # Display the active login manager(s) in the whiptail message box
        whiptail --title "Active login manager(s) detected" \
            --msgbox "The following login manager(s) are active:\n\n$active_list\n\nIf you want to install ly display manager, stop and disable the active services above, reboot before running this script\n\nYour option to install ly has now been removed\n\n- Ja " 23 80
    fi
fi

# Check if NVIDIA GPU is detected, and which driver branch can drive it.
#
# Not `lspci | grep -i nvidia`: that also matched the GPU's HDMI audio function
# and nForce chipsets, and said nothing about the generation - so every NVIDIA
# card got nvidia-open-dkms, which only binds to Turing and newer. A GTX 1060
# rebooted with that module unloaded AND nouveau blacklisted: no driver at all.
# nvidia_detect.sh prints none / open / 580xx / unsupported.
nvidia_tier=$("$(dirname "$SCRIPT_PATH")/install-scripts/nvidia_detect.sh" 2>/dev/null || echo none)
nvidia_detected=false
nvidia_supported=false
case "$nvidia_tier" in
    open)  _nv_driver="nvidia-open-dkms" ;;
    580xx) _nv_driver="nvidia-580xx-dkms (legacy branch, AUR)" ;;
    *)     _nv_driver="" ;;
esac
if [ "$nvidia_tier" != "none" ]; then
    nvidia_detected=true
    [ -n "$_nv_driver" ] && nvidia_supported=true
    if [ "$nvidia_supported" != "true" ]; then
        # Kepler or older. "auto" leaves it alone below, so nouveau keeps working.
        echo "${WARN} NVIDIA GPU detected, but it is Kepler or older: no maintained proprietary driver supports it. Keeping nouveau." | tee -a "$LOG"
    elif [ "$preset_mode" == "true" ]; then
        echo "${NOTE} NVIDIA GPU detected (driver: ${_nv_driver}). It is configured unless the preset sets nvidia=\"OFF\"." | tee -a "$LOG"
    else
        whiptail --title "NVIDIA GPU Detected" --msgbox "NVIDIA GPU detected in your system.\n\nNOTE: The script will install ${_nv_driver}, the matching nvidia-utils and nvidia-settings if you chose to configure." 12 70
    fi
fi

# An ASUS hybrid laptop left in Eco mode by its previous OS keeps the dGPU
# powered off - dgpu_disable=1 lives in firmware and survives a reinstall - so
# the card is not on the PCI bus and nvidia_detect.sh above says "none".
# nvidia="auto" then resolves to OFF and even a forced nvidia="ON" is skipped:
# after switching to Hybrid later, the NVIDIA GPU came up with no proprietary
# driver, and nothing in the run had said so.
#
# Said, not fixed: dgpu_disable is not written from here. Switching the GPU
# mode is asusd's job (asusctl 6.x; the value is written at shutdown) and takes
# a reboot to settle, so the driver is a step for afterwards, and the warning is
# repeated at the end of the run.
asus_dgpu_off=false
if [ "$nvidia_detected" != "true" ] \
   && [ "$(cat /sys/devices/platform/asus-nb-wmi/dgpu_disable 2>/dev/null)" = "1" ]; then
    asus_dgpu_off=true
    echo "${WARN} ASUS dGPU is switched OFF (Eco mode, dgpu_disable=1). If it is an NVIDIA GPU, it is invisible to this run: its driver cannot be detected or installed." | tee -a "$LOG"
    echo "${NOTE} To get the NVIDIA driver: switch to Hybrid (ROG Control Center -> GPU Configuration, or ${MAGENTA}asusctl armoury set dgpu_disable 0${RESET}), reboot, then run ${MAGENTA}install-scripts/nvidia.sh${RESET}." | tee -a "$LOG"
    if [ "$preset_mode" != "true" ]; then
        whiptail --title "ASUS dGPU is switched off" --msgbox "This ASUS laptop's discrete GPU is switched off (Eco mode, dgpu_disable=1), so it is not visible and no NVIDIA driver can be detected or installed now.\n\nTo get it afterwards: switch to Hybrid (ROG Control Center -> GPU Configuration, or asusctl armoury set dgpu_disable 0), reboot, then run install-scripts/nvidia.sh." 14 78
    fi
fi

# Check if this is an ASUS LAPTOP (asusctl targets ROG laptops: fan curves,
# keyboard backlight, hybrid-GPU switching). DMI is the same question
# rog="ON" was asking the user to answer by hand.
#
# Vendor alone is not enough: a desktop built on an ASUS motherboard reports
# sys_vendor "ASUS" too, and got asusctl for laptop controls it does not
# have. So it must also look like a laptop - a battery in
# /sys/class/power_supply, or a portable DMI chassis type (8-11 and 14), the
# same test configs/Vars.lua uses to skip the laptop keybinds.
is_laptop=false
if ls -d /sys/class/power_supply/BAT* >/dev/null 2>&1; then
    is_laptop=true
else
    case "$(cat /sys/class/dmi/id/chassis_type 2>/dev/null)" in
        8|9|10|11|14) is_laptop=true ;;
    esac
fi
rog_detected=false
if grep -qi 'asus' /sys/class/dmi/id/sys_vendor 2>/dev/null; then
    if [ "$is_laptop" == "true" ]; then
        rog_detected=true
        echo "${NOTE} ASUS laptop detected (${SKY_BLUE}$(cat /sys/class/dmi/id/sys_vendor)${RESET})." | tee -a "$LOG"
    else
        echo "${NOTE} ASUS motherboard, but not a laptop: skipping the ROG laptop tools." | tee -a "$LOG"
    fi
fi

# Check for a Bluetooth controller. The kernel creates /sys/class/bluetooth/hci*
# as soon as a driver binds one, with no help from bluez, so this is answerable
# before anything is installed.
#
# rfkill is the second test, not lsusb. A radio that is soft-blocked (the bar's
# own toggle blocks it, and systemd-rfkill restores that state at boot; on
# ThinkPads the block also cuts power to the USB controller) has no hci*
# directory and does not even show up in lsusb - but rfkill still lists the
# switch. Without this test the T480 this preset was written on resolved
# bluetooth="auto" to OFF whenever its radio happened to be off at install
# time. rfkill is util-linux, so it is always present; lspci/lsusb stay as the
# last resort for a controller whose driver has not loaded yet.
bluetooth_detected=false
if ls -d /sys/class/bluetooth/hci* >/dev/null 2>&1; then
    bluetooth_detected=true
elif rfkill -n -o TYPE list bluetooth 2>/dev/null | grep -q bluetooth; then
    bluetooth_detected=true
elif lsusb 2>/dev/null | grep -qi bluetooth || lspci 2>/dev/null | grep -qi bluetooth; then
    bluetooth_detected=true
fi
if [ "$bluetooth_detected" == "true" ]; then
    echo "${NOTE} Bluetooth controller detected." | tee -a "$LOG"
fi

# Plymouth counts as "present" only when the distro also hooked it into the
# initramfs - CachyOS does; a plain archinstall has neither. The theme alone is
# harmless, but "auto" should not pull plymouth onto a machine that never asked.
plymouth_detected=false
# mkinitcpio_has_hook (Global_functions.sh), which reads the config exactly the
# way mkinitcpio does - a multi-line HOOKS array, HOOKS+=(plymouth) in a
# drop-in and the drop-ins' real order all count. In a child shell, because
# Global_functions.sh sets -e (see the Limine detection below).
_hooks_have_plymouth=false
if bash -c 'source "$1" && mkinitcpio_has_hook plymouth' _ "$script_directory/Global_functions.sh" 2>/dev/null; then
    _hooks_have_plymouth=true
fi
if pacman -Qi plymouth &>/dev/null && [ "$_hooks_have_plymouth" == "true" ]; then
    plymouth_detected=true
    echo "${NOTE} Plymouth is installed and in the initramfs HOOKS." | tee -a "$LOG"
fi

# Limine: the theme edits its config, so only offer it where that config exists.
#
# The search is find_limine_conf in Global_functions.sh, the one limine.sh and
# the final check use too, so the three cannot disagree about where the file is
# (this used to be a third copy of a path list that missed archinstall's
# <ESP>/EFI/arch-limine/limine.conf). Sourced in a child shell, just for this
# call, because Global_functions.sh sets -e - see the plymouth block above.
limine_detected=false
_limine_conf=$(bash -c 'source "$1" && find_limine_conf' _ "$script_directory/Global_functions.sh" 2>/dev/null)
if [ -n "$_limine_conf" ]; then
    limine_detected=true
    echo "${NOTE} Limine bootloader detected (${_limine_conf})." | tee -a "$LOG"
fi

# Resolve "auto" into ON/OFF from what was just detected. Only the preset loop
# reads these - the interactive checklist below ships its own defaults - so an
# interactive run is unaffected.
for _hw in $auto_options; do
    [ "${!_hw}" == "auto" ] || continue
    case "$_hw" in
        # A GPU no maintained driver supports stays on nouveau under "auto".
        nvidia)         _want="$nvidia_supported" ;;
        # nouveau follows the *decision* on nvidia, not the detection. It used to
        # follow nvidia_detected, so nvidia="OFF" plus nouveau="auto" on an NVIDIA
        # machine blacklisted nouveau without installing the proprietary driver -
        # no GPU driver at all. nvidia is resolved earlier in this loop, so it is
        # already ON/OFF here. It also needs a card the driver supports: a
        # forced nvidia="ON" on a Kepler card is skipped below, and blacklisting
        # nouveau there would leave no driver at all.
        nouveau)        if [ "$nvidia" == "ON" ] && [ "$nvidia_supported" == "true" ]; then _want=true; else _want=false; fi ;;
        rog)            _want="$rog_detected" ;;
        bluetooth)      _want="$bluetooth_detected" ;;
        plymouth)       _want="$plymouth_detected" ;;
        limine)         _want="$limine_detected" ;;
    esac
    if [ "$_want" == "true" ]; then
        printf -v "$_hw" "ON"
        # Preset runs only: the interactive checklist ignores these values, so
        # there it logged "enabling bluetooth" for a box left unticked.
        if [ "$preset_mode" == "true" ]; then
            echo "${NOTE} auto: enabling ${SKY_BLUE}$_hw${RESET} (hardware detected)." | tee -a "$LOG"
        fi
    else
        printf -v "$_hw" "OFF"
    fi
done

# Initialize the options array for whiptail checklist
options_command=(
    whiptail --title "Select Options" --checklist "Choose options to install or configure\nNOTE: 'SPACEBAR' to select & 'TAB' key to change selection" 28 85 20
)

# Add NVIDIA options if a card the driver supports is there. Detected is not
# enough: a Kepler-or-older card is detected but no maintained driver binds to
# it, and ticking "nvidia" there ran nvidia.sh into a failure the final check
# then blamed on a missing driver no script can install. The preset path gates
# the same way.
if [ "$nvidia_supported" == "true" ]; then
    options_command+=(
        "nvidia" "Do you want script to configure NVIDIA GPU?" "OFF"
        "nouveau" "Do you want Nouveau to be blacklisted?" "OFF"
    )
fi

# Add 'input_group' option if user is not in input group
input_group_detected=false
if ! groups "$(whoami)" | grep -q '\binput\b'; then
    input_group_detected=true
    if [ "$preset_mode" == "true" ]; then
        echo "${NOTE} You are not in the 'input' group. Added only if the preset sets input_group=\"ON\"." | tee -a "$LOG"
    else
        whiptail --title "Input Group" --msgbox "You are not currently in the input group.\n\nAdding you to the input group might be necessary for the Waybar keyboard-state functionality." 12 60
    fi
fi

# Add 'input_group' option if necessary
if [ "$input_group_detected" == "true" ]; then
    options_command+=(
        "input_group" "Add your USER to input group for some waybar functionality?" "OFF"
    )
fi

# Conditionally add ly display manager option if no active login manager is found
if ! check_services_running; then
    options_command+=(
        "ly" "Install & configure ly display manager?" "ON"
    )
fi

# Add the remaining static options
options_command+=(
    "gtk_themes" "Install GTK themes? (required for Dark/Light function)" "OFF"
    "bluetooth" "Do you want script to configure Bluetooth?" "OFF"
    "thunar" "Do you want Thunar file manager to be installed?" "OFF"
    "quickshell" "Install quickshell for Desktop-Like Overview?" "OFF"
    "xdph" "Install XDG-DESKTOP-PORTAL-HYPRLAND (for screen share)?" "OFF"
    "zsh" "Install zsh shell with Oh-My-Zsh?" "OFF"
    "pokemon" "Add Pokemon color scripts to your terminal?" "OFF"
    "rog" "Are you installing on Asus ROG laptops?" "OFF"
    "dots" "Install the pre-configured Hyprland dotfiles?" "OFF"
    "handy" "Install Handy speech-to-text (CTRL+SUPER+F8 toggle)?" "OFF"
    "nopasswd_sudo" "Passwordless sudo for wheel? (needed by the bar's VPN widget)" "OFF"
    "printing" "Install CUPS printing? (nothing else pulls in a print stack)" "OFF"
    "docker" "Install Docker, socket-activated? (adds you to the root-equivalent 'docker' group)" "ON"
    "plymouth" "Plymouth boot splash with the repo logo? (wires it into boot if needed)" "OFF"
    "text_boot" "Text boot: show the kernel/systemd messages, no splash? (not with plymouth)" "ON"
    "limine" "Theme the Limine boot menu and disable its countdown? (edits limine.conf, backup kept)" "OFF"
    "herdr" "Install Herdr terminal workspace manager for AI coding agents?" "OFF"
    "neovim" "Install Neovim with LazyVim? (the file explorer beside the agents)" "OFF"
    "hunk" "Install Hunk diff viewer? (review what the agents wrote)" "OFF"
)

# With a preset, skip the menu entirely and derive the selection from the
# variables the preset set. Previously the preset was sourced and then ignored -
# the checklist below hardcodes "OFF" for every entry and never consulted these
# variables - so --preset presented an all-unticked menu and installed nothing
# unless the user re-selected everything by hand.
if [ "$preset_mode" == "true" ]; then
    selected_options=""
    for _opt in ly nvidia nouveau input_group gtk_themes bluetooth thunar \
                quickshell xdph zsh pokemon rog dots handy nopasswd_sudo \
                printing plymouth text_boot limine docker herdr neovim hunk; do
        [ "${!_opt}" == "ON" ] || continue

        # Respect the same conditions the interactive menu applies before it
        # offers an option, so a preset cannot ask for something nonsensical.
        case "$_opt" in
            nvidia|nouveau)
                if [ "$nvidia_detected" != "true" ]; then
                    echo "${NOTE} Preset forces '$_opt' but no NVIDIA GPU was detected. Skipping." | tee -a "$LOG"
                    continue
                fi
                # A Kepler-or-older card is "detected" but no maintained driver
                # binds to it. Forcing nvidia there used to run nvidia.sh anyway,
                # fail, and have the final check blame a missing DKMS module.
                if [ "$_opt" == "nvidia" ] && [ "$nvidia_supported" != "true" ]; then
                    echo "${NOTE} Preset forces 'nvidia' but this GPU is Kepler or older - no maintained driver supports it. Skipping." | tee -a "$LOG"
                    continue
                fi
                # Same card, other side: nouveau is the only driver it has.
                if [ "$_opt" == "nouveau" ] && [ "$nvidia_supported" != "true" ]; then
                    echo "${NOTE} Preset forces 'nouveau' but this GPU is Kepler or older - nouveau is its only driver, so it is not blacklisted. Skipping." | tee -a "$LOG"
                    continue
                fi
                ;;
            rog|bluetooth)
                # No gate: "auto" already resolved to OFF when nothing was detected, so an
                # ON that reaches this point is an explicit force-on (e.g. a Bluetooth
                # controller whose firmware is not loaded yet, or lsusb not installed).
                ;;
            input_group)
                if [ "$input_group_detected" != "true" ]; then
                    echo "${NOTE} Preset asks for 'input_group' but you are already in it. Skipping." | tee -a "$LOG"
                    continue
                fi
                ;;
            ly)
                if check_services_running; then
                    echo "${WARN} Preset asks for 'ly' but another login manager is active: ${active_services[*]}" | tee -a "$LOG"
                    echo "${NOTE} Skipping ly. Disable the active manager and re-run if you want it." | tee -a "$LOG"
                    continue
                fi
                ;;
        esac
        selected_options+="$_opt "
    done

    if [ -z "$selected_options" ]; then
        echo "${ERROR} Preset enabled no installable options. Nothing to do." | tee -a "$LOG"
        exit 1
    fi

    echo "${INFO} Preset mode - installing:" | tee -a "$LOG"
    for _opt in $selected_options; do echo "   - $_opt" | tee -a "$LOG"; done
    if [[ " $selected_options " != *" dots "* ]]; then
        echo "${WARN} 'dots' is not enabled, so none of the configs in Hyprland-Dots will be installed." | tee -a "$LOG"
    fi
    printf "\n%.0s" {1..1}
else

# Capture the selected options before the while loop starts
while true; do
    selected_options=$("${options_command[@]}" 3>&1 1>&2 2>&3)

    # Check if the user pressed Cancel (exit status 1)
    if [ $? -ne 0 ]; then
        echo -e "\n"
        echo "❌ ${INFO} You 🫵 cancelled the selection. ${YELLOW}Goodbye!${RESET}" | tee -a "$LOG"
        exit 0  # Exit the script if Cancel is pressed
    fi

    # If no option was selected, notify and restart the selection
    if [ -z "$selected_options" ]; then
        whiptail --title "Warning" --msgbox "No options were selected. Please select at least one option." 10 60
        continue  # Return to selection if no options selected
    fi

    # Strip the quotes and trim spaces if necessary (sanitize the input)
    selected_options=$(echo "$selected_options" | tr -d '"' | tr -s ' ')

    # Convert selected options into an array (preserving spaces in values)
    IFS=' ' read -r -a options <<< "$selected_options"

    # Check if the "dots" option was selected
    dots_selected="OFF"
    for option in "${options[@]}"; do
        if [[ "$option" == "dots" ]]; then
            dots_selected="ON"
            break
        fi
    done

    # If "dots" is not selected, show a note and ask the user to proceed or return to choices
    if [[ "$dots_selected" == "OFF" ]]; then
        # Show a note about not selecting the "dots" option
        if ! whiptail --title "Hyprland Dotfiles" --yesno \
        "You have not selected to install the pre-configured Hyprland dotfiles.\n\nNOTE: without them Hyprland starts with its default vanilla configuration - none of the bar, keybinds, theming or scripts in this repo will be in place.\n\nContinue without the dotfiles, or return to the options?" \
        --yes-button "Continue" --no-button "Return" 15 90; then
            echo "🔙 Returning to options..." | tee -a "$LOG"
            continue
        else
            # User chose to continue
            echo "${INFO} ⚠️ Continuing WITHOUT the dotfiles installation..." | tee -a "$LOG"
			printf "\n%.0s" {1..1}
        fi
    fi

    # Prepare the confirmation message
    confirm_message="You have selected the following options:\n\n"
    for option in "${options[@]}"; do
        confirm_message+=" - $option\n"
    done
    confirm_message+="\nAre you happy with these choices?"

    # Confirmation prompt
    if ! whiptail --title "Confirm Your Choices" --yesno "$(printf "%s" "$confirm_message")" 25 80; then
        echo -e "\n"
        echo "❌ ${SKY_BLUE}You're not 🫵 happy${RESET}. ${YELLOW}Returning to options...${RESET}" | tee -a "$LOG"
        continue 
    fi

    echo "👌 ${OK} You confirmed your choices. Proceeding with the ${SKY_BLUE}Hyprland installation...${RESET}" | tee -a "$LOG"
    break  
done
fi

printf "\n%.0s" {1..1}

# plymouth asks for the splash and text_boot takes it away: with both, the
# splash wins and text_boot is dropped here, before the selection is exported,
# so the final check does not look for its outcome either.
if [[ " $selected_options " == *" plymouth "* && " $selected_options " == *" text_boot "* ]]; then
    echo "${NOTE} Both 'plymouth' and 'text_boot' are selected - keeping the Plymouth splash and skipping text_boot." | tee -a "$LOG"
    selected_options=$(tr -s ' ' '\n' <<< "$selected_options" | grep -vx 'text_boot' | paste -sd' ' -)
fi

# The selection is exported so 02-Final-Check.sh can verify the *outcome* of
# each selected component (dots copied, ly enabled, zsh the login shell, ...)
# and not only whether packages landed - see the outcome checks in that file.
export INSTALL_SELECTED_OPTIONS="$selected_options"
# Also saved, for re-running the final check by hand: "auto" options resolve per
# machine (no plymouth on plain Arch, no bluetooth on a desktop without a
# controller, nvidia only where there is one), so a selection copied from the
# README used to give false failures or skip checks.
printf '%s\n' "$selected_options" > Install-Logs/.selected-options 2>/dev/null || true

# Reset the failed-package manifest that Global_functions.sh appends to and
# 02-Final-Check.sh reads. Truncated per run so a failure from a previous
# install is never reported against this one - the path must stay in step with
# FAILED_PACKAGES_MANIFEST in install-scripts/Global_functions.sh.
#
# HERE, next to .selected-options, not at the top: a run that stopped before
# this point (sudo refused, PulseAudio found, a cancelled menu) used to empty
# these lists while the previous run's selection stayed - and a final check run
# by hand then paired the old selection with no failures, passing a machine
# whose last real run had failed. Nothing before this point records into them.
# Still below the root check: run as root this would leave a root-owned file
# that every later non-root run then fails to truncate.
: > "Install-Logs/.failed-packages"
# Same treatment for the checksum-failure manifest, for the same reason: a
# stale tarball from a previous run must not be reported against this one.
: > "Install-Logs/.checksum-failures"
# And for failed initramfs rebuilds (INITRAMFS_FAILED_MANIFEST).
: > "Install-Logs/.initramfs-failures"
# Until this run reaches its final check, the lists above hold only part of it:
# pacman.sh, locales.sh or the AUR helper build can still stop the whole run
# (run_required), and a final check run by hand then paired this selection with
# near-empty lists and passed. The marker says so; it is removed right before
# the final check below, and 02-Final-Check.sh reports it when it is still here.
date '+%F %T' > Install-Logs/.run-in-progress 2>/dev/null || true

# Sudo, once, up front - and then never again for the rest of the run.
#
# Every install_* function runs `sudo pacman`/`yay` in the background with its
# output sent to the log, while show_progress redraws a spinner on the same
# line. sudo writes its password prompt to /dev/tty, so when the timestamp
# expired mid-run (the default is 5 minutes, and the first `yay -Syu`, the
# oh-my-zsh clone or the GTK theme extraction alone can take longer) the next
# package call looked like a spinner that had hung. "Fully unattended" was
# only true for the first five minutes.
#
# Two things fix it. If the preset asked for passwordless sudo, install that
# rule FIRST, before anything else needs root, so the rest of the run cannot
# prompt at all. And regardless, keep the sudo timestamp alive from a
# background loop for the whole run, which covers the interactive path and
# the few seconds before the rule lands.
# (sudo was authenticated and the keepalive started before hardware detection.)
if [[ " $selected_options " == *" nopasswd_sudo "* ]]; then
    echo "${INFO} Configuring ${SKY_BLUE}passwordless sudo for wheel${RESET} first, so nothing below can prompt..." | tee -a "$LOG"
    # The script's status and the rule itself, not `sudo -n true`: the `sudo -v`
    # and the keepalive loop at the top keep the timestamp valid, so that passed
    # whether or not the rule landed and this said "no longer asks" even after a
    # failed visudo check. Same test as 02-Final-Check.sh: nopasswd_rule_status
    # in Global_functions.sh ("NOPASSWD: ALL", not bluetooth.sh's narrower rule,
    # and "next-login" when this run had to add $USER to wheel). Sourced in a
    # child shell, like find_limine_conf above, because that file sets -e.
    if execute_script "sudoers_nopasswd.sh" \
        && _nopasswd=$(bash -c 'source "$1" && nopasswd_rule_status' _ "$script_directory/Global_functions.sh" 2>/dev/null); then
        if [ "$_nopasswd" = now ]; then
            echo "${OK} sudo no longer asks for a password." | tee -a "$LOG"
        else
            echo "${OK} Passwordless sudo is in place from the next login ($USER was just added to wheel); the keepalive loop carries this run." | tee -a "$LOG"
        fi
    else
        echo "${WARN} The passwordless sudo rule did not land (see above); the keepalive loop will carry the run instead." | tee -a "$LOG"
    fi
fi

# The three steps below are the base everything else installs onto. Each exits
# non-zero when it fails (pacman.sh on a failed full upgrade, locales.sh on a
# failed locale-gen), and used to be ignored here: the run carried on and put
# ~150 packages onto a partial upgrade, which is exactly what pacman.sh's own
# error message says not to do. Stop while the real error is still on screen.
run_required() {
    local script="$1"
    if ! execute_script "$script"; then
        echo "${ERROR} ${script} failed. Nothing after it can be trusted, so the install stops here." | tee -a "$LOG"
        echo "${NOTE} Read the error above (also in Install-Logs/), fix it, and re-run the installer." | tee -a "$LOG"
        exit 1
    fi
}

# pacman.sh first: it enables multilib, refreshes the keyring and runs the full
# upgrade, so 00-base.sh's installs (git, findutils) resolve against a freshly
# synced database rather than the one from the day the OS was installed.
run_required "pacman.sh"
sleep 1
# Ensuring base-devel is installed
run_required "00-base.sh"
sleep 1

# Generate the locales the dots reference. Runs before the dotfiles are copied,
# so that by the time environment.d/locale.conf and ENVariables.conf set
# LC_TIME=ru_RU.UTF-8, that locale actually exists. Setting LC_TIME to an
# ungenerated locale does not fail - glibc falls back to C in silence.
echo "${INFO} Generating ${SKY_BLUE}locales${RESET}..." | tee -a "$LOG"
run_required "locales.sh"
sleep 1

# pacman.sh's full upgrade runs after the check above, and a libalpm bump
# there can break a helper that still worked then. Rebuild yay in that case too
# (from the vendored PKGBUILD, as for a fresh machine).
if [ -z "${aur_helper:-}" ] && ! aur_helper_works; then
    aur_helper="yay"
    echo "${WARN} The installed AUR helper no longer starts (after the system upgrade?) - rebuilding ${SKY_BLUE}yay${RESET}." | tee -a "$LOG"
fi

# Execute AUR helper script after other installations if applicable
if [ "$aur_helper" == "paru" ]; then
    execute_script "paru.sh"
elif [ "$aur_helper" == "yay" ]; then
    execute_script "yay.sh"
fi

# Nothing below works without an AUR helper: install_package() would run
# `-S --noconfirm pkg` with an empty helper name, about 150 times, each one a
# silent failure, and the run would end an hour later with a misleading
# final screen. Stop here instead, while the real error is still on screen.
# `--version`, not only `command -v`: an AUR helper that is on PATH but cannot
# start (paru-bin linked against a libalpm soname that pacman no longer ships)
# passed the old check, and then every one of ~150 installs failed.
if ! aur_helper_works; then
    echo "${ERROR} No working AUR helper after ${aur_helper:-yay}.sh ran. Nothing else can install without one." | tee -a "$LOG"
    echo "${NOTE} Read the build error above (also in Install-Logs/), fix it, and re-run the installer." | tee -a "$LOG"
    exit 1
fi

sleep 1

# PipeWire before the package list. ffmpeg (behind wf-recorder, cava and mpv)
# needs a JACK library, and with nothing providing one yet pacman took its
# first provider, jack2 - which then also blocked pipewire-jack, which conflicts
# with it. pipewire.sh puts pipewire-jack in place first.
echo "${INFO} Installing ${SKY_BLUE}pipewire and pipewire-audio...${RESET}" | tee -a "$LOG"
sleep 1
execute_script "pipewire.sh"

# Run the Hyprland related scripts
echo "${INFO} Installing ${SKY_BLUE}additional Hyprland packages...${RESET}" | tee -a "$LOG"
sleep 1
execute_script "01-hypr-pkgs.sh"

echo "${INFO} Installing ${SKY_BLUE}CPU microcode...${RESET}" | tee -a "$LOG"
sleep 1
execute_script "ucode.sh"

echo "${INFO} Installing ${SKY_BLUE}GPU drivers...${RESET}" | tee -a "$LOG"
sleep 1
execute_script "graphics.sh"

echo "${INFO} Setting up ${SKY_BLUE}power profiles...${RESET}" | tee -a "$LOG"
sleep 1
execute_script "power_profiles.sh"

echo "${INFO} Setting up the ${SKY_BLUE}battery charge limit...${RESET}" | tee -a "$LOG"
sleep 1
execute_script "battery_charge_limit.sh"

echo "${INFO} Installing the ${SKY_BLUE}WireGuard killswitch helpers...${RESET}" | tee -a "$LOG"
sleep 1
execute_script "vpn_tools.sh"

echo "${INFO} Installing ${SKY_BLUE}necessary fonts...${RESET}" | tee -a "$LOG"
sleep 1
execute_script "fonts.sh"

echo "${INFO} Installing ${SKY_BLUE}Hyprland...${RESET}"
sleep 1
execute_script "hyprland.sh"

# Clean up the selected options (remove quotes and trim spaces)
selected_options=$(echo "$selected_options" | tr -d '"' | tr -s ' ')

# Convert selected options into an array (splitting by spaces)
IFS=' ' read -r -a options <<< "$selected_options"

# Loop through selected options
for option in "${options[@]}"; do
    case "$option" in
        ly)
            if check_services_running; then
                active_list=$(printf "%s\n" "${active_services[@]}")
                if [ "$preset_mode" == "true" ]; then
                    # exec "$0" would drop the --preset arguments and restart
                    # into an interactive run - or loop forever. Just skip.
                    echo "${WARN} Skipping ly, login manager active: $active_list" | tee -a "$LOG"
                    continue
                fi
                whiptail --title "Error" --msgbox "One of the following login services is running:\n$active_list\n\nPlease stop & disable it or DO not choose ly." 12 60
                exec "$SCRIPT_PATH"
            else
                echo "${INFO} Installing and configuring ${SKY_BLUE}ly display manager...${RESET}" | tee -a "$LOG"
                execute_script "ly.sh"
                execute_script "ly_config.sh"
            fi
            ;;
        nvidia)
            echo "${INFO} Configuring ${SKY_BLUE}nvidia stuff${RESET}" | tee -a "$LOG"
            # nvidia.sh exits non-zero unless every installed kernel ended up
            # with an NVIDIA module. Its result used to be ignored and nouveau
            # blacklisted regardless - a failed DKMS build then rebooted into
            # no GPU driver at all.
            if execute_script "nvidia.sh"; then
                nvidia_ok=true
            else
                nvidia_ok=false
                echo "${ERROR} The NVIDIA driver did not land - see the messages above." | tee -a "$LOG"
            fi
            ;;
        nouveau)
            # Only on top of a working NVIDIA driver. Ticking nouveau without
            # nvidia (or a preset forcing nouveau="ON" while nvidia resolved OFF)
            # used to blacklist it anyway: no GPU driver at all, Hyprland on
            # simpledrm, and the final check - whose NVIDIA checks only run when
            # nvidia is selected - passed and let the preset reboot.
            if [[ " $selected_options " != *" nvidia "* ]]; then
                echo "${WARN} Not blacklisting ${SKY_BLUE}nouveau${RESET}: the NVIDIA driver is not selected, and nouveau would be this GPU's only driver." | tee -a "$LOG"
            elif [ "${nvidia_ok:-false}" != "true" ]; then
                # It used to say "nouveau is the only driver left", as if skipping
                # this kept it working. It did not: nvidia-utils ships its own
                # "blacklist nouveau" (/usr/lib/modprobe.d/nvidia-utils.conf), so
                # the fallback only exists because nvidia.sh's failure path masks
                # that file - and only for as long as nothing else blacklists it.
                # It masks it only when NO kernel got the module; when some did,
                # it keeps it so those boot on nvidia, and the others get no
                # driver for the card. Either way, blacklisting more here helps
                # nothing.
                echo "${WARN} Not blacklisting ${SKY_BLUE}nouveau${RESET}: the NVIDIA driver did not land on every kernel. nvidia.sh's messages above say which kernels fall back to nouveau and which boot with no driver for the card." | tee -a "$LOG"
            else
                echo "${INFO} blacklisting ${SKY_BLUE}nouveau${RESET}"
                execute_script "nvidia_nouveau.sh" | tee -a "$LOG"
            fi
            ;;
        gtk_themes)
            echo "${INFO} Installing ${SKY_BLUE}GTK themes...${RESET}" | tee -a "$LOG"
            execute_script "gtk_themes.sh"
            ;;
        input_group)
            echo "${INFO} Adding user into ${SKY_BLUE}input group...${RESET}" | tee -a "$LOG"
            execute_script "InputGroup.sh"
            ;;
        quickshell)
            echo "${INFO} Installing ${SKY_BLUE}quickshell for Desktop Overview...${RESET}" | tee -a "$LOG"
            execute_script "quickshell.sh"
            ;;
        xdph)
            echo "${INFO} Installing ${SKY_BLUE}xdg-desktop-portal-hyprland...${RESET}" | tee -a "$LOG"
            execute_script "xdph.sh"
            ;;
        bluetooth)
            echo "${INFO} Configuring ${SKY_BLUE}Bluetooth...${RESET}" | tee -a "$LOG"
            execute_script "bluetooth.sh"
            ;;
        thunar)
            echo "${INFO} Installing ${SKY_BLUE}Thunar file manager...${RESET}" | tee -a "$LOG"
            execute_script "thunar.sh"
            execute_script "thunar_default.sh"
            # thunar_sort.sh is deliberately NOT here - it has to run after
            # dotfiles-main.sh. See below the loop.
            ;;
        zsh)
            echo "${INFO} Installing ${SKY_BLUE}zsh with Oh-My-Zsh...${RESET}" | tee -a "$LOG"
            execute_script "zsh.sh"
            ;;
        pokemon)
            echo "${INFO} Adding ${SKY_BLUE}Pokemon color scripts to terminal...${RESET}" | tee -a "$LOG"
            execute_script "zsh_pokemon.sh"
            ;;
        rog)
            echo "${INFO} Installing ${SKY_BLUE}ROG laptop packages...${RESET}" | tee -a "$LOG"
            execute_script "rog.sh"
            ;;
        dots)
            echo "${INFO} Installing the pre-configured ${SKY_BLUE}Hyprland dotfiles...${RESET}" | tee -a "$LOG"
            execute_script "dotfiles-main.sh"
            ;;
        handy)
            echo "${INFO} Installing ${SKY_BLUE}Handy speech-to-text...${RESET}" | tee -a "$LOG"
            execute_script "handy.sh"
            ;;
        nopasswd_sudo)
            # Already done at the top of the run, before the first package
            # install, so that nothing in between could prompt for a password.
            ;;
        printing)
            echo "${INFO} Installing ${SKY_BLUE}CUPS printing...${RESET}" | tee -a "$LOG"
            execute_script "printing.sh"
            ;;
        plymouth)
            echo "${INFO} Installing the ${SKY_BLUE}Plymouth boot splash${RESET} theme..." | tee -a "$LOG"
            execute_script "plymouth.sh"
            ;;
        text_boot)
            echo "${INFO} Switching the boot to ${SKY_BLUE}text${RESET} (no quiet, no splash)..." | tee -a "$LOG"
            execute_script "text-boot.sh"
            ;;
        limine)
            echo "${INFO} Theming the ${SKY_BLUE}Limine boot menu${RESET}..." | tee -a "$LOG"
            execute_script "limine.sh"
            ;;
        docker|herdr|neovim|hunk)
            # Handled after this loop, in order, because they depend on the
            # dotfiles already being in place. Listed here so they do not fall
            # into the "Unknown option" branch below and log a false alarm.
            ;;
        *)
            echo "Unknown option: $option" | tee -a "$LOG"
            ;;
    esac
done

sleep 1

# Thunar per-folder sort - AFTER the dotfiles, not with the rest of Thunar.
#
# thunar_sort.sh turns on /misc-directory-specific-settings, and xfconf-query
# stores that in ~/.config/xfce4/xfconf/xfce-perchannel-xml/thunar.xml. But
# "xfce4" is one of the directories copy.sh replaces wholesale, and the tracked
# copy of thunar.xml did not carry that property - so running the sort script
# inside the thunar) case (which the option order puts before dots) wrote the
# setting and then had dotfiles-main.sh copy it straight back off again. The
# tracked thunar.xml carries it now too: without it every re-run also backed
# up xfce4 over this one line, and a re-run inside a live session lost it for
# good - xfconfd still answered "true" from memory, so thunar_sort.sh skipped,
# and it never rewrites a value that has not changed.
#
# The symptom was quiet and misleading: the gio metadata on the folders lives in
# ~/.local/share/gvfs-metadata and DOES survive, so the per-folder sort was set
# up correctly and simply ignored, because the switch that makes Thunar honour
# per-folder settings at all had been reverted. Screenshots and Recordings
# opened in name order on every fresh install.
#
# Keyed off selected_options rather than the preset variable so it behaves the
# same on the interactive path, where the preset variables are never set.
if [[ " $selected_options " == *" thunar "* ]]; then
    echo "${INFO} Configuring ${SKY_BLUE}Thunar per-folder sort...${RESET}" | tee -a "$LOG"
    execute_script "thunar_sort.sh"
fi

sleep 1

# Docker with socket activation (on-demand daemon, no boot autostart).
#
# Gated now. This call used to be unconditional - the only component in the
# installer with no checkbox - so every machine got Docker and, with it,
# membership of the root-equivalent "docker" group whether or not that was
# wanted. Keyed off selected_options so the interactive path and the preset
# path behave the same, exactly like the thunar_sort block above.
if [[ " $selected_options " == *" docker "* ]]; then
    echo "${INFO} Installing ${SKY_BLUE}Docker (socket-activated)...${RESET}" | tee -a "$LOG"
    sleep 1
    execute_script "docker.sh"
fi

# Herdr - AFTER the dotfiles, for the same reason as thunar_sort above.
#
# herdr.sh downloads only the binary and writes only the systemd --user unit.
# Its config.toml, notification sounds and the four herdr-* helper scripts are
# dotfiles, and config.toml is shipped with __HOME__ placeholders that herdr.sh
# rewrites in the installed copy. Run before dotfiles-main.sh and the
# substitution would target a file that does not exist yet, then copy.sh would
# lay the templated version down on top of it.
if [[ " $selected_options " == *" herdr "* ]]; then
    echo "${INFO} Installing ${SKY_BLUE}Herdr terminal workspace manager...${RESET}" | tee -a "$LOG"
    sleep 1
    execute_script "herdr.sh"
fi

# Neovim - the file explorer half of the herdr workspace. Independent of herdr
# itself (it is just an editor), so it is not gated on the herdr option.
if [[ " $selected_options " == *" neovim "* ]]; then
    echo "${INFO} Installing ${SKY_BLUE}Neovim with LazyVim...${RESET}" | tee -a "$LOG"
    sleep 1
    execute_script "neovim.sh"
fi

# Hunk - AFTER the dotfiles, like herdr above: it reports on whether the layout
# functions (config/zsh/herdr-layouts.zsh) arrived, and that check needs them to
# already be in ~/.config.
if [[ " $selected_options " == *" hunk "* ]]; then
    echo "${INFO} Installing ${SKY_BLUE}Hunk diff viewer...${RESET}" | tee -a "$LOG"
    sleep 1
    execute_script "hunk.sh"
fi

# Enable essential system services
echo "${INFO} Enabling ${SKY_BLUE}essential system services...${RESET}" | tee -a "$LOG"
sleep 1
execute_script "services.sh"

# copy fastfetch config if arch.png is not present. From the dotfiles: the
# duplicate assets/fastfetch/ it used to read is gone.
if [ ! -f "$HOME/.config/fastfetch/arch.png" ]; then
    # mkdir first: with dots off, ~/.config need not exist yet, and
    # `cp -r dir ~/.config/` into a missing directory fails.
    mkdir -p "$HOME/.config"
    cp -r Hyprland-Dots/config/fastfetch "$HOME/.config/"
fi

# No `clear` here, on purpose. It used to wipe the screen right before the
# final check, so any error a script printed during the run was gone by the
# time the reboot countdown started - the one moment you would want to read it.
printf "\n%.0s" {1..2}

# Final check that every package actually landed AND that each selected
# component produced what it was supposed to (dots in ~/.config, ly enabled,
# zsh the login shell, the locales generated, ...). Its exit code gates the
# preset auto-reboot below: an incomplete install must not reboot out from
# under you with the warning scrolled off the screen.
# Every step has run, so the failure lists are complete for this run.
rm -f Install-Logs/.run-in-progress
if execute_script "02-Final-Check.sh"; then
    install_complete="true"
else
    install_complete="false"
fi

printf "\n%.0s" {1..1}

# Check if hyprland or hyprland-git is installed
if pacman -Q hyprland &> /dev/null || pacman -Q hyprland-git &> /dev/null; then
    if [ "$install_complete" == "true" ]; then
        printf "\n ${OK} 👌 Hyprland is installed and every package checked out."
    else
        printf "\n ${WARN} Hyprland is installed, but ${WARNING}the final check found problems${RESET} - see the list above."
    fi
    printf "\n"
    sleep 2
    printf "\n%.0s" {1..2}

    # Only after a passing check: it used to sit between "the final check found
    # problems" and "NOT rebooting", and told you to type a bare `Hyprland`
    # (if SDDM was not installed - this setup uses ly), which Hyprland 0.56
    # itself warns against.
    if [ "$install_complete" == "true" ]; then
        printf "${SKY_BLUE}Installation complete.${RESET} ${YELLOW}Enjoy!${RESET}"
        printf "\n%.0s" {1..2}
        printf "\n${NOTE} Reboot to log in through ly. To try it before that, run ${SKY_BLUE}start-hyprland${RESET} from a TTY.\n\n"
    fi

    # Repeated here because the warning from hardware detection is an hour of
    # scrollback away by now, and this is what the screen shows before a reboot
    # (or before the NOT-rebooting list below).
    if [ "$asus_dgpu_off" == "true" ]; then
        # "If it is NVIDIA", like the warning at detection time: the switched-off
        # GPU may be AMD, and then nvidia.sh finds no NVIDIA card and the verify
        # step below would fail every kernel's NVIDIA module check.
        echo "${WARN} Reminder: the ASUS dGPU was switched off (Eco mode), so it was not visible to this run."
        echo "${NOTE} If it is an NVIDIA GPU: switch to Hybrid (ROG Control Center -> GPU Configuration, or ${MAGENTA}asusctl armoury set dgpu_disable 0${RESET}), reboot, then run ${MAGENTA}install-scripts/nvidia.sh${RESET}."
        # The saved selection has no nvidia in it, so a plain re-check would skip
        # exactly the checks that matter after that.
        echo "${NOTE} Then verify it with nvidia in the selection: ${MAGENTA}INSTALL_SELECTED_OPTIONS=\"\$(cat Install-Logs/.selected-options) nvidia\" ./install-scripts/02-Final-Check.sh${RESET}"
        printf "\n%.0s" {1..1}
    fi

    # An unattended reboot is only safe when the install actually completed.
    # With packages missing, rebooting just hides the evidence: the warning
    # scrolls away with the session and the next thing you see is a desktop
    # that is subtly wrong, with nothing on screen saying why. Stop instead and
    # leave the list in front of you.
    if [ "$preset_mode" == "true" ] && [ "$install_complete" != "true" ]; then
        printf "\n%.0s" {1..1}
        echo "${WARN} NOT rebooting: the final check found missing packages or a component that did not land."
        echo "${CAT} Fix what is listed above, then reboot with ${MAGENTA}systemctl reboot${RESET}."
        echo "${NOTE} Most package failures are AUR builds. Retry one with:"
        echo "        ${MAGENTA}yay -S <package>${RESET}"
        echo "${NOTE} herdr, hunk, lazyvim, plymouth-theme-*, plymouth-hook, plymouth-splash and text-boot are not packages - the list above says what to re-run or fix."
        echo "${NOTE} A failed component can be retried with its script, e.g. ${MAGENTA}install-scripts/dotfiles-main.sh${RESET}"
        echo "${NOTE} The full list is in ${MAGENTA}Install-Logs/00_CHECK-*_installed.log${RESET}"
        printf "\n%.0s" {1..2}
        exit 1
    fi

    # sudo, not a bare `systemctl reboot`. polkit lets an unprivileged user
    # reboot only from the local active session (allow_active=yes); from an SSH
    # session it is auth_admin_keep, so the unattended reboot sat at a
    # pkttyagent password prompt or failed with "Access denied". sudo is already
    # authenticated for the whole run (the keepalive at the top) or NOPASSWD.
    # -n so it can never stop to ask; if it cannot, plain systemctl still works
    # from a local session.
    reboot_now() { sudo -n systemctl reboot 2>/dev/null || systemctl reboot; }

    # A preset run is meant to be unattended, so it reboots on its own rather
    # than parking on a prompt nobody is there to answer. The countdown is the
    # escape hatch: Ctrl-C, or any keypress, cancels the reboot.
    if [ "$preset_mode" == "true" ]; then
        if [ -t 0 ]; then
            echo "${NOTE} Preset mode: rebooting in 15 seconds."
            echo "${CAT} Press any key to cancel and stay in this session."
            # Throw away anything typed during the install first. Background jobs
            # read nothing from the terminal, so every stray key from the last hour
            # sat in the input buffer and `read -n 1` took it at once - cancelling
            # the reboot before the countdown had started.
            while read -r -t 0.05 -n 1000 _discard; do :; done
            if read -r -t 15 -n 1; then
                printf "\n"
                echo "👌 ${OK} Reboot cancelled. Reboot yourself with ${MAGENTA}systemctl reboot${RESET} when ready."
                printf "\n%.0s" {1..2}
                exit 0
            fi
        else
            # No terminal on stdin (nohup, </dev/null, `ssh host ./install.sh`
            # without -t): `read` hits end of file at once, so the 15-second
            # countdown rebooted immediately and no keypress could ever cancel
            # it. Wait the 15 seconds anyway; Ctrl-C is the way out.
            echo "${NOTE} Preset mode, no terminal on stdin: rebooting in 15 seconds (Ctrl-C to abort)."
            sleep 15
        fi
        printf "\n"
        echo "${INFO} Rebooting now..."
        reboot_now
        exit 0
    fi

    while true; do
        echo -n "${CAT} Would you like to reboot now? (y/n): "
        # End of input (stdin redirected, or the terminal went away) makes read
        # return nothing, for ever, and this loop printed "Invalid response"
        # without end. No answer is a no.
        if ! read -r HYP && [ -z "$HYP" ]; then
            printf "\n"
            echo "${NOTE} No answer (end of input) - not rebooting."
            HYP="n"
        fi
        HYP=$(echo "$HYP" | tr '[:upper:]' '[:lower:]')

        if [[ "$HYP" == "y" || "$HYP" == "yes" ]]; then
            echo "${INFO} Rebooting now..."
            reboot_now
            break
        elif [[ "$HYP" == "n" || "$HYP" == "no" ]]; then
            echo "👌 ${OK} You chose NOT to reboot"
            printf "\n%.0s" {1..1}
            # Check if NVIDIA GPU is present
            if lspci | grep -i "nvidia" &> /dev/null; then
                echo "${INFO} HOWEVER ${YELLOW}NVIDIA GPU${RESET} detected. Reminder that you must REBOOT your SYSTEM..."
                printf "\n%.0s" {1..1}
            fi
            break
        else
            echo "${WARN} Invalid response. Please answer with 'y' or 'n'."
        fi
    done
else
    # Print error message if neither package is installed
    printf "\n${WARN} Hyprland is NOT installed. Please check 00_CHECK-time_installed.log and other files in the Install-Logs/ directory..."
    printf "\n%.0s" {1..3}
    exit 1
fi


printf "\n%.0s" {1..2}