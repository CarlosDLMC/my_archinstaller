pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

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
    // The layout last chosen here, and the one asked of mango and not yet
    // reported back (-1: none). Every switch in this setup goes through this
    // bar - no xkb toggle option is set. A mango config reload (a wallpaper
    // change, blur, game mode, the touchpad toggle, setoption) rebuilds the
    // keymap on the first layout, mostly without a word: the config's exec=
    // line calls restore() after each one, and a reset that does get reported
    // is put back here as well.
    property int chosenIndex: 0
    property int pendingIndex: -1

    // While a switch session is running the MRU order is frozen, so the popup
    // does not reshuffle under you mid-browse (GNOME behaves the same).
    property bool sessionActive: false
    property int sessionPos: 0

    readonly property bool ready: layouts.length > 0

    // OSD timings live here so the commit can be sequenced against them: the
    // MRU reorder must land only after the popup has fully faded, otherwise
    // the squares visibly reshuffle on screen.
    readonly property int osdVisibleMs: 1300
    readonly property int osdFadeMs: 200

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
    signal hideOsd()

    // While the pointer is over the popup it stays put: the auto-hide and the
    // MRU commit are both suspended, so it cannot vanish or reshuffle under
    // the cursor.
    property bool osdHeld: false

    function holdOsd() {
        osdHeld = true
        commitTimer.stop()
    }

    function releaseOsd() {
        osdHeld = false
        commitTimer.restart()
    }

    // Clicking an entry in the popup picks it directly.
    function selectPos(pos) {
        if (!ready || pos < 0 || pos >= mru.length) return
        sessionActive = true
        sessionPos = pos
        activate(mru[pos])
        hideOsd()
        releaseOsd()
    }

    function moveToFront(list, value) {
        var out = [value]
        for (var i = 0; i < list.length; i++)
            if (list[i] !== value) out.push(list[i])
        return out
    }

    // mango numbers the layouts from 1 (0 means "next").
    function activate(layoutIndex) {
        chosenIndex = layoutIndex
        pendingIndex = layoutIndex
        Mango.dispatch("switch_keyboard_layout," + (layoutIndex + 1))
    }

    // The bar's layout label: the next layout in configured order.
    function cycle() {
        if (!ready) return
        activate((currentIndex + 1) % layouts.length)
    }

    // Driven by the keybinds (LayoutNext.sh -> `qs -c bar ipc call layout next`).
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

    // Settle the session once the popup is off screen. Promoting currentIndex
    // covers both paths: after activate() the activelayout event has already
    // pointed it at whatever layout ended up in effect.
    Timer {
        id: commitTimer
        interval: root.osdVisibleMs + root.osdFadeMs + 250
        onTriggered: {
            root.mru = root.moveToFront(root.mru, root.currentIndex)
            root.sessionActive = false
            root.sessionPos = 0
        }
    }

    // next: SUPER+SPACE and both ALT+SHIFT orders, through LayoutNext.sh.
    // restore: after every config reload (mango/startup.conf).
    IpcHandler {
        target: "layout"
        function next(): void { root.switchNext() }
        function restore(): void {
            if (root.ready) root.activate(root.chosenIndex)
        }
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
                root.chosenIndex = parsed.current
                root.mru = root.moveToFront(order, parsed.current)
            }
        }
        Component.onCompleted: running = true
    }

    // Track every layout change, however it was triggered. Because the MRU is
    // derived from what actually happened rather than from our own bookkeeping,
    // it cannot drift out of sync with the real layout. mango reports only real
    // switches of the keyboard group: virtual keyboards (wtype, Handy) have
    // their own keymaps and never show up here.
    Connections {
        target: Mango
        function onKeyboardLayoutChanged() {
            var displayName = Mango.keyboardLayout
            if (!displayName) return

            var idx = -1
            for (var i = 0; i < root.layouts.length; i++)
                if (root.layouts[i].name === displayName) { idx = i; break }
            if (idx < 0) return
            if (idx === root.pendingIndex) {
                root.pendingIndex = -1
            } else if (idx !== root.chosenIndex && !root.sessionActive) {
                // A reload's reset: put the chosen layout back, no OSD.
                root.activate(root.chosenIndex)
                return
            }
            // The stream starts with the layout in effect, which layouts.py
            // already reported: not a switch.
            if (idx === root.currentIndex && !root.sessionActive) return

            root.currentIndex = idx
            if (!root.sessionActive) {
                // Switched by something other than our shortcut (the bar's
                // label). Show the OSD and let commitTimer do the promotion
                // later, so this path cannot reshuffle a visible popup either.
                root.showOsd()
                commitTimer.restart()
            }
        }
    }
}
