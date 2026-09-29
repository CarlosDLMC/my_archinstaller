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

# One stamp for the whole run, so a single invocation's backups group together.
BACKUP_STAMP="$(date +%Y%m%d-%H%M%S)"

# A video wallpaper chosen in WallpaperSelect.sh lives in three lines of
# hypr/configs/Startup_Apps.lua: livewallpaper, awww-daemon commented out,
# mpvpaper live. Copy that choice from one Startup_Apps.lua to another with the
# same seds WallpaperSelect.sh uses - never the whole file, which is the repo's
# and should still update. Returns 1 when <from> holds no video choice.
# ENVIRON, not awk -v: -v would unescape backslashes in the path.
# LC_ALL=C and grep -a throughout: a line saved by an older WallpaperSelect.sh
# can hold raw bytes that are not valid UTF-8, and in a UTF-8 locale grep then
# printed "binary file matches" instead of the line - the path came back empty
# and the next login had video mode with no video.
#
# The path is read BEFORE <to> is touched, and any spacing is accepted (a hand
# edit like local livewallpaper="..." is valid Lua). It used to switch <to> to
# video mode first and then find no path - a login with mpvpaper on and an empty
# path, i.e. no wallpaper at all. Returns 0 copied, 1 no video in <from>, 2 a
# video is on in <from> but its path line cannot be read (nothing changed).
copy_video_wallpaper() { # from to
    local _from="$1" _to="$2" _lw _t
    local _lw_re='^[[:space:]]*local[[:space:]]+livewallpaper[[:space:]]*='
    [ -f "$_from" ] && [ -f "$_to" ] || return 1
    LC_ALL=C grep -aqE '^\s*run\("mpvpaper ' "$_from" || return 1
    _lw=$(LC_ALL=C grep -aE "$_lw_re" "$_from" | head -n 1)
    [ -n "$_lw" ] || return 2
    # Both edits in ONE pass into a temp file, which replaces <to> only once it
    # was written in full. The mode switch used to be a sed -i on <to> first: a
    # temp file that could not be written (a full TMPDIR) then left mpvpaper on
    # with an empty path - and still returned 0.
    _t=$(mktemp) || return 2
    if LW="$_lw" RE="$_lw_re" LC_ALL=C awk '$0 ~ ENVIRON["RE"] {print ENVIRON["LW"]; next} {print}' "$_to" \
         | LC_ALL=C sed -E 's|^(\s*)run\("awww-daemon --format argb"\)|\1-- run("awww-daemon --format argb")|; s|^(\s*)--\s*run\("mpvpaper |\1run("mpvpaper |' >"$_t" \
       && [ -s "$_t" ] && cat "$_t" >"$_to"; then
        rm -f "$_t"
        return 0
    fi
    rm -f "$_t"
    return 2
}

