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
    # GTK4 apps that do not link libadwaita (pavucontrol) ignore gsettings
    # color-scheme, the xdg-desktop-portal appearance setting AND gtk-3.0's
    # settings.ini. Without this they render in GTK4's built-in light Adwaita.
    "gtk-4.0"
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

# Where each directory's backup ended up, keyed by directory name. The wallust
# seeding further down reads this to recover the live palette from the copy it
# just displaced - see the comment there.
declare -A BACKUP_OF

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
                BACKUP_OF["$dir"]="$backup"
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

# Expand $HOME in the Thunar sidebar bookmarks
#
# GTK reads this file as a list of absolute file:// URIs and does no variable
# expansion of its own, so the tracked copy cannot just say $HOME - but it also
# must not hardcode one machine's home, which is what it did before: every
# bookmark pointed at /home/mentefria and every one of them was dead on any
# other machine. Tracked as a template, substituted here.
printf "\n${INFO} Expanding \$HOME in GTK bookmarks...\n"
_bookmarks="$HOME/.config/gtk-3.0/bookmarks"
if [ -f "$_bookmarks" ]; then
    if sed -i "s|\$HOME|$HOME|g" "$_bookmarks"; then
        echo "  ${OK} Thunar sidebar bookmarks point at $HOME"
    else
        echo "  ${ERROR} Could not expand \$HOME in $_bookmarks - the sidebar bookmarks will be dead links"
    fi
fi

# Seed the wallust output files
#
# Every path below is a `target` in config/wallust/wallust.toml, so it is
# regenerated in full on every wallpaper change. That makes them runtime state,
# and they are gitignored for it - see .gitignore. But they are not optional:
#
#   - UserConfigs/UserDecorations.lua requires wallust/wallust-hyprland.lua
#     (it falls back to a built-in palette, but seeding keeps colours consistent)
#   - twelve rofi themes `@theme` colors-rofi.rasi
#   - wlogout/style.css `@import`s colors-waybar.css
#
# A missing file at any of those is a config error on first launch, not a
# silent fallback, and first launch happens before initial-boot.sh has had a
# chance to run wallust. So a rendered snapshot of each ships in defaults/ and
# is copied into place here. wallust overwrites all of them on first login.
#
# On a RE-RUN the live palette is recovered from the backup rather than
# reverted to the snapshot. This needs saying because it is not obvious: every
# one of these files sits inside a directory the loop above backs up and
# replaces wholesale, so by the time we get here the live copy has already been
# moved aside. Without the recovery step a re-install would silently reset the
# desktop to the snapshot palette - and it would STAY there, because
# initial-boot.sh is guarded by ~/.config/hypr/.initial_startup_done and does
# not run a second time. Nothing would repaint until the next wallpaper change.
printf "\n${INFO} Seeding wallust output files...\n"
wallust_targets=(
    "cava/config"
    "hypr/wallust/wallust-hyprland.lua"
    "rofi/wallust/colors-rofi.rasi"
    "wallust/output/colors-waybar.css"
    "quickshell/qml_color.json"
)

for _target in "${wallust_targets[@]}"; do
    _seed="$SCRIPT_DIR/defaults/$_target"
    _dest="$HOME/.config/$_target"
    # "hypr/wallust/wallust-hyprland.lua" -> dir "hypr", rest "wallust/..."
    _dir="${_target%%/*}"
    _rest="${_target#*/}"
    _live="${BACKUP_OF[$_dir]:+${BACKUP_OF[$_dir]}/$_rest}"

    if [ -e "$_dest" ]; then
        echo "  ${NOTE} $_target already present - left alone"
        continue
    fi

    mkdir -p "$(dirname "$_dest")"

    if [ -n "$_live" ] && [ -f "$_live" ]; then
        if cp "$_live" "$_dest"; then
            echo "  ${OK} Kept your current palette for $_target"
            continue
        fi
        echo "  ${WARN} Could not recover $_target from the backup - falling back to the shipped default"
    fi

    if [ ! -f "$_seed" ]; then
        echo "  ${ERROR} Missing seed defaults/$_target - $_dest will not exist until wallust runs"
        continue
    fi

    if cp "$_seed" "$_dest"; then
        echo "  ${OK} Seeded $_target"
    else
        echo "  ${ERROR} Failed to seed $_target"
    fi
done

# Deploy secrets.zsh, but only if the user does not already have one
#
# Two things here are load-bearing:
#
#   - "zsh" is deliberately NOT in config_dirs above. That loop backs up and
#     *replaces* whole directories, which would move a filled-in secrets.zsh
#     out from under the user on every re-run.
#
#   - The copy is guarded by a -e test. The tracked copy of this file holds
#     placeholder values, so overwriting a real one would silently replace live
#     credentials with "sk-ant-1234" - and the only symptom would be every
#     authenticated tool failing at once, with nothing pointing at the cause.
#     Create when missing, never overwrite.
printf "\n${INFO} Setting up machine-local secrets...\n"
if [ -f "$SCRIPT_DIR/config/zsh/secrets.zsh" ]; then
    mkdir -p "$HOME/.config/zsh"

    if [ -e "$HOME/.config/zsh/secrets.zsh" ]; then
        echo "  ${NOTE} ~/.config/zsh/secrets.zsh already exists - left untouched"
    else
        cp "$SCRIPT_DIR/config/zsh/secrets.zsh" "$HOME/.config/zsh/secrets.zsh"
        chmod 600 "$HOME/.config/zsh/secrets.zsh"
        echo "  ${OK} Created ~/.config/zsh/secrets.zsh (mode 600)"
        echo "  ${NOTE} Everything in it is commented out - uncomment the keys you use and"
        echo "  ${NOTE} replace the placeholder values with the real ones"
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

    # Point the rofi background symlink at the deployed wallpaper.
    #
    # WallustSwww.sh re-links this on every wallpaper change, so it is runtime
    # state and is gitignored. It used to be tracked, and as a symlink git
    # stores the target verbatim: it was an absolute path into /home/mentefria
    # naming a wallpaper this repo does not ship, so on any other machine the
    # six rofi themes that use it as a background got a dead link.
    #
    # Linked to ~/Pictures/wallpapers rather than into the repo, because that is
    # where the wallpaper still is after the repo is moved or deleted.
    # Like the wallust outputs above, the rofi/ backup is consulted first so a
    # re-install keeps whatever wallpaper you were actually using.
    _rofi_link="$HOME/.config/rofi/.current_wallpaper"
    _rofi_live="${BACKUP_OF[rofi]:+${BACKUP_OF[rofi]}/.current_wallpaper}"
    _rofi_target="$HOME/Pictures/wallpapers/$DEFAULT_WALLPAPER"

    if [ -n "$_rofi_live" ] && [ -e "$_rofi_live" ]; then
        # -e, not -L: a symlink left dangling by a deleted wallpaper is no use.
        _rofi_target="$(readlink -f "$_rofi_live")"
        echo "  ${NOTE} Keeping your current rofi background"
    fi

    if ln -sfn "$_rofi_target" "$_rofi_link"; then
        echo "  ${OK} rofi background linked to $(basename "$_rofi_target")"
    else
        echo "  ${ERROR} Could not link $_rofi_link - rofi themes will have no background"
    fi
else
    echo "  ${ERROR} Default wallpaper $DEFAULT_WALLPAPER not found - first boot will have no wallpaper"
fi

printf "\n${OK} Dotfiles installation complete!\n\n"
