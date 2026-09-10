#!/bin/bash
# Script to copy customized dotfiles to user's home directory

# Set some colors for output messages
OK="$(tput setaf 2)[OK]$(tput sgr0)"
ERROR="$(tput setaf 1)[ERROR]$(tput sgr0)"
NOTE="$(tput setaf 3)[NOTE]$(tput sgr0)"
WARN="$(tput setaf 1)[WARN]$(tput sgr0)"
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
    # GTK font, cursor theme/size and prefer-dark. initial-boot.sh sets the
    # theme names over gsettings, but GTK3 itself reads this file, and without
    # it the font drops to the default 11pt Cantarell.
    "gtk-3.0"
    # LC_TIME for the whole graphical session: 24-hour clock, Monday-first
    # calendar and Cyrillic month names. Needs install-scripts/locales.sh to
    # have generated ru_RU.UTF-8, or glibc falls back to C in silence.
    "environment.d"
    # nwg-displays' own settings (view scale, snap threshold). It is referenced
    # 17 times across the dots as the monitor-layout tool.
    "nwg-displays"
    # 99-no-ligatures.conf turns off liga/clig/calt/dlig and swaps JetBrains
    # Mono and Fira Code for their no-ligature cuts. Without it a fresh machine
    # gets ligatures everywhere - ->, =>, != rendered as single glyphs.
    "fontconfig"
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

# Install the secrets template, and seed the real file only if absent
#
# NOTE: "zsh" is deliberately NOT in config_dirs above. That loop backs up and
# *replaces* the whole directory, which would move a filled-in secrets.zsh out
# from under the user on every re-run. This block only ever adds.
printf "\n${INFO} Setting up machine-local secrets...\n"
if [ -f "$SCRIPT_DIR/config/zsh/secrets.zsh.example" ]; then
    mkdir -p "$HOME/.config/zsh"

    # The template itself is always refreshed - it is documentation, not data.
    cp "$SCRIPT_DIR/config/zsh/secrets.zsh.example" "$HOME/.config/zsh/secrets.zsh.example"
    echo "  ${OK} Copied secrets.zsh.example"

    # The real file is created from the template ONLY when missing. Never
    # overwrite it: it holds live credentials that exist nowhere else, and this
    # script is expected to be re-run.
    if [ -e "$HOME/.config/zsh/secrets.zsh" ]; then
        echo "  ${NOTE} secrets.zsh already exists - left untouched"
    else
        cp "$SCRIPT_DIR/config/zsh/secrets.zsh.example" "$HOME/.config/zsh/secrets.zsh"
        chmod 600 "$HOME/.config/zsh/secrets.zsh"
        echo "  ${OK} Created ~/.config/zsh/secrets.zsh from the template (mode 600)"
        echo "  ${NOTE} It holds placeholder values - edit it and put your real keys in"
    fi
fi

# Copy the wallpaper library
#
# The dots hardcode $HOME/Pictures/wallpapers in WallpaperSelect.sh,
# WallpaperRandom.sh and Startup_Apps.conf, so an empty directory there means
# the wallpaper picker opens with nothing in it.
printf "\n${INFO} Copying wallpapers...\n"
if [ -d "$SCRIPT_DIR/wallpapers" ]; then
    mkdir -p "$HOME/Pictures/wallpapers"
    # No backup/replace dance here: wallpapers are additive. Overwriting only
    # the ones we ship leaves anything the user added themselves alone.
    if cp -r "$SCRIPT_DIR/wallpapers/." "$HOME/Pictures/wallpapers/"; then
        echo "  ${OK} Copied $(find "$SCRIPT_DIR/wallpapers" -type f | wc -l) wallpapers to ~/Pictures/wallpapers"
    else
        echo "  ${ERROR} Failed to copy wallpapers"
    fi
fi

# Seed the active wallpaper
#
# initial-boot.sh loads $HOME/.config/hypr/wallpaper_effects/.wallpaper_current
# and does nothing at all if that file is missing - no wallpaper, and no wallust
# run to colour the bar from it. The file is a copy of the active wallpaper
# rather than a path, so it is runtime state and is not tracked; this is where
# the default gets chosen.
DEFAULT_WALLPAPER="sovietpunk/sovietpunk_2k_2560x1440.png"

printf "\n${INFO} Setting default wallpaper...\n"
_default_src="$SCRIPT_DIR/wallpapers/$DEFAULT_WALLPAPER"
if [ -f "$_default_src" ]; then
    mkdir -p "$HOME/.config/hypr/wallpaper_effects"
    # .wallpaper_modified is the WallpaperEffects.sh output and the background
    # of the rofi effect picker. Seed it with the unmodified image so the picker
    # has something to show before any effect has been applied.
    if cp "$_default_src" "$HOME/.config/hypr/wallpaper_effects/.wallpaper_current" &&
       cp "$_default_src" "$HOME/.config/hypr/wallpaper_effects/.wallpaper_modified"; then
        echo "  ${OK} Default wallpaper set to $DEFAULT_WALLPAPER"
    else
        echo "  ${ERROR} Failed to set default wallpaper"
    fi
else
    echo "  ${ERROR} Default wallpaper $DEFAULT_WALLPAPER not found - first boot will have no wallpaper"
fi

printf "\n${OK} Dotfiles installation complete!\n\n"