# Is <file> one of the animation presets Animations.sh copies in? Only then is
# a UserAnimations.lua a CHOICE; an untouched copy of an older repo version is
# not, and must not be kept over the updated one.
is_animation_preset() { # file animations-dir
    local _a
    for _a in "$2"/*.lua; do
        if [ -f "$_a" ] && cmp -s "$_a" "$1"; then
            return 0
        fi
    done
    return 1
}

# Every path below is a `target` in config/wallust/wallust.toml - the palette,
# regenerated in full on every wallpaper change, so runtime state and
# gitignored. Defined up here because restore_state (in the config loop) and
# the seeding step further down both use it; see "Seed the wallust output
# files" for why each one has to exist.
wallust_targets=(
    "cava/config"
    "hypr/wallust/wallust-hyprland.lua"
    "rofi/wallust/colors-rofi.rasi"
    "wallust/output/colors-waybar.css"
    "quickshell/qml_color.json"
    # bar/Theme.qml reads this through a FileView. The bar and initial-boot.sh's
    # first `wallust run` start in parallel from hyprland.start, so without a
    # seed the bar can load before the file exists and sit on its fallback
    # palette until it is restarted.
    "quickshell/bar/wallust-colors.json"
)

# Put hypr/'s machine state back from its backup: what the repo's copy either
# lacks or holds only as a template.
restore_hypr_state() { # backup
    local _bak="$1" _state _ua _rc
    # Not in the repo at all: the first-boot marker, the active wallpaper, and
    # the monitors.conf / workspaces.conf nwg-displays writes next to the .lua.
    for _state in .initial_startup_done wallpaper_effects/.wallpaper_current wallpaper_effects/.wallpaper_modified monitors.conf workspaces.conf; do
        if [ -f "$_bak/$_state" ] && [ ! -e "$HOME/.config/hypr/$_state" ]; then
            mkdir -p "$(dirname "$HOME/.config/hypr/$_state")"
            cp "$_bak/$_state" "$HOME/.config/hypr/$_state" && echo "  ${OK} Kept your $_state from the previous install"
        fi
    done

    # The monitor and workspace layout belong to the machine, not the repo: the
    # tracked monitors.lua / workspaces.lua are generic templates that
    # nwg-displays overwrites on Apply. Unlike the files above these DO exist in
    # the fresh copy (as the templates), so the backup has to win outright -
    # otherwise a re-run reset every monitor to the catch-all highres/auto rule.
    for _state in monitors.lua workspaces.lua; do
        if [ -f "$_bak/$_state" ] && ! cmp -s "$_bak/$_state" "$HOME/.config/hypr/$_state"; then
            cp "$_bak/$_state" "$HOME/.config/hypr/$_state" && echo "  ${OK} Kept your $_state from the previous install"
        fi
    done

    # UserAnimations.lua is state too - Animations.sh copies the chosen preset
    # over it - but only when it IS one of the presets: an untouched copy of an
    # older repo version is not a choice, and keeping it blocked repo updates.
    _ua="UserConfigs/UserAnimations.lua"
    if [ -f "$_bak/$_ua" ] && ! cmp -s "$_bak/$_ua" "$HOME/.config/hypr/$_ua" \
       && is_animation_preset "$_bak/$_ua" "$HOME/.config/hypr/animations"; then
        cp "$_bak/$_ua" "$HOME/.config/hypr/$_ua" && echo "  ${OK} Kept your animation preset ($_ua) from the previous install"
    fi

    # The video wallpaper: only its three lines, not the whole Startup_Apps.lua
    # (see copy_video_wallpaper). Without this the next login showed a still image.
    copy_video_wallpaper "$_bak/configs/Startup_Apps.lua" "$HOME/.config/hypr/configs/Startup_Apps.lua"
    _rc=$?
    if [ "$_rc" -eq 0 ]; then
        echo "  ${OK} Kept your video wallpaper from the previous install"
    elif [ "$_rc" -eq 2 ]; then
        echo "  ${WARN} Your Startup_Apps.lua had mpvpaper on, but the video could not be carried over (no livewallpaper line this script can read, or no room for a temp file). It is in $(basename "$_bak"); pick it again with SUPER+W."
    fi
}

# Put a directory's machine state back from its backup RIGHT AFTER the loop
# below copies it. It used to happen only at the very end, after every other
# directory and the 49 MB wallpaper copy, from the backup path remembered in
# that same run: anything that stopped the run in between (Ctrl-C, a closed
# terminal, a full disk, a failed cp) left the monitor layout, the animation
# preset, the video wallpaper, the palette and the first-boot marker in a
# hypr.backup-* the next run never looked at - by then hypr/ matched the repo
# again, so nothing was backed up and nothing restored.
restore_state() { # dir backup
    local _dir="$1" _bak="$2" _t _s
    # This directory's palette files.
    for _t in "${wallust_targets[@]}"; do
        [ "${_t%%/*}" = "$_dir" ] || continue
        _s="${_t#*/}"
        if [ -f "$_bak/$_s" ] && [ ! -e "$HOME/.config/$_t" ]; then
            mkdir -p "$(dirname "$HOME/.config/$_t")"
            cp "$_bak/$_s" "$HOME/.config/$_t" && echo "  ${OK} Kept your current palette for $_t"
        fi
    done
    case "$_dir" in
    hypr) restore_hypr_state "$_bak" ;;
    rofi)
        # The rofi background link. -e, not -L: one left dangling by a deleted
        # wallpaper is no use.
        if [ -e "$_bak/.current_wallpaper" ] && [ ! -e "$HOME/.config/rofi/.current_wallpaper" ]; then
            ln -sfn "$(readlink -f "$_bak/.current_wallpaper")" "$HOME/.config/rofi/.current_wallpaper" \
                && echo "  ${NOTE} Keeping your current rofi background"
        fi
        ;;
    nwg-displays)
        # Saved display profiles and the active one: nwg-displays' own state,
        # which the repo does not track and the backup took along.
        for _s in profiles active_profile.json; do
            if [ -e "$_bak/$_s" ] && [ ! -e "$HOME/.config/nwg-displays/$_s" ]; then
                cp -a "$_bak/$_s" "$HOME/.config/nwg-displays/$_s" && echo "  ${OK} Kept your nwg-displays $_s"
            fi
        done
        ;;
    esac
}

