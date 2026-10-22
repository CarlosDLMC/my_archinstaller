pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The connected monitors, shared by the capture dialogs.
//
// Both grim and wf-recorder need an explicit output: with none, wf-recorder
// falls back to an interactive stdin prompt (and silently lands on the laptop
// panel), while grim captures the whole layout with the dead space between
// screens. So every capture here names a monitor.
Singleton {
    id: root

    // [{name, width, height, refresh, description}]: every enabled output,
    // its current mode in pixels. From wlr-randr (output management), which
    // has the refresh rate and the description that mango's IPC lacks.
    property var list: []

    readonly property bool multiple: list.length > 1

    function refresh() {
        proc.running = true
    }

    function focusedName() {
        if (Mango.focusedMonitorName)
            return Mango.focusedMonitorName
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
            "wlr-randr --json | jq -c '[.[] | select(.enabled) | . as $o " +
            "| ($o.modes[] | select(.current)) as $m " +
            "| {name: $o.name, width: $m.width, height: $m.height, " +
            "refresh: ($m.refresh|round), description: $o.description}]'"]
        stdout: SplitParser {
            onRead: data => {
                if (!data) return
                try { root.list = JSON.parse(data) } catch (e) { /* keep last good */ }
            }
        }
    }

    Component.onCompleted: refresh()
}
