#!/usr/bin/env bash
# rofi script mode behind the launcher's ФАЙЛЫ tab (SUPER D). The first screen
# picks where to search, ~ or /; then every file and folder under it is listed
# with fd and filtered by rofi. The launcher runs with -matching glob, so
# "*part*" and "*.pdf" work as patterns (plain words still match anywhere).
# Enter opens the pick with xdg-open, folders in the file manager; ".." goes
# back to the ~ / choice.
#
# Keys on a file (bound in config-launcher.rasi, which numbers them):
#   Shift+Enter  open it and keep rofi open (ROFI_RETV 11)
#   Ctrl+E       show it in Thunar, selected in its folder (ROFI_RETV 15)
#   Ctrl+C       copy its full path to the clipboard (ROFI_RETV 19)

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
# Shift+Enter needs it to list the same folder again.
share=${ROFI_DATA%%;*}
root=${ROFI_DATA#*;}

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

# list_tree ROOT [ROW]: ROW is the entry Shift+Enter just opened, to keep the
# cursor on.
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
    header
    # rofi reads keep-filter from the list on screen when a key is pressed, so
    # it is set here: after Shift+Enter the typed filter stays.
    printf '\0keep-filter\x1ftrue\n'
    printf '\0message\x1f%s%s  ·  *часть* или *.pdf  ·  Enter открывает\n' \
        "${root/#$HOME/\~}" "${share:+ + .local/share}"
    # After Shift+Enter the opened row comes first. rofi puts the cursor on
    # the first match of the new list, and this row matches the filter, so
    # the cursor stays on it. (keep-selection/new-selection can't do it: rofi
    # maps them through the old list, and fd's order changes from run to run.)
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

# A row's path as the shell needs it: ~/ expanded, no trailing / on folders.
path_of() {
    local p=${1%/}
    [[ $p == "~/"* ]] && p=$HOME/${p#\~/}
    printf '%s' "$p"
}

open_path() {
    # setsid keeps the app alive after rofi exits.
    setsid -f xdg-open "$(path_of "$1")" >/dev/null 2>&1
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
                open_path "$1"
                # Enter: no output, which closes rofi. Shift+Enter: the list
                # again, the opened row first with the cursor on it.
                [[ $ROFI_RETV == 11 ]] && list_tree "$root" "$1"
                ;;
        esac
        ;;
    15) if [[ $ROFI_INFO ]]; then relist; else show_in_folder "$1"; fi ;;
    19) if [[ $ROFI_INFO ]]; then relist; else copy_path "$1"; fi ;;
    0)  list_roots ;;
    # rofi's other custom keys (Alt+1 and so on) do nothing here.
    *)  relist ;;
esac
