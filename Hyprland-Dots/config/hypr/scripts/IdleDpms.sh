#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# Decide whether an idle timeout should actually blank the screen.
#
# The Soviet TUI lock screen is meant to be readable across the room, so it
# stays lit - but only while plugged in. On battery, blanking matters more
# than looking good, and the lock screen would otherwise hold the display on
# all night (the panel plus a per-second clock refresh).
#
# Called from hypridle.conf's "Turn off screen" listener. Kept as a script
# rather than inlined because hypridle uses { } to delimit listener blocks,
# so a braced shell compound in a value is asking for a parser argument.
#
# Blank unless: the session is locked AND we are on AC.

# Power supply name varies by machine; this ThinkPad uses AC.
on_ac() {
    local dev value
    for dev in AC AC0 ACAD ADP0 ADP1; do
        [ -r "/sys/class/power_supply/$dev/online" ] || continue
        value=$(<"/sys/class/power_supply/$dev/online")
        [ "$value" = "1" ] && return 0
        return 1
    done
    # No AC device at all: most likely a desktop, where blanking on idle is
    # still the sane default.
    return 1
}

HYPRCTL="${HYPRCTL:-hyprctl}"

if pidof hyprlock >/dev/null 2>&1 && on_ac; then
    exit 0
fi

"$HYPRCTL" dispatch dpms off
