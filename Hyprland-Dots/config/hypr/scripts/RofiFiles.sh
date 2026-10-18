#!/usr/bin/env bash
# rofi script mode behind the launcher's ФАЙЛЫ tab (SUPER D). The first screen
# picks where to search, ~ or /; then every file and folder under it is listed
# with fd and filtered by rofi. The launcher runs with -matching glob, so
# "*part*" and "*.pdf" work as patterns (plain words still match anywhere).
# Enter opens the pick with xdg-open, folders in the file manager; ".." goes
# back to the ~ / choice.

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

header() {
    printf '\0prompt\x1fФАЙЛЫ\n\0no-custom\x1ftrue\n\0data\x1f%s\n' "$1"
}

list_roots() {
    header ""
    printf '\0message\x1fГде искать?\n'
    printf '~   ДОМАШНЯЯ ПАПКА\0info\x1f%s\n' "$HOME"
    printf '/   ВСЯ СИСТЕМА\0info\x1f/\n'
}

list_tree() {
    local root=$1 x
    local args=(--hidden --color never --absolute-path)
    for x in "${excludes[@]}"; do args+=(--exclude "$x"); done
    if [[ $root == / ]]; then
        for x in "${root_excludes[@]}"; do args+=(--exclude "$x"); done
    fi
    header "$root"
    printf '\0message\x1f%s  ·  *часть* или *.pdf  ·  Enter открывает\n' "${root/#$HOME/\~}"
    printf '..   НАЗАД\0info\x1fback\n'
    # Paths under home are shown as ~/..., shorter to read and to type.
    fd "${args[@]}" . "$root" 2>/dev/null | sed "s|^$HOME/|~/|"
}

if [[ $ROFI_RETV == 1 ]]; then
    case $ROFI_INFO in
        back) list_roots ;;
        ?*)   list_tree "$ROFI_INFO" ;;
        *)
            path=$1
            [[ $path == "~/"* ]] && path=$HOME/${path#\~/}
            # No output closes rofi; setsid keeps the app alive after it exits.
            setsid -f xdg-open "$path" >/dev/null 2>&1
            ;;
    esac
else
    list_roots
fi
