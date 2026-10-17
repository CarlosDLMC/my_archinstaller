pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

// The bar's cards from the keyboard, omarchy-style: one global shortcut per
// card (quickshell:card<Name>, bound to SUPER+CTRL+<letter> in Keybinds.lua).
// The card opens on the focused monitor with its first control focused, and
// CardKeys.qml drives it from there: arrows/Tab between controls, Enter or
// Space to press, Esc to close. The same shortcut again closes it.
//
// Only the routing lives here; each bar (shell.qml) opens its own widget.
Singleton {
    id: root

    signal toggleRequested(string card, string screenName)

    function request(card) {
        root.toggleRequested(card, Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "")
    }

    GlobalShortcut { appid: "quickshell"; name: "cardAudio";     description: "Audio card";         onPressed: root.request("audio") }
    GlobalShortcut { appid: "quickshell"; name: "cardNetwork";   description: "Network card";       onPressed: root.request("network") }
    GlobalShortcut { appid: "quickshell"; name: "cardPower";     description: "Power card";         onPressed: root.request("power") }
    GlobalShortcut { appid: "quickshell"; name: "cardBluetooth"; description: "Bluetooth card";     onPressed: root.request("bluetooth") }
    GlobalShortcut { appid: "quickshell"; name: "cardCalendar";  description: "Calendar";           onPressed: root.request("calendar") }
    GlobalShortcut { appid: "quickshell"; name: "cardWeather";   description: "Weather card";       onPressed: root.request("weather") }
    GlobalShortcut { appid: "quickshell"; name: "cardVpn";       description: "VPN card";           onPressed: root.request("vpn") }
    GlobalShortcut { appid: "quickshell"; name: "cardProfile";   description: "Power profile card"; onPressed: root.request("profile") }
    GlobalShortcut { appid: "quickshell"; name: "cardBattery";   description: "Battery card";       onPressed: root.request("battery") }
    GlobalShortcut { appid: "quickshell"; name: "cardAgent";     description: "Claude Code card";   onPressed: root.request("agent") }
}