# Copy shell configuration files - backing up the existing ones like every config
# directory below. ZshChangeTheme.sh edits ~/.zshrc in place and people add aliases;
# a re-run used to discard that silently.
printf "${INFO} Copying shell configuration files...\n"
for file in .zshrc .zprofile .bashrc .bash_profile pokefetch_perfect; do
    if [ -f "$SCRIPT_DIR/$file" ]; then
        if [ -f "$HOME/$file" ] && ! cmp -s "$SCRIPT_DIR/$file" "$HOME/$file"; then
            cp "$HOME/$file" "$HOME/$file.backup-$BACKUP_STAMP" && echo "  ${NOTE} Backed up existing $file to $file.backup-$BACKUP_STAMP"
        fi
        if cp "$SCRIPT_DIR/$file" "$HOME/" 2>/dev/null; then
            # .zshrc runs pokefetch_perfect only when it is executable
            # (`[ -x "$HOME/pokefetch_perfect" ]`), and skips it silently when
            # not - and cp does not make it so: a new copy takes the checkout's
            # mode (644 in a checkout that lost its exec bits, which is why the
            # README says `chmod +x install.sh`), and an existing
            # ~/pokefetch_perfect keeps whatever mode it already had. zsh.sh
            # used to chmod it, but leaves this file to us when dots is selected.
            [ "$file" = pokefetch_perfect ] && chmod +x "$HOME/$file"
            echo "  ${OK} Copied $file"
        fi
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
        # Same cmp-then-back-up as the shell files: an edited script used to be
        # replaced with nothing left of the edit.
        _dst="$HOME/.local/bin/$(basename "$_src")"
        if [ -f "$_dst" ] && ! cmp -s "$_src" "$_dst"; then
            # chmod -x: ~/.local/bin is on PATH, and an executable backup
            # would show up there as a command.
            cp "$_dst" "$_dst.backup-$BACKUP_STAMP" && chmod -x "$_dst.backup-$BACKUP_STAMP" \
                && echo "  ${NOTE} Backed up existing $(basename "$_src") to $(basename "$_src").backup-$BACKUP_STAMP"
        fi
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
    # Per file, backed up first when it differs (the dunst D-Bus service
    # override, say) - a plain cp -r used to replace an edited one silently.
    while IFS= read -r -d '' _src; do
        _rel="${_src#"$SCRIPT_DIR/.local/share/"}"
        _dst="$HOME/.local/share/$_rel"
        if [ -f "$_dst" ] && ! cmp -s "$_src" "$_dst"; then
            cp "$_dst" "$_dst.backup-$BACKUP_STAMP" && echo "  ${NOTE} Backed up existing $_rel to $(basename "$_rel").backup-$BACKUP_STAMP"
        fi
    done < <(find "$SCRIPT_DIR/.local/share" -type f -print0)
    cp -r "$SCRIPT_DIR/.local/share/." "$HOME/.local/share/" 2>/dev/null && echo "  ${OK} Copied .local/share data files"
fi

# ~/.config has to exist before anything is copied into it. On a fresh machine
# it usually does by now (yay and pipewire.sh create it), but the user-dirs
# copies below used to run before the mkdir further down and fail silently.
mkdir -p "$HOME/.config"

