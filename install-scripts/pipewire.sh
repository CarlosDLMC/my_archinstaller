#!/bin/bash
# Pipewire and Pipewire Audio Stuff #

pipewire=(
    pipewire
    wireplumber
    pipewire-audio
    pipewire-alsa
    pipewire-pulse
    # JACK through PipeWire. Without it the first package that needs a JACK
    # library (ffmpeg, behind wf-recorder, cava and mpv) brought in jack2,
    # pacman's first provider under --noconfirm.
    pipewire-jack
    lib32-pipewire-jack
    sof-firmware
)

############## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##############
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Change the working directory to the parent directory of the script
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "[ERROR] Failed to change directory to $PARENT_DIR"; exit 1; }

# Source the global functions script
source "$SCRIPT_DIR/Global_functions.sh"

# Set the name of the log file to include the current date and time
LOG="Install-Logs/install-$(date +%Y%m%d-%H%M%S)_pipewire.log"

# Disabling pulseaudio to avoid conflicts and logging output
echo -e "${NOTE} Disabling pulseaudio to avoid conflicts..."
systemctl --user disable --now pulseaudio.socket pulseaudio.service >> "$LOG" 2>&1 || true

# jack2 from an earlier run: pipewire-jack conflicts with it, and --noconfirm
# answers "Remove jack2?" with no, so it could never be added afterwards.
# Swapped like install.sh swaps PulseAudio - without dependency checks, since
# what needs it needs a libjack, which pipewire-jack provides right after.
_jack2=$(pacman -Qq jack2 lib32-jack2 2>/dev/null || true)
if [ -n "$_jack2" ]; then
    echo -e "${NOTE} Replacing $(echo $_jack2) with pipewire-jack..."
    sudo pacman -Rdd --noconfirm $_jack2 >> "$LOG" 2>&1 || echo -e "${ERROR} Could not remove $(echo $_jack2) - see $LOG"
fi

# Pipewire
echo -e "${NOTE} Installing ${SKY_BLUE}Pipewire${RESET} Packages..."
for PIPEWIRE in "${pipewire[@]}"; do
    install_package "$PIPEWIRE" "$LOG"
done

echo -e "${NOTE} Activating Pipewire Services..."
# Redirect systemctl output to log file
systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service 2>&1 | tee -a "$LOG"
systemctl --user enable --now pipewire.service 2>&1 | tee -a "$LOG"

echo -e "\n${OK} Pipewire Installation and services setup complete!" 2>&1 | tee -a "$LOG"

printf "\n%.0s" {1..2}
