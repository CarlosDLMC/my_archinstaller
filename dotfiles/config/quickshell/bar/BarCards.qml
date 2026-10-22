pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The bar's cards from the keyboard, omarchy-style: one IPC call per card,
// `qs -c bar ipc call cards toggle <card>`, bound to SUPER+CTRL+<letter> in
// ~/.config/mango/keybinds.conf. The card opens on the focused monitor with its
// first control focused, and CardKeys.qml drives it from there: arrows/Tab
// between controls, Enter or Space to press, Esc to close. The same keys
// again close it.
//
// Only the routing lives here; each bar (shell.qml) opens its own widget.
Singleton {
    id: root

    signal toggleRequested(string card, string screenName)

    function request(card) {
        root.toggleRequested(card, Mango.focusedMonitorName)
    }

    // audio, network, power, bluetooth, calendar, weather, vpn, profile,
    // battery, agent
    IpcHandler {
        target: "cards"
        function toggle(card: string): void { root.request(card) }
    }
}
