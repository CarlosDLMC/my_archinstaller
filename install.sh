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

# Create Directory for Install Logs
if [ ! -d Install-Logs ]; then
    mkdir Install-Logs
fi

# Set the name of the log file to include the current date and time
LOG="Install-Logs/01-Hyprland-Install-Scripts-$(date +%Y%m%d-%H%M%S).log"

# Check if running as root. If root, script will exit
if [[ $EUID -eq 0 ]]; then
    echo "${ERROR}  This script should ${WARNING}NOT${RESET} be executed as root!! Exiting......." | tee -a "$LOG"
    printf "\n%.0s" {1..2} 
    exit 1
fi

# Reset the failed-package manifest that Global_functions.sh appends to and
# 02-Final-Check.sh reads. Truncated per run so a failure from a previous
# install is never reported against this one - the path must stay in step with
# FAILED_PACKAGES_MANIFEST in install-scripts/Global_functions.sh.
#
# Below the root check on purpose: run as root this would leave a root-owned
# file that every later non-root run then fails to truncate.
: > "Install-Logs/.failed-packages"

# Check if PulseAudio package is installed
if pacman -Qq | grep -qw '^pulseaudio$'; then
    echo "$ERROR PulseAudio is detected as installed. Uninstall it first, or comment out the execute_script 'pipewire.sh' call in install.sh." | tee -a "$LOG"
    printf "\n%.0s" {1..2} 
    exit 1
fi

# Check if base-devel is installed
if pacman -Q base-devel &> /dev/null; then
    echo "base-devel is already installed."
else
    echo "$NOTE Install base-devel.........."

    if sudo pacman -S --noconfirm base-devel; then
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
    sudo pacman -S --noconfirm libnewt
    printf "\n%.0s" {1..1}
fi

## Default values for the options (will be overwritten by preset file if available)
gtk_themes="OFF"
bluetooth="OFF"
thunar="OFF"
quickshell="OFF"
sddm="OFF"
sddm_theme="OFF"
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

# Function to load preset file
load_preset() {
    if [ -f "$1" ]; then
        echo "✅ Loading preset: $1"
        source "$1"
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

# install pciutils if detected not installed. Necessary for detecting GPU
if ! pacman -Qs pciutils > /dev/null; then
    echo "${NOTE} - pciutils is not installed. Installing..." | tee -a "$LOG"
    sudo pacman -S --noconfirm pciutils
    printf "\n%.0s" {1..1}
fi

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


# Check if yay or paru is installed
echo "${INFO} - Checking if yay or paru is installed"
if ! command -v yay &>/dev/null && ! command -v paru &>/dev/null; then
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
        aur_helper=$(whiptail --title "Neither Yay nor Paru is installed" --checklist "Neither Yay nor Paru is installed. Choose one AUR.\n\nNOTE: Select only 1 AUR helper!\nINFO: spacebar to select" 12 60 2 \
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
services=("gdm.service" "gdm3.service" "lightdm.service" "lxdm.service")

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

# Check if NVIDIA GPU is detected
nvidia_detected=false
if lspci | grep -i "nvidia" &> /dev/null; then
    nvidia_detected=true
    if [ "$preset_mode" == "true" ]; then
        echo "${NOTE} NVIDIA GPU detected. It is configured unless the preset sets nvidia=\"OFF\"." | tee -a "$LOG"
    else
        whiptail --title "NVIDIA GPU Detected" --msgbox "NVIDIA GPU detected in your system.\n\nNOTE: The script will install nvidia-dkms, nvidia-utils, and nvidia-settings if you chose to configure." 12 60
    fi
fi

# Check if this is an ASUS laptop (asusctl/supergfxctl target ROG hardware).
# DMI is the same question rog="ON" was asking the user to answer by hand.
rog_detected=false
if grep -qi 'asus' /sys/class/dmi/id/sys_vendor 2>/dev/null; then
    rog_detected=true
    echo "${NOTE} ASUS hardware detected (${SKY_BLUE}$(cat /sys/class/dmi/id/sys_vendor)${RESET})." | tee -a "$LOG"
fi

# Resolve "auto" into ON/OFF from what was just detected. Only the preset loop
# reads these - the interactive checklist below ships its own defaults - so an
# interactive run is unaffected.
for _hw in nvidia nouveau rog; do
    [ "${!_hw}" == "auto" ] || continue
    case "$_hw" in
        nvidia|nouveau) _want="$nvidia_detected" ;;
        rog)            _want="$rog_detected" ;;
    esac
    if [ "$_want" == "true" ]; then
        printf -v "$_hw" "ON"
        echo "${NOTE} auto: enabling ${SKY_BLUE}$_hw${RESET} (hardware detected)." | tee -a "$LOG"
    else
        printf -v "$_hw" "OFF"
    fi
