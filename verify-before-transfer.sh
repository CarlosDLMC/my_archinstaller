#!/bin/bash
# Run this script BEFORE transferring to verify everything is ready

OK="$(tput setaf 2)[OK]$(tput sgr0)"
ERROR="$(tput setaf 1)[ERROR]$(tput sgr0)"
NOTE="$(tput setaf 3)[NOTE]$(tput sgr0)"
INFO="$(tput setaf 4)[INFO]$(tput sgr0)"
RESET="$(tput sgr0)"

# Resolve the repo and its name from this script's own location, rather than
# hardcoding the upstream project's name.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_NAME="$(basename "$REPO_DIR")"

printf "\n${NOTE} Verifying $REPO_NAME directory is ready for transfer...\n\n"

# Check if we're in the right directory
if [ ! -f "$REPO_DIR/install.sh" ]; then
    printf "${ERROR} This script must be run from the $REPO_NAME directory\n"
    printf "${INFO} Run: cd $REPO_DIR && ./verify-before-transfer.sh\n"
    exit 1
fi

all_good=true

# Check critical files
printf "${INFO} Checking critical files...\n"
critical_files=(
    "install.sh"
    "custom-preset.conf"
    "diagnose.sh"
    "Hyprland-Dots/copy.sh"
    "Hyprland-Dots/.zshrc"
    "Hyprland-Dots/pokefetch_perfect"
    "install-scripts/dotfiles-main.sh"
    "install-scripts/02-Final-Check.sh"
)

for file in "${critical_files[@]}"; do
    if [ -f "$file" ]; then
        printf "  ${OK} $file exists\n"
    else
        printf "  ${ERROR} $file MISSING\n"
        all_good=false
    fi
done

# Check critical directories
printf "\n${INFO} Checking critical directories...\n"
critical_dirs=(
    "Hyprland-Dots/config/hypr"
    "Hyprland-Dots/config/quickshell"
    "Hyprland-Dots/config/wlogout"
    "Hyprland-Dots/config/wallust"
    "Hyprland-Dots/config/foot"
    "Hyprland-Dots/.local/bin"
    "install-scripts"
)

for dir in "${critical_dirs[@]}"; do
    if [ -d "$dir" ]; then
        printf "  ${OK} $dir/ exists\n"
    else
        printf "  ${ERROR} $dir/ MISSING\n"
        all_good=false
    fi
done

# Check VPN widget
printf "\n${INFO} Checking custom widgets...\n"
if [ -f "Hyprland-Dots/config/quickshell/bar/components/VpnWidget.qml" ]; then
    printf "  ${OK} VpnWidget.qml exists\n"
else
    printf "  ${ERROR} VpnWidget.qml MISSING\n"
    all_good=false
fi

if [ -f "Hyprland-Dots/config/quickshell/bar/components/NightLightWidget.qml" ]; then
    printf "  ${OK} NightLightWidget.qml exists\n"
else
    printf "  ${ERROR} NightLightWidget.qml MISSING\n"
    all_good=false
fi

if [ -f "Hyprland-Dots/config/quickshell/bar/components/KeyboardLayoutWidget.qml" ]; then
    printf "  ${OK} KeyboardLayoutWidget.qml exists\n"
else
    printf "  ${ERROR} KeyboardLayoutWidget.qml MISSING\n"
    all_good=false
fi

# Check pokefetch helper
printf "\n${INFO} Checking pokefetch scripts...\n"
if [ -f "Hyprland-Dots/.local/bin/pokefetch-merge" ]; then
    printf "  ${OK} pokefetch-merge exists\n"
else
    printf "  ${ERROR} pokefetch-merge MISSING\n"
    all_good=false
fi

# Show directory size
printf "\n${INFO} Directory size:\n"
du -sh . 2>/dev/null | sed 's/^/  /'
printf "\n${INFO} Hyprland-Dots size:\n"
du -sh Hyprland-Dots/ 2>/dev/null | sed 's/^/  /'

# Summary
printf "\n${NOTE} ========== SUMMARY ==========\n"
if [ "$all_good" = true ]; then
    printf "${OK} All critical files and directories are present!\n\n"
    printf "${INFO} Ready to transfer. Use one of these methods:\n\n"
    printf "1. USB Transfer:\n"
    printf "   tar -czf ~/$REPO_NAME.tar.gz -C $(dirname "$REPO_DIR") $REPO_NAME\n"
    printf "   # Copy ~/$REPO_NAME.tar.gz to USB\n\n"
    printf "2. Network transfer (if both computers are networked):\n"
    printf "   rsync -av $REPO_DIR/ user@newcomputer:~/Documents/$REPO_NAME/\n\n"
    printf "3. On new computer after transfer:\n"
    printf "   cd ~/Documents/$REPO_NAME\n"
    printf "   ./install.sh --preset custom-preset.conf\n\n"
else
    printf "${ERROR} Some files are missing! Fix these before transferring.\n"
    exit 1
fi
