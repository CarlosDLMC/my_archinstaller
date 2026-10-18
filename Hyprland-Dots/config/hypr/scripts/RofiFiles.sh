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

# The "+ .local/share" switch on the first screen searches .local/share too
# (Steam games and their soundtracks, Trash, flatpak apps: ~85k entries under
# ~ become ~410k). rofi hands it back on every call through ROFI_DATA, so it
# holds while the launcher is open and is off again the next time.
share=$ROFI_DATA

header() {
    printf '\0prompt\x1fФАЙЛЫ\n\0no-custom\x1ftrue\n\0data\x1f%s\n' "$share"
}

list_roots() {
    header
    printf '\0message\x1fГде искать?\n'
    printf '~   ДОМАШНЯЯ ПАПКА\0info\x1f%s\n' "$HOME"
    printf '/   ВСЯ СИСТЕМА\0info\x1f/\n'
    local mark=" "
    [[ $share ]] && mark=x
    printf '[%s] + .local/share\0info\x1fshare\n' "$mark"
}

list_tree() {
    local root=$1 x
    local args=(--hidden --color never --absolute-path)
    for x in "${excludes[@]}"; do
        [[ $share && $x == '**/.local/share' ]] && continue
        args+=(--exclude "$x")
    done
    if [[ $root == / ]]; then
        for x in "${root_excludes[@]}"; do args+=(--exclude "$x"); done
    fi
    header
    printf '\0message\x1f%s%s  ·  *часть* или *.pdf  ·  Enter открывает\n' \
        "${root/#$HOME/\~}" "${share:+ + .local/share}"
    printf '..   НАЗАД\0info\x1fback\n'
    # Paths under home are shown as ~/..., shorter to read and to type.
    fd "${args[@]}" . "$root" 2>/dev/null | sed "s|^$HOME/|~/|"
}

if [[ $ROFI_RETV == 1 ]]; then
    case $ROFI_INFO in
        back)  list_roots ;;
        share)
            if [[ $share ]]; then share=; else share=1; fi
            # The cursor goes back to the top row (rofi 2.0 ignores
            # keep-selection here), so Enter right after searches ~.
            list_roots
            ;;
        ?*)    list_tree "$ROFI_INFO" ;;
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
