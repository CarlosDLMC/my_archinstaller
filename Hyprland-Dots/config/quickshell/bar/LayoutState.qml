pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Keyboard-layout state for the GNOME-style switcher.
//
// Mirrors GNOME Shell's InputSourceManager: layouts are kept in a
// most-recently-used list, and the switch shortcut selects MRU[1] (the layout
// you were last on) rather than the next one in configured order. Repeated
// presses walk further down the MRU list; the selection is committed to the
// front of the list once you stop pressing, so a single tap toggles between
// your two most-used layouts the way Alt+Tab toggles between two windows.
Singleton {
    id: root

    // [{code, short, name}] in xkb (configured) order.
    property var layouts: []
    // Indices into `layouts`, most-recently-used first.
    property var mru: []
    // Index into `layouts` of the layout currently in effect.
    property int currentIndex: 0

    // While a switch session is running the MRU order is frozen, so the popup
    // does not reshuffle under you mid-browse (GNOME behaves the same).
    property bool sessionActive: false
    property int sessionPos: 0

    readonly property bool ready: layouts.length > 0

    // What the switcher renders: every layout, in MRU order.
    readonly property var switcherItems: {
        var out = []
        for (var i = 0; i < mru.length; i++)
            if (layouts[mru[i]]) out.push(layouts[mru[i]])
        return out
    }

    // Which entry of switcherItems is highlighted.
    readonly property int selectedPos: {
        if (sessionActive) return sessionPos
        for (var i = 0; i < mru.length; i++)
            if (mru[i] === currentIndex) return i
        return 0
    }

    signal showOsd()

    function moveToFront(list, value) {
        var out = [value]
        for (var i = 0; i < list.length; i++)
            if (list[i] !== value) out.push(list[i])
        return out
    }

    function activate(layoutIndex) {
        applyProc.command = ["hyprctl", "switchxkblayout", "all", String(layoutIndex)]
        applyProc.running = true
    }

    // Driven by the global shortcut.
    function switchNext() {
        if (!ready || mru.length < 2) return
        if (!sessionActive) {
            sessionActive = true
            sessionPos = 1              // MRU[1] == the layout you were last on
        } else {
            sessionPos = (sessionPos + 1) % mru.length
        }
        activate(mru[sessionPos])
        showOsd()
        commitTimer.restart()
    }

    // Settle the session: whatever is selected becomes most-recently-used.
    Timer {
        id: commitTimer
        interval: 1300
        onTriggered: {
            root.mru = root.moveToFront(root.mru, root.mru[root.sessionPos])
            root.sessionActive = false
            root.sessionPos = 0
        }
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "layoutNext"
        description: "Switch keyboard layout (most recently used)"
        onPressed: root.switchNext()
    }

    Process {
        id: applyProc
        command: ["true"]
    }

    // One-shot at startup: configured layouts + their display names.
    Process {
        id: loadProc
        command: ["sh", "-c", "$HOME/.config/quickshell/bar/scripts/layouts.py"]
        stdout: SplitParser {
            onRead: data => {
                if (!data) return
                var parsed
                try { parsed = JSON.parse(data) } catch (e) { return }
                root.layouts = parsed.layouts
                var order = []
                for (var i = 0; i < root.layouts.length; i++) order.push(i)
                // Seed MRU with the active layout in front.
                root.currentIndex = parsed.current
                root.mru = root.moveToFront(order, parsed.current)
            }
        }
        Component.onCompleted: running = true
    }

    // Track every layout change, however it was triggered. Because the MRU is
    // derived from what actually happened rather than from our own bookkeeping,
    // it cannot drift out of sync with the real layout.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "activelayout") return
            var comma = event.data.indexOf(",")
            if (comma < 0) return
            var displayName = event.data.substring(comma + 1)

            var idx = -1
            for (var i = 0; i < root.layouts.length; i++)
                if (root.layouts[i].name === displayName) { idx = i; break }
            if (idx < 0) return

            root.currentIndex = idx
            if (!root.sessionActive) {
                // Switched by something other than our shortcut (bar widget,
                // per-window switch): promote it and show the OSD anyway.
                root.mru = root.moveToFront(root.mru, idx)
                root.showOsd()
            }
        }
    }
}
