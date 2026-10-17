#!/usr/bin/env bash
# Login reminder to bring the VPN up, sent once by UserConfigs/Startup_Apps.lua
# (it replaced a yad window that said the same in English).
#
# Critical urgency, so dunst's [critical_never_expires] rule keeps the card on
# screen with the red ТРЕВОГА stamp until it is clicked away. It only says so
# while it is true: nothing is sent when a WireGuard tunnel is already up, and a
# tunnel that comes up while the card is showing - NetworkManager autoconnecting
# a WireGuard profile, or a pick in the bar's VPN menu - turns it into a short
# confirmation instead.

tunnel_up() { [ -n "$(ip -br link show type wireguard 2>/dev/null)" ]; }

# dunst is started by the same hyprland.start handler and may not own the
# notification bus yet. A notification sent before it does makes D-Bus start
# dunst a second time, through systemd.
for _ in $(seq 1 50); do
    busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus \
        NameHasOwner s org.freedesktop.Notifications 2>/dev/null | grep -q true && break
    sleep 0.2
done

tunnel_up && exit 0

# -w keeps notify-send running until the card closes, so EOF on its output means
# the reminder was dismissed. -p prints the id first, which the replace needs.
# Once the card is replaced the waiter never hears it close - dunst sends the
# closed signal to whoever sent the card last - so every exit takes it down.
exec 3< <(notify-send -p -w -u critical "Товарищ, информация не защищена!" "Включите ВПН!")
waiter=$!
trap 'kill "$waiter" 2>/dev/null' EXIT
read -r id <&3 || exit 0

# Watch for a tunnel for ten minutes, two seconds at a time.
for _ in $(seq 1 300); do
    read -r -t 2 _ <&3
    (( $? > 128 )) || exit 0    # not a timeout: the card was closed
    if tunnel_up; then
        notify-send -r "$id" -u low -t 1500 "ВПН включён." "Информация защищена."
        exit 0
    fi
done