# Back up a top-level ~/.config file before the repo copy replaces it.
#
# Unlike the shell files above and the config directories below, mimeapps.list
# and the user-dirs files used to be replaced with no backup at all - and
# mimeapps.list is where every "open with" choice made since the install lives:
# on this machine a re-run would have silently taken Slack sign-in links and
# double-clicked .docx files away from the apps they had been set to, with
# nothing left to restore them from.
#
# Backed up when the live file holds a line the repo copy lacks, rather than on
# any `cmp` difference, because tools rewrite both files during every install
# and a byte comparison would back up nothing but their output:
#   - thunar_default.sh runs `xdg-mime default` BEFORE the dots, so on a fresh
#     machine mimeapps.list already exists with its two Thunar lines (and a
#     leading blank line) - both are in the repo copy too.
#   - xdg-user-dirs-update, run just below, adds every default the repo's
#     user-dirs.dirs does not name - current xdg-user-dirs adds
#     XDG_PROJECTS_DIR="$HOME/Projects" - so every re-run found that line
#     "changed". Lines built from /etc/xdg/user-dirs.defaults the way it writes
#     them are ignored for that reason; a Projects entry pointed elsewhere
#     still counts.
# A changed default app or a moved Downloads is a line the repo does not have,
# so that is still backed up.
backup_config_file() {
    local _src="$1" _dst="$2"
    [ -f "$_dst" ] || return 0
    if grep -vxF -f "$_src" \
            -f <(sed -n 's/^\([A-Z_]\+\)=\(.*\)$/XDG_\1_DIR="$HOME\/\2"/p' /etc/xdg/user-dirs.defaults 2>/dev/null) \
            "$_dst" | grep -q .; then
        cp "$_dst" "$_dst.backup-$BACKUP_STAMP" && echo "  ${NOTE} Backed up existing $(basename "$_dst") to $(basename "$_dst").backup-$BACKUP_STAMP"
    fi
}

# Copy XDG user directories configuration
printf "\n${INFO} Copying XDG user directories configuration...\n"
for file in user-dirs.dirs user-dirs.locale; do
    if [ -f "$SCRIPT_DIR/config/$file" ]; then
        backup_config_file "$SCRIPT_DIR/config/$file" "$HOME/.config/$file"
        cp "$SCRIPT_DIR/config/$file" "$HOME/.config/" 2>/dev/null && echo "  ${OK} Copied $file"
    fi
done

# Create the XDG user directories (Downloads, Pictures, ...) so Thunar shows
# them with their special icons.
#
# The directories are created here, by hand, BEFORE xdg-user-dirs-update runs.
# That order matters: with a user-dirs.dirs already in place (copied just
# above), xdg-user-dirs-update treats every configured directory that does not
# exist as one the user deleted and rewrites its entry to "$HOME/" instead of
# creating it. On the first CachyOS desktop install that left a home with no
# Downloads/Pictures/... at all, and a `mkdir ~/Downloads` afterwards got a plain
# folder icon because the config no longer pointed at it. Only Documents, which
# existed for the git clone, came out right.
if [ -f "$HOME/.config/user-dirs.dirs" ]; then
    printf "${INFO} Creating XDG user directories...\n"
    (
        # shellcheck disable=SC1091
        source "$HOME/.config/user-dirs.dirs"
        for d in "$XDG_DESKTOP_DIR" "$XDG_DOWNLOAD_DIR" "$XDG_TEMPLATES_DIR" \
                 "$XDG_PUBLICSHARE_DIR" "$XDG_DOCUMENTS_DIR" "$XDG_MUSIC_DIR" \
                 "$XDG_PICTURES_DIR" "$XDG_VIDEOS_DIR"; do
            [ -n "$d" ] && [ "$d" != "$HOME" ] && [ "$d" != "$HOME/" ] && mkdir -p "$d"
        done
    )
    echo "  ${OK} Created user directories (Documents, Downloads, Videos, etc.)"
fi
# Now the update only registers what exists (and adds any newer defaults such
# as Projects) instead of un-configuring the missing ones.
if command -v xdg-user-dirs-update &> /dev/null; then
    xdg-user-dirs-update 2>/dev/null || true
fi

