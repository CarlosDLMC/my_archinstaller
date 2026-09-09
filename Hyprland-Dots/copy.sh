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
    # chmod only what we copied. A blanket chmod +x on ~/.local/bin/* would also
    # flip the mode of unrelated things already installed there (uv, aws, claude).
    for _src in "$SCRIPT_DIR/.local/bin/"*; do
        [ -e "$_src" ] || continue
        if cp "$_src" "$HOME/.local/bin/"; then
            chmod +x "$HOME/.local/bin/$(basename "$_src")"
            echo "  ${OK} Copied $(basename "$_src")"
        fi
    done
fi

# Copy .local/share data files (D-Bus service overrides, etc.)
printf "\n${INFO} Copying .local/share data files...\n"
if [ -d "$SCRIPT_DIR/.local/share" ]; then
    mkdir -p "$HOME/.local/share"
    cp -r "$SCRIPT_DIR/.local/share/." "$HOME/.local/share/" 2>/dev/null && echo "  ${OK} Copied .local/share data files"
fi

# Copy XDG user directories configuration
printf "\n${INFO} Copying XDG user directories configuration...\n"
for file in user-dirs.dirs user-dirs.locale; do
    if [ -f "$SCRIPT_DIR/config/$file" ]; then
        cp "$SCRIPT_DIR/config/$file" "$HOME/.config/" 2>/dev/null && echo "  ${OK} Copied $file"
    fi
done

# Create XDG user directories with proper icons
if command -v xdg-user-dirs-update &> /dev/null; then
    printf "${INFO} Creating XDG user directories...\n"
    xdg-user-dirs-update 2>/dev/null && echo "  ${OK} Created user directories (Documents, Downloads, Videos, etc.)"
fi

# Copy mimeapps.list
printf "\n${INFO} Copying MIME type associations...\n"
if [ -f "$SCRIPT_DIR/config/mimeapps.list" ]; then
    cp "$SCRIPT_DIR/config/mimeapps.list" "$HOME/.config/" 2>/dev/null && echo "  ${OK} Copied mimeapps.list"
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
    "dunst"
    # swaync is NOT the notification daemon here (dunst is), but ~/.config/swaync
    # is the icon/image asset store that 25 of the hypr scripts point at
    # (iDIR="$HOME/.config/swaync/icons"). Dropping it kills notification icons.
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
    "xfce4"
)

# One stamp for the whole run, so a single invocation's backups group together.
BACKUP_STAMP="$(date +%Y%m%d-%H%M%S)"

for dir in "${config_dirs[@]}"; do
    if [ -d "$SCRIPT_DIR/config/$dir" ]; then
        # Back up to a timestamped name. A fixed "$dir.backup" target breaks on
        # re-run: the second run moves the config *inside* the existing backup,
        # and the third fails outright with "Directory not empty" - silently,
        # since the error was discarded - leaving the old config in place to be
        # merged over rather than replaced.
        if [ -d "$HOME/.config/$dir" ]; then
            # The stamp only has second resolution, so two runs inside the same
            # second would collide and mv would nest again. Find a free name.
            backup="$HOME/.config/$dir.backup-$BACKUP_STAMP"
            _n=1
            while [ -e "$backup" ]; do
                backup="$HOME/.config/$dir.backup-$BACKUP_STAMP-$_n"
                _n=$((_n + 1))
            done
            # -T: treat the target as a name, never as a directory to move into,
            # so a lost race fails loudly instead of silently nesting.
            if mv -T "$HOME/.config/$dir" "$backup"; then
                printf "  ${NOTE} Backed up existing $dir to $(basename "$backup")\n"
            else
                echo "  ${ERROR} Could not back up existing $dir - skipping it rather than merging over it"
                continue
            fi
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
