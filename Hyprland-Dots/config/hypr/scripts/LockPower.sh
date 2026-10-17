#!/usr/bin/env bash
# Shutdown from the lock screen, keyboard only: F1 (configs/Keybinds.lua).
#
# Hyprland's locked binds fire whether the session is locked or not, so F1 is
# bound non-consuming - apps still get their F1 - and this does nothing unless
# hyprlock is running.
#
# Two presses: the first arms it for ARM_SECS, and the lock screen shows a red
# notice above its footer (SovietLockGen.py polls `label`); a second F1 while
# armed powers off. A single stray key on a lock screen must not switch the
# machine off.
#
#   key     F1 pressed: arm it, or power off when it is already armed
#   label   the armed notice, or nothing

ARM_SECS=4
STATE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/lock-poweroff-armed"

armed() {
    [ -f "$STATE" ] || return 1
    [ $(( $(date +%s) - $(stat -c %Y "$STATE" 2>/dev/null || echo 0) )) -lt "$ARM_SECS" ]
}

case "${1:-}" in
    key)
        pidof -q hyprlock || exit 0
        if armed; then
            rm -f "$STATE"
            systemctl poweroff
        else
            touch "$STATE"
        fi
        ;;
    label)
        # Pango markup in a command's output is not read by hyprlock's config
        # parser, so the colour takes a single '#' here (not the config's '##').
        if armed; then
            echo '<span foreground="#C42B1C"><b>F1 ЕЩЁ РАЗ - ВЫКЛЮЧИТЬ</b></span>'
        else
            echo ''
        fi
        ;;
    *)
        echo "usage: LockPower.sh key|label" >&2
        exit 2
        ;;
esac