# Copy mimeapps.list
printf "\n${INFO} Copying MIME type associations...\n"
if [ -f "$SCRIPT_DIR/config/mimeapps.list" ]; then
    backup_config_file "$SCRIPT_DIR/config/mimeapps.list" "$HOME/.config/mimeapps.list"
    cp "$SCRIPT_DIR/config/mimeapps.list" "$HOME/.config/" 2>/dev/null && echo "  ${OK} Copied mimeapps.list"
fi

# Copy config directories
printf "\n${INFO} Copying configuration directories...\n"
mkdir -p "$HOME/.config"

# List of config directories to copy
config_dirs=(
    "hypr"
    # NOT herdr: ~/.config/herdr is also herdr's runtime directory - the running
    # server's sockets, session.json and its logs live next to config.toml - so
    # moving it aside wholesale took the saved session and the live sockets with
    # it on every re-run. It is deployed file by file further down.
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
    "fastfetch"
    "btop"
    "cava"
    "Kvantum"
    "Mousepad"
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
    # MangoHud.conf is not just an overlay layout: fps_limit and vsync in it
    # actively cap and pace the game, so it is the panel tuning (48-75 Hz
    # FreeSync window, cap 3 under the 75 Hz ceiling) in file form. Inert
    # unless a game is launched with `mangohud %command%` - see GAMES_README.md.
    "MangoHud"
)

# Where each directory's backup ended up, keyed by directory name. The wallust
# seeding further down reads this to recover the live palette from the copy it
# just displaced - see the comment there.
declare -A BACKUP_OF

# A directory is "half-replaced" from the moment it is moved aside until its copy
# and state restore are done. If the run is stopped in that window (Ctrl-C, the
# terminal closed, a kill), put the original back instead of leaving a partial
# copy with the real one stranded in a backup.
_replacing=""
rollback_replace() {
    [ -n "$_replacing" ] || return 0
    local _d="${_replacing%%|*}" _b="${_replacing#*|}"
    rm -rf "$HOME/.config/$_d" && mv -T "$_b" "$HOME/.config/$_d" \
        && echo "  ${WARN} Put your original $_d back (from $(basename "$_b"))"
    unset "BACKUP_OF[$_d]"
    _replacing=""
}
trap 'echo; rollback_replace; exit 130' INT TERM HUP

# Directories that could not be copied. The run carries on with the rest, then
# exits 1 and leaves Install-Logs/.dots-failed for 02-Final-Check.sh - it used to
# `exit 1` on the spot, which skipped every later step, and install.sh ignores
# dotfiles-main.sh's status, so the final check then passed anyway.
copy_failed=()
DOTS_FAILED="$SCRIPT_DIR/../Install-Logs/.dots-failed"

