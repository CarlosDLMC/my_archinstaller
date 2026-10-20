#!/usr/bin/env bash
# rofi script mode behind the launcher's ФАЙЛЫ tab (SUPER D). The first screen
# picks where to search, ~ or /; then every file and folder under it is listed
# with fd and filtered by rofi. The launcher runs with -matching glob, so
# "*part*" and "*.pdf" work as patterns (plain words still match anywhere).
# Enter opens the pick with xdg-open, folders in the file manager; ".." goes
# back to the ~ / choice.
#
# Keys on a file (bound in config-launcher.rasi, which numbers them):
#   Shift+Enter  preview mode on/off (ROFI_RETV 11): while on, the file under
#                the cursor opens beside rofi, one at a time - see preview below
#   Ctrl+E       show it in Thunar, selected in its folder (ROFI_RETV 15)
#   Ctrl+C       copy its full path to the clipboard (ROFI_RETV 19)
#
# Also run as `RofiFiles.sh --hover ENTRY` by rofi's on-selection-changed hook
# (the SUPER D bind), for the preview.
#
# Stock rofi (if pkgbuilds/rofi's build failed or a repo update replaced it):
# Shift+Enter reloads the list with the row first instead of keeping it, and
# a row with an odd " or a trailing \ in its name shows rofi's parse-error
# box instead of a preview.

# Cache, toolchain and app-data folders, skipped in both searches. They hold
# most of the files under ~ (over a million) and nothing worth opening; delete
# a line to have that folder searched again.
excludes=(
    .git node_modules .cache .npm
    '**/.local/share' .rustup .cargo '**/go/pkg'
    .icons .themes .librewolf
    '**/.config/Slack' '**/.config/chromium' '**/.config/JetBrains'
)
# Kernel and runtime pseudo-filesystems plus btrfs snapshots, which would
# repeat the whole system. Only used when searching /.
root_excludes=(/proc /sys /dev /run /tmp /.snapshots)