done

# Initialize the options array for whiptail checklist
options_command=(
    whiptail --title "Select Options" --checklist "Choose options to install or configure\nNOTE: 'SPACEBAR' to select & 'TAB' key to change selection" 28 85 20
)

# Add NVIDIA options if detected
if [ "$nvidia_detected" == "true" ]; then
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
                printing; do
        [ "${!_opt}" == "ON" ] || continue

        # Respect the same conditions the interactive menu applies before it
        # offers an option, so a preset cannot ask for something nonsensical.
        case "$_opt" in
            nvidia|nouveau)
                if [ "$nvidia_detected" != "true" ]; then
                    echo "${NOTE} Preset forces '$_opt' but no NVIDIA GPU was detected. Skipping." | tee -a "$LOG"
                    continue
                fi
                ;;
            rog)
                if [ "$rog_detected" != "true" ]; then
                    echo "${NOTE} Preset forces 'rog' but this is not ASUS hardware. Skipping." | tee -a "$LOG"
                    continue
                fi
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

# Ensuring base-devel is installed
execute_script "00-base.sh"
sleep 1
execute_script "pacman.sh"
sleep 1

# Generate the locales the dots reference. Runs before the dotfiles are copied,
# so that by the time environment.d/locale.conf and ENVariables.conf set
# LC_TIME=ru_RU.UTF-8, that locale actually exists. Setting LC_TIME to an
# ungenerated locale does not fail - glibc falls back to C in silence.
echo "${INFO} Generating ${SKY_BLUE}locales${RESET}..." | tee -a "$LOG"
execute_script "locales.sh"
sleep 1

# Execute AUR helper script after other installations if applicable
if [ "$aur_helper" == "paru" ]; then
    execute_script "paru.sh"
elif [ "$aur_helper" == "yay" ]; then
    execute_script "yay.sh"
fi

sleep 1

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

echo "${INFO} Installing ${SKY_BLUE}pipewire and pipewire-audio...${RESET}" | tee -a "$LOG"
sleep 1
execute_script "pipewire.sh"

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
                exec "$0"
            else
                echo "${INFO} Installing and configuring ${SKY_BLUE}ly display manager...${RESET}" | tee -a "$LOG"
                execute_script "ly.sh"
                execute_script "ly_config.sh"
            fi
            ;;
        nvidia)
            echo "${INFO} Configuring ${SKY_BLUE}nvidia stuff${RESET}" | tee -a "$LOG"
            execute_script "nvidia.sh"
            ;;
        nouveau)
            echo "${INFO} blacklisting ${SKY_BLUE}nouveau${RESET}"
            execute_script "nvidia_nouveau.sh" | tee -a "$LOG"
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
            echo "${INFO} Configuring ${SKY_BLUE}passwordless sudo for wheel...${RESET}" | tee -a "$LOG"
            execute_script "sudoers_nopasswd.sh"
            ;;
        printing)
            echo "${INFO} Installing ${SKY_BLUE}CUPS printing...${RESET}" | tee -a "$LOG"
            execute_script "printing.sh"
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
# copy of thunar.xml does not carry that property - so running the sort script
# inside the thunar) case (which the option order puts before dots) wrote the
# setting and then had dotfiles-main.sh copy it straight back off again.
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