for dir in "${config_dirs[@]}"; do
    if [ -d "$SCRIPT_DIR/config/$dir" ]; then
        # Back up to a timestamped name. A fixed "$dir.backup" target breaks on
        # re-run: the second run moves the config *inside* the existing backup,
        # and the third fails outright with "Directory not empty" - silently,
        # since the error was discarded - leaving the old config in place to be
        # merged over rather than replaced.
        # An existing directory that is byte-for-byte the repo copy holds
        # nothing worth keeping (diff -rq also reports files that exist on one
        # side only, so a hypr/ carrying the first-boot marker or a rofi/ with
        # its wallpaper link still counts as different and is still backed up).
        # Without this, anything another install script had already put in
        # place - or a re-run right after a clean install - left a *.backup-<stamp>
        # directory of identical content behind.
        # gtk-3.0 is compared with $HOME already filled into its bookmarks (the
        # expansion further down), which is what an up-to-date install holds.
        # Compared raw, it always differed, so every re-run moved it aside and
        # the Thunar bookmarks added since were left only in the backup.
        _cmp_src="$SCRIPT_DIR/config/$dir"
        _cmp_tmp=""
        if [ "$dir" = "gtk-3.0" ] && [ -f "$_cmp_src/bookmarks" ]; then
            _cmp_tmp=$(mktemp -d)
            cp -r "$_cmp_src/." "$_cmp_tmp/"
            sed -i "s|\$HOME|$HOME|g" "$_cmp_tmp/bookmarks"
            _cmp_src="$_cmp_tmp"
        fi
        # hypr likewise: compared against the repo copy with this machine's
        # state already in it - the monitor layout, the lock screen's generated
        # hyprlock-monitors.conf (rewritten at every login and lock), a chosen
        # animation preset and a video wallpaper. Everything below restores
        # those onto the fresh copy anyway, so without this the directory never
        # matched again and every re-run backed it up (~9 MB). When it does
        # match, the identical branch copies THIS tree, so nothing is reset.
        if [ "$dir" = "hypr" ] && [ -d "$HOME/.config/hypr" ]; then
            _live="$HOME/.config/hypr"
            _cmp_tmp=$(mktemp -d)
            cp -r "$_cmp_src/." "$_cmp_tmp/"
            for _f in monitors.lua workspaces.lua monitors.conf workspaces.conf hyprlock-monitors.conf; do
                if [ -f "$_live/$_f" ]; then
                    cp "$_live/$_f" "$_cmp_tmp/$_f"
                fi
            done
            if [ -f "$_live/UserConfigs/UserAnimations.lua" ] \
               && is_animation_preset "$_live/UserConfigs/UserAnimations.lua" "$_cmp_tmp/animations"; then
                cp "$_live/UserConfigs/UserAnimations.lua" "$_cmp_tmp/UserConfigs/UserAnimations.lua"
            fi
            copy_video_wallpaper "$_live/configs/Startup_Apps.lua" "$_cmp_tmp/configs/Startup_Apps.lua" || true
            _cmp_src="$_cmp_tmp"
        fi
        # xfce4: Thunar rewrites its last-* window and view keys in thunar.xml
        # (window size, column widths, last view) as it is used, so every re-run
        # after opening Thunar backed xfce4 up and reset them. Compared with the
        # live thunar.xml in place when the two differ only in those keys - and
        # then kept, as the tree the identical branch copies.
        _tx="xfconf/xfce-perchannel-xml/thunar.xml"
        if [ "$dir" = "xfce4" ] && [ -f "$HOME/.config/xfce4/$_tx" ] && [ -f "$_cmp_src/$_tx" ] \
           && cmp -s <(grep -v 'name="last-' "$_cmp_src/$_tx") <(grep -v 'name="last-' "$HOME/.config/xfce4/$_tx"); then
            _cmp_tmp=$(mktemp -d)
            cp -r "$_cmp_src/." "$_cmp_tmp/"
            cp "$HOME/.config/xfce4/$_tx" "$_cmp_tmp/$_tx"
            _cmp_src="$_cmp_tmp"
        fi
        # Runtime files this script seeds itself (all gitignored), left out of the
        # comparison: with them counted, hypr, quickshell, wallust, rofi and cava
        # were backed up on every re-run with no edits at all, ~12 MB each time.
        # The "identical" branch copies the repo over the existing directory, so
        # they stay in place - the repo has none of them to overwrite with. Not
        # monitors.lua/workspaces.lua: those ARE tracked, and the identical
        # branch would reset them to the templates with no backup to recover from.
        # hypr/wallust/, rofi/wallust/ and wallust/output/ hold only wallust
        # output and have no tracked file at all, so they are left out whole.
        _cmp_x=()
        case "$dir" in
            hypr)       _cmp_x=(.initial_startup_done .wallpaper_current .wallpaper_modified wallust) ;;
            quickshell) _cmp_x=(qml_color.json wallust-colors.json) ;;
            wallust)    _cmp_x=(output) ;;
            rofi)       _cmp_x=(wallust .current_wallpaper) ;;
            cava)       _cmp_x=(config) ;;
            # nwg-displays' saved profiles: its own state, not tracked (restored
            # from the backup by restore_state when the directory is replaced).
            nwg-displays) _cmp_x=(profiles active_profile.json) ;;
        esac
        # Never tracked anywhere (gitignored): python's bytecode caches next to
        # the dots' scripts would otherwise force a backup for nothing.
        _cmp_x+=(__pycache__)
        _cmp_args=()
        for _x in "${_cmp_x[@]}"; do
            _cmp_args+=(-x "$_x")
        done
        _same=no
        if [ -d "$HOME/.config/$dir" ] && diff -rq "${_cmp_args[@]}" "$_cmp_src" "$HOME/.config/$dir" >/dev/null 2>&1; then
            _same=yes
        fi
        if [ "$_same" = yes ]; then
            echo "  ${NOTE} Existing $dir is identical to the repo copy - no backup needed"
        elif [ -d "$HOME/.config/$dir" ]; then
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
                _replacing="$dir|$backup"
            else
                echo "  ${ERROR} Could not back up existing $dir - skipping it rather than merging over it"
                # The comparison copy (a full hypr tree, ~9 MB) was left in
                # $TMPDIR on this path before.
                if [ -n "$_cmp_tmp" ]; then
                    rm -rf "$_cmp_tmp"
                fi
                continue
            fi
        fi

        # Identical: copy the tree it was compared against (for hypr, the one
        # with this machine's state in it), so the templates never reset it.
        # Backed up: the plain repo copy - the state is restored from the backup
        # further down.
        _copy_src="$SCRIPT_DIR/config/$dir"
        if [ "$_same" = yes ] && [ -n "$_cmp_tmp" ]; then
            _copy_src="$_cmp_tmp"
            printf "  ${INFO} Copying $dir (repo copy with this machine's state kept) to $HOME/.config/\n"
        else
            printf "  ${INFO} Copying $dir from $SCRIPT_DIR/config/$dir to $HOME/.config/\n"
        fi
        mkdir -p "$HOME/.config/$dir"
        if cp -r "$_copy_src/." "$HOME/.config/$dir/" 2>&1; then
            echo "  ${OK} Copied $dir"
            if [ -n "${BACKUP_OF[$dir]:-}" ]; then
                restore_state "$dir" "${BACKUP_OF[$dir]}"
            fi
        else
            echo "  ${ERROR} Failed to copy $dir - keeping the version that was there"
            copy_failed+=("$dir")
            rollback_replace
        fi
        _replacing=""
        if [ -n "$_cmp_tmp" ]; then
            rm -rf "$_cmp_tmp"
        fi
    else
        printf "  ${WARN} $dir not found in $SCRIPT_DIR/config/, skipping\n"
    fi
