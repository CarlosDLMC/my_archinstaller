pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// The connected monitors, shared by the capture dialogs.
//
// Both grim and wf-recorder need an explicit output: with none, wf-recorder
// falls back to an interactive stdin prompt (and silently lands on the laptop
// panel), while grim captures the whole layout with the dead space between
// screens. So every capture here names a monitor.
Singleton {
    id: root

    // [{name, width, height, refresh, description, focused}] in Hyprland order.
    property var list: []

    readonly property bool multiple: list.length > 1

    function refresh() {
        proc.running = true
    }

    function focusedName() {
        if (Hyprland.focusedMonitor && Hyprland.focusedMonitor.name)
            return Hyprland.focusedMonitor.name
        return list.length > 0 ? list[0].name : ""
    }

    // Resolve a remembered choice against the current layout: keep it while
    // that monitor is still plugged in, otherwise fall back to the focused one.
    function resolveTarget(name) {
        if (name && name !== "" && list.some(m => m.name === name))
            return name
        return focusedName()
    }

    Process {
        id: proc
        command: ["sh", "-c",
            "hyprctl -j monitors | jq -c '[.[] | {name, width, height, " +
            "refresh: (.refreshRate|round), description, focused}]'"]
        stdout: SplitParser {
            onRead: data => {
                if (!data) return
                try { root.list = JSON.parse(data) } catch (e) { /* keep last good */ }
            }
        }
    }

    Component.onCompleted: refresh()
}
