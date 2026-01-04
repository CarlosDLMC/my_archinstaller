#!/bin/bash
# Script to copy customized dotfiles to user's home directory

# Set some colors for output messages
OK="$(tput setaf 2)[OK]$(tput sgr0)"
ERROR="$(tput setaf 1)[ERROR]$(tput sgr0)"
NOTE="$(tput setaf 3)[NOTE]$(tput sgr0)"
INFO="$(tput setaf 4)[INFO]$(tput sgr0)"
RESET="$(tput sgr0)"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

printf "\n${NOTE} Copying customized dotfiles to your home directory...\n\n"

# Copy shell configuration files
printf "${INFO} Copying shell configuration files...\n"
for file in .zshrc .zprofile .bashrc .bash_profile pokefetch_perfect; do
    if [ -f "$SCRIPT_DIR/$file" ]; then
        cp "$SCRIPT_DIR/$file" "$HOME/" 2>/dev/null && echo "  ${OK} Copied $file"
    fi
done

# Copy .local/bin scripts
printf "\n${INFO} Copying custom scripts...\n"
if [ -d "$SCRIPT_DIR/.local/bin" ]; then
    mkdir -p "$HOME/.local/bin"
    cp -r "$SCRIPT_DIR/.local/bin/"* "$HOME/.local/bin/" 2>/dev/null && echo "  ${OK} Copied .local/bin scripts"
    chmod +x "$HOME/.local/bin/"* 2>/dev/null
fi

# Copy config directories
printf "\n${INFO} Copying configuration directories...\n"
mkdir -p "$HOME/.config"

# List of config directories to copy
config_dirs=(
    "hypr"
    "quickshell"
    "wlogout"
    "wallust"
    "foot"
    "rofi"
    "swaync"
    "swappy"
    "fastfetch"
    "btop"
    "cava"
    "Kvantum"
    "Mousepad"
    "mpv"
    "qt5ct"
    "qt6ct"
    "Thunar"
)

for dir in "${config_dirs[@]}"; do
    if [ -d "$SCRIPT_DIR/config/$dir" ]; then
        # Backup existing config if it exists
        if [ -d "$HOME/.config/$dir" ]; then
            printf "  ${NOTE} Backing up existing $dir to $dir.backup\n"
            mv "$HOME/.config/$dir" "$HOME/.config/$dir.backup" 2>/dev/null
        fi

        printf "  ${INFO} Copying $dir from $SCRIPT_DIR/config/$dir to $HOME/.config/\n"
        if cp -r "$SCRIPT_DIR/config/$dir" "$HOME/.config/" 2>&1; then
            echo "  ${OK} Copied $dir"
        else
            echo "  ${ERROR} Failed to copy $dir"
            exit 1
        fi
    else
        printf "  ${WARN} $dir not found in $SCRIPT_DIR/config/, skipping\n"
    fi
done

printf "\n${OK} Dotfiles installation complete!\n\n"