done

# Create MangoHud's log folder
#
# Shift_L+F2 (toggle_logging) writes a CSV into MangoHud.conf's output_folder,
# and MangoHud opens that file with a plain ofstream - it never creates the
# folder, so with the folder missing the toggle writes nothing and says
# nothing. The tracked conf used to say /home/mentefria/mangologs, which was
# missing even on this machine and cannot be created on one with another user
# name; it says ~/mangologs now (MangoHud expands a leading ~ itself). Read from
# the deployed conf so the folder and the setting cannot drift apart.
_mh_logs="$(sed -n 's/^output_folder=//p' "$HOME/.config/MangoHud/MangoHud.conf" 2>/dev/null | tail -1)"
case "$_mh_logs" in "~/"*) _mh_logs="$HOME/${_mh_logs#\~/}" ;; esac
if [ -n "$_mh_logs" ]; then
    mkdir -p "$_mh_logs" && echo "  ${OK} MangoHud logs (Shift_L+F2) go to $_mh_logs"
fi

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
# (wallust_targets is defined at the top; restore_state already put a backed-up
# palette back as each directory was copied, so this mostly seeds a fresh install.)

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

# Deploy the herdr layout functions.
#
# Separate from the config_dirs loop for the same reason secrets.zsh is: that loop
# replaces whole directories, and ~/.config/zsh holds a filled-in secrets.zsh that
# must survive. This file is the opposite case - it is entirely repo-owned, carries
# no user data, and .zshrc sources it - so unlike secrets.zsh it is copied
# unconditionally and a newer version always wins.
if [ -f "$SCRIPT_DIR/config/zsh/herdr-layouts.zsh" ]; then
    mkdir -p "$HOME/.config/zsh"
    if cp "$SCRIPT_DIR/config/zsh/herdr-layouts.zsh" "$HOME/.config/zsh/herdr-layouts.zsh"; then
        echo "  ${OK} Copied herdr-layouts.zsh (hdl / hds / hdlm / hsl)"
    else
        echo "  ${ERROR} Failed to copy herdr-layouts.zsh"
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