# Install Docker with socket activation (on-demand daemon, no boot autostart)
echo "${INFO} Installing ${SKY_BLUE}Docker (socket-activated)...${RESET}" | tee -a "$LOG"
sleep 1
execute_script "docker.sh"

# Enable essential system services
echo "${INFO} Enabling ${SKY_BLUE}essential system services...${RESET}" | tee -a "$LOG"
sleep 1
execute_script "services.sh"

# copy fastfetch config if arch.png is not present. From the dotfiles: the
# duplicate assets/fastfetch/ it used to read is gone.
if [ ! -f "$HOME/.config/fastfetch/arch.png" ]; then
    cp -r Hyprland-Dots/config/fastfetch "$HOME/.config/"
fi

clear

# Final check that every package actually landed. Its exit code gates the
# preset auto-reboot below: an incomplete install must not reboot out from
# under you with the warning scrolled off the screen.
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
        printf "\n ${WARN} Hyprland is installed, but ${WARNING}some packages are missing${RESET} - see the list above."
    fi
    printf "\n"
    sleep 2
    printf "\n%.0s" {1..2}

    printf "${SKY_BLUE}Installation complete.${RESET} ${YELLOW}Enjoy!${RESET}"
    printf "\n%.0s" {1..2}

    printf "\n${NOTE} You can start Hyprland by typing ${SKY_BLUE}Hyprland${RESET} (IF SDDM is not installed) (note the capital H!).\n"
    printf "\n${NOTE} However, it is ${YELLOW}highly recommended to reboot${RESET} your system.\n\n"

    # An unattended reboot is only safe when the install actually completed.
    # With packages missing, rebooting just hides the evidence: the warning
    # scrolls away with the session and the next thing you see is a desktop
    # that is subtly wrong, with nothing on screen saying why. Stop instead and
    # leave the list in front of you.
    if [ "$preset_mode" == "true" ] && [ "$install_complete" != "true" ]; then
        printf "\n%.0s" {1..1}
        echo "${WARN} NOT rebooting: the final check found missing packages."
        echo "${CAT} Install them, then reboot with ${MAGENTA}systemctl reboot${RESET}."
        echo "${NOTE} Most failures here are AUR builds. Retry one with:"
        echo "        ${MAGENTA}yay -S <package>${RESET}"
        echo "${NOTE} The full list is in ${MAGENTA}Install-Logs/00_CHECK-*_installed.log${RESET}"
        printf "\n%.0s" {1..2}
        exit 1
    fi

    # A preset run is meant to be unattended, so it reboots on its own rather
    # than parking on a prompt nobody is there to answer. The countdown is the
    # escape hatch: Ctrl-C, or any keypress, cancels the reboot.
    if [ "$preset_mode" == "true" ]; then
        echo "${NOTE} Preset mode: rebooting in 15 seconds."
        echo "${CAT} Press any key to cancel and stay in this session."
        if read -r -t 15 -n 1; then
            printf "\n"
            echo "👌 ${OK} Reboot cancelled. Reboot yourself with ${MAGENTA}systemctl reboot${RESET} when ready."
            printf "\n%.0s" {1..2}
            exit 0
        fi
        printf "\n"
        echo "${INFO} Rebooting now..."
        systemctl reboot
        exit 0
    fi

    while true; do
        echo -n "${CAT} Would you like to reboot now? (y/n): "
        read HYP
        HYP=$(echo "$HYP" | tr '[:upper:]' '[:lower:]')

        if [[ "$HYP" == "y" || "$HYP" == "yes" ]]; then
            echo "${INFO} Rebooting now..."
            systemctl reboot 
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