# ROFI_DATA is "<share>;<root>", handed back by rofi on every call.
# The "+ .local/share" switch on the first screen searches .local/share too
# (Steam games and their soundtracks, Trash, flatpak apps: ~85k entries under
# ~ become ~410k); it holds while the launcher is open and is off again the
# next time. The root is the folder being listed, empty on the first screen;
# Shift+Enter needs it for the list's message, other keys to list it again.
share=${ROFI_DATA%%;*}
root=${ROFI_DATA#*;}

# Preview mode. $PV holds the PID of the rofi it is on for (ROFI_OUTSIDE is
# that PID in script mode); $PV.last the file on screen, $PV.hover the row the
# cursor last moved to, $PV.mpv the preview mpv's IPC socket, $PV.imv the
# preview imv's PID, $PV.img* the symlink imv was last handed.
# configs/WindowRules.lua does the window side: while RofiFilesPreview(true) is
# on, every new window floats beside the launcher without taking its keyboard
# or animating, and closes the one before; the mode ends when rofi closes.
PV=${XDG_RUNTIME_DIR:-/tmp}/rofi-files-preview

header() {
    printf '\0prompt\x1fФАЙЛЫ\n\0no-custom\x1ftrue\n\0use-hot-keys\x1ftrue\n'
    printf '\0data\x1f%s;%s\n' "$share" "$root"
}

list_roots() {
    root=
    header
    printf '\0message\x1fГде искать?\n'
    # permanent: shown whatever the filter, which a file list may hand over
    # (keep-filter below).
    printf '~   ДОМАШНЯЯ ПАПКА\0info\x1f%s\x1fpermanent\x1ftrue\n' "$HOME"
    printf '/   ВСЯ СИСТЕМА\0info\x1f/\x1fpermanent\x1ftrue\n'
    local mark=" "
    [[ $share ]] && mark=x
    printf '[%s] + .local/share\0info\x1fshare\x1fpermanent\x1ftrue\n' "$mark"
}

# The options of a file list, everything but its rows.
tree_header() {
    header
    # rofi reads keep-filter from the list on screen when a key is pressed:
    # set here, the typed filter outlives a reload of the list.
    printf '\0keep-filter\x1ftrue\n'
    if preview_here; then
        printf '\0message\x1f%s%s  ·  ПРОСМОТР  ·  Shift+Enter выключает\n' \
            "${root/#$HOME/\~}" "${share:+ + .local/share}"
    else
        printf '\0message\x1f%s%s  ·  *часть* или *.pdf  ·  Enter открывает\n' \
            "${root/#$HOME/\~}" "${share:+ + .local/share}"
    fi
}

# list_tree ROOT [ROW]: ROW comes first in the list (see keep_tree).
list_tree() {
    root=$1
    local x args=(--hidden --color never --absolute-path)
    for x in "${excludes[@]}"; do
        [[ $share && $x == '**/.local/share' ]] && continue
        args+=(--exclude "$x")
    done
    if [[ $root == / ]]; then
        for x in "${root_excludes[@]}"; do args+=(--exclude "$x"); done
    fi
    tree_header
    [[ $2 ]] && printf '%s\n' "$2"
    printf '..   НАЗАД\0info\x1fback\n'
    # Paths under home are shown as ~/..., shorter to read and to type.
    if [[ -z $2 ]]; then
        fd "${args[@]}" . "$root" 2>/dev/null | sed "s|^$HOME/|~/|"
    else
        fd "${args[@]}" . "$root" 2>/dev/null | sed "s|^$HOME/|~/|" |
            LC_ALL=C grep -vxF -- "$2"
    fi
}

# rofi is the patched build (pkgbuilds/rofi), which knows keep-list.
rofi_keeps_lists() {
    LC_ALL=C pacman -Qi rofi 2>/dev/null | grep -q '^Description .*keep-list'
}

# keep_tree ROW: the file list stays as it is - same rows, filter and cursor -
# and only its message changes. keep-list is the patched rofi's; stock rofi
# (its build failed, or a repo update replaced it) would close on an answer
# with no rows, so it gets the list again with ROW, the one Shift+Enter was
# pressed on, first: rofi puts the cursor on the first match, and ROW matches
# the filter. (keep-selection cannot do it: rofi maps it through the old list,
# and fd's order changes from run to run.)
keep_tree() {
    if rofi_keeps_lists; then
        tree_header
        printf '\0keep-list\x1ftrue\n'
    else
        list_tree "$root" "$1"
    fi
}

# A row's path as the shell needs it: ~/ expanded, no trailing / on folders.
path_of() {
    local p=${1%/}
    [[ $p == "~/"* ]] && p=$HOME/${p#\~/}
    printf '%s' "$p"
}

# Source code and config files open in nvim (in foot), not their default app.
# xdg-open goes by a file's contents, which call most code text/plain
# (omawrite), so the extension decides here; .txt and .md stay with omawrite,
# .html with the browser. A file with no extension counts when its contents
# say script or source (a shebang: file reports text/x-...).
code_exts=" c h cc cpp cxx hpp hh rs go py pyi rb pl pm lua js mjs cjs ts tsx
    jsx java kt kts scala swift zig nim dart php r jl hs ml ex exs erl clj el
    vim sh bash zsh fish ps1 sql qml css scss sass less vue svelte xml json
    jsonc toml yaml yml ini conf cfg rasi kdl nix cmake mk diff patch tex
    gradle proto graphql desktop service "
code_names=" Makefile makefile GNUmakefile Dockerfile Containerfile PKGBUILD
    Justfile justfile CMakeLists.txt .gitignore .gitconfig .editorconfig "

is_code() {
    local name=${1##*/} ext
    [[ -f $1 ]] || return 1
    [[ $code_names == *" $name "* || $name == .*rc || $name == .*profile ]] && return 0
    if [[ ${name#.} == *.* ]]; then
        ext=${name##*.}
        [[ $code_exts == *[[:space:]]"${ext,,}"[[:space:]]* ]]
    else
        [[ $(file -b --mime-type -- "$1" 2>/dev/null) == text/x-* ]]
    fi
}

open_path() {
    local p
    p=$(path_of "$1")
    # setsid keeps the app alive after rofi exits.
    if is_code "$p"; then
        setsid -f foot nvim -- "$p" >/dev/null 2>&1
    else
        setsid -f xdg-open "$p" >/dev/null 2>&1
    fi
}

# Thunar's daemon answers org.freedesktop.FileManager1, whose ShowItems opens
# the folder with the item selected; plain thunar on the folder if that fails.
show_in_folder() {
    local p uri
    p=$(path_of "$1")
    uri=$(python3 -c 'import pathlib, sys; print(pathlib.Path(sys.argv[1]).as_uri())' "$p") &&
        gdbus call --session --dest org.freedesktop.FileManager1 \
            --object-path /org/freedesktop/FileManager1 \
            --method org.freedesktop.FileManager1.ShowItems "['$uri']" "" >/dev/null 2>&1 ||
        setsid -f thunar "${p%/*}" >/dev/null 2>&1
}

copy_path() {
    # wl-copy stays behind to serve the clipboard; its output must not hold
    # rofi's pipe open, or rofi waits for it.
    path_of "$1" | wl-copy >/dev/null 2>&1
}

# The same screen again, for a key pressed on a row it does nothing for.
relist() {
    if [[ $root ]]; then list_tree "$root"; else list_roots; fi
}

# Preview mode is on for the rofi this script runs in.
preview_here() {
    [[ $(cat "$PV" 2>/dev/null) == "$ROFI_OUTSIDE" ]]
}

# The desktop file a file opens with, empty if it has none.
default_app() {
    xdg-mime query default "$(xdg-mime query filetype "$1" 2>/dev/null)" 2>/dev/null
}

# A desktop file (by id) is a web browser.
is_browser() {
    local d
    for d in "${XDG_DATA_HOME:-$HOME/.local/share}" /usr/local/share /usr/share \
             /var/lib/flatpak/exports/share; do
        if [[ -f $d/applications/$1 ]]; then
            grep -q '^Categories=.*WebBrowser' "$d/applications/$1"
            return
        fi
    done
    return 1
}

# Open a file (full path) as the preview, unless it is already on screen. The
# window it opens replaces the previous preview (WindowRules.lua).
preview_open() {
    local app
    [[ $(cat "$PV.last" 2>/dev/null) == "$1" ]] && return
    printf '%s' "$1" > "$PV.last"
    if is_code "$1"; then
        setsid -f foot nvim -- "$1" >/dev/null 2>&1
        return
    fi
    app=$(default_app "$1")
    # Never previewed in a web browser, nor with no default app (xdg-open
    # would fall back to one): it lands as a tab in the running browser, or as
    # a browser window the next preview would close.
    [[ $app ]] || return
    is_browser "$app" && return
    case $app in
        mpv.desktop) mpv_preview "$1" ;;
        imv.desktop) imv_preview "$1" ;;
        *)           setsid -f xdg-open "$1" >/dev/null 2>&1 ;;
    esac
}

# Images share one imv the same way: imv-msg (imv's IPC, by PID) opens the
# next image, selects it and closes the one before, so imv holds one image and
# its window stays. A new imv only when the saved PID is no imv any more (the
# first image, or its window was replaced by another app's). The imv launcher
# execs imv-wayland, so the PID started here is imv's own.
imv_preview() {
    local pid link f
    pid=$(cat "$PV.imv" 2>/dev/null)
    if [[ $pid && $(cat "/proc/$pid/comm" 2>/dev/null) == imv* ]]; then
        # imv splits a command at every space, quotes or not, and expands each
        # piece like a shell. So it is given a symlink with a plain name, never
        # the path: spaces, quotes and $(...) in file names stay inert.
        # Then "close" closes the current (old) image and imv moves on to the
        # new one. Not "goto -1" + "close 1": closing an image before the
        # current one leaves imv on an index past its list, showing nothing.
        link=$PV.img$RANDOM
        if ln -sfn -- "$1" "$link" && imv-msg "$pid" "open $link" &&
                imv-msg "$pid" "close"; then
            for f in "$PV".img*; do [[ $f == "$link" ]] || rm -f "$f"; done
            return
        fi
    fi
    setsid imv -- "$1" >/dev/null 2>&1 &
    printf '%s' "$!" > "$PV.imv"
}

# Sounds and videos share one mpv while its window is the preview: the next
# file goes into it over its IPC socket, $PV.mpv, so the window stays and mpv
# does not start up again. Only when nothing answers there - the first one, or
# its window was replaced by another app's and it quit - is mpv started:
# mpv.desktop's own command plus the socket and --keep-open. That keeps a file
# that ends on its last frame instead of closing the window, which would hand
# the keyboard to another window, away from the launcher (on-demand focus).
mpv_preview() {
    python3 - "$PV.mpv" "$1" 2>/dev/null <<'EOF' && return
import json, socket, sys
s = socket.socket(socket.AF_UNIX)
s.connect(sys.argv[1])
s.sendall((json.dumps({"command": ["loadfile", sys.argv[2]]}) + "\n").encode())
EOF
    setsid -f mpv --player-operation-mode=pseudo-gui --keep-open=yes \
        --input-ipc-server="$PV.mpv" -- "$1" >/dev/null 2>&1
}

toggle_preview() {
    local p
    if preview_here; then
        rm -f "$PV" "$PV.last" "$PV.hover" "$PV.mpv" "$PV.imv" "$PV".img*
        hyprctl eval 'RofiFilesPreview(false)' >/dev/null 2>&1
    else
        printf '%s' "$ROFI_OUTSIDE" > "$PV"
        rm -f "$PV.last"
        hyprctl eval 'RofiFilesPreview(true)' >/dev/null 2>&1
        p=$(path_of "$1")
        [[ -f $p ]] && preview_open "$p"
    fi
}

# rofi's on-selection-changed hook: the row the cursor moved to, in any tab.
# rofi runs it detached (its parent is PID 1), so the rofi it belongs to is
# the one $PV names, if that is still a running rofi.
hover() {
    local pid p
    pid=$(cat "$PV" 2>/dev/null) || return
    [[ $pid && $(cat "/proc/$pid/comm" 2>/dev/null) == rofi ]] || return
    p=$(path_of "$1")
    # Only files: not folders, "..", the first screen's rows or app names.
    [[ $p == /* && -f $p ]] || return
    # Holding an arrow key runs through many rows; only the one the cursor
    # rests on for 250 ms is opened.
    printf '%s' "$p" > "$PV.hover"
    sleep 0.25
    [[ $(cat "$PV.hover" 2>/dev/null) == "$p" ]] || return
    preview_open "$p"
}

# The patched rofi hands the row over as one argument; stock rofi splits it at
# spaces, so the words are joined back (a run of spaces comes back as one).
if [[ $1 == --hover ]]; then
    shift
    hover "$*"
    exit 0
fi

case ${ROFI_RETV:-0} in
    1|11)
        case $ROFI_INFO in
            back)  list_roots ;;
            share)
                if [[ $share ]]; then share=; else share=1; fi
                # The cursor goes back to the top row (this screen sets no
                # keep-selection), so Enter right after searches ~.
                list_roots
                ;;
            ?*)    list_tree "$ROFI_INFO" ;;
            *)
                if [[ $ROFI_RETV == 11 ]]; then
                    # Shift+Enter: preview mode on/off, list left as it is.
                    toggle_preview "$1"
                    keep_tree "$1"
                else
                    # Enter: no output, which closes rofi (and with it the
                    # preview).
                    open_path "$1"
                fi
                ;;
        esac
        ;;
    15) if [[ $ROFI_INFO ]]; then relist; else show_in_folder "$1"; fi ;;
    19) if [[ $ROFI_INFO ]]; then relist; else copy_path "$1"; fi ;;
    0)
        # A new launcher: preview mode left by an earlier one is gone with it.
        preview_here || rm -f "$PV" "$PV.last" "$PV.hover" "$PV.mpv" "$PV.imv" "$PV".img*
        list_roots
        ;;
    # rofi's other custom keys (Alt+1 and so on) do nothing here.
    *)  relist ;;
esac