# hypr/'s state from a backup (the first-boot marker, the active wallpaper, the
# monitor layout, the animation preset, the video wallpaper) was already put back
# by restore_state, right after the loop above copied hypr/.

# Deploy herdr's config and sounds INTO ~/.config/herdr, never replacing it.
#
# That directory is also where herdr keeps its runtime state (herdr.sock,
# herdr-client.sock, session.json, logs), so the backup-and-replace loop above
# would move the saved session and the running server's sockets into a
# .backup-<stamp> directory - clients could no longer find the server, and the
# next start came up with no session. Only the files the repo owns are touched;
# a config.toml that differs is backed up next to itself first.
printf "\n${INFO} Deploying herdr config...\n"
if [ -d "$SCRIPT_DIR/config/herdr" ]; then
    mkdir -p "$HOME/.config/herdr"
    _herdr_cfg="$HOME/.config/herdr/config.toml"
    # Compare against the template with this machine's $HOME filled in, which
    # is what an up-to-date install holds - otherwise every re-run backed up an
    # identical file just because its placeholders had been resolved.
    if [ -f "$_herdr_cfg" ] && ! sed "s#__HOME__#$HOME#g" "$SCRIPT_DIR/config/herdr/config.toml" | cmp -s - "$_herdr_cfg"; then
        cp "$_herdr_cfg" "$_herdr_cfg.backup-$BACKUP_STAMP" && echo "  ${NOTE} Backed up existing config.toml to config.toml.backup-$BACKUP_STAMP"
    fi
    if cp -r "$SCRIPT_DIR/config/herdr/." "$HOME/.config/herdr/"; then
        # [[keys.command]] entries need absolute paths, and a tracked dotfile
        # cannot carry one machine's $HOME, so the repo copy says __HOME__.
        # Resolved HERE, not only in install-scripts/herdr.sh: running
        # dotfiles-main.sh on its own (which the installer suggests as the retry
        # for a failed dots step) used to lay the template back down and leave
        # every tab and close-workspace bind pointing at __HOME__/.local/bin.
        if sed -i "s#__HOME__#$HOME#g" "$_herdr_cfg"; then
            echo "  ${OK} Copied herdr config (paths resolved to $HOME)"
        else
            echo "  ${ERROR} Could not resolve __HOME__ in $_herdr_cfg - the herdr tab binds will do nothing"
        fi
    else
        echo "  ${ERROR} Failed to copy herdr config"
        copy_failed+=("herdr")
    fi
fi

printf "\n${INFO} Setting default wallpaper...\n"
_default_src="$SCRIPT_DIR/wallpapers/$DEFAULT_WALLPAPER"
if [ -f "$HOME/.config/hypr/wallpaper_effects/.wallpaper_current" ]; then
    echo "  ${NOTE} Active wallpaper already present - left alone"
elif [ -f "$_default_src" ]; then
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

# Point the rofi background symlink at the deployed wallpaper.
#
# Outside the if/elif above on purpose. rofi/ is replaced wholesale by this
# script and the link is gitignored, so it has to be recreated on EVERY run -
# but it used to live in the elif branch, which a re-run never reaches (the
# active wallpaper is recovered from the hypr/ backup, so the first branch
# wins). Six rofi themes then had no background until the next wallpaper
# change relinked it.
if [ -f "$_default_src" ] || [ -n "${BACKUP_OF[rofi]:-}" ]; then
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
fi

if [ ${#copy_failed[@]} -gt 0 ]; then
    mkdir -p "$(dirname "$DOTS_FAILED")"
    printf '%s\n' "${copy_failed[@]}" >"$DOTS_FAILED"
    printf "\n${ERROR} Could not copy: ${copy_failed[*]} - the version already there was kept. Fix the error above, then re-run install-scripts/dotfiles-main.sh.\n\n"
    exit 1
fi
rm -f "$DOTS_FAILED"

printf "\n${OK} Dotfiles installation complete!\n\n"
