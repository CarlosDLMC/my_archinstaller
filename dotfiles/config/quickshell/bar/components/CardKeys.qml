import QtQuick

// Keyboard driving inside a bar card (opened by BarCards.qml). The cards' controls -
// ConsoleButton, ConsoleRow, VolumeSlider - take focus; this walks between
// them. A key the focused control does not use bubbles up to here:
//
//   Up/Down, Left/Right, Tab/Shift+Tab   previous / next control
//   Esc                                  close the card
//
// Enter/Space press the focused control and Left/Right set a fader's level;
// the control handles those itself, so they never reach this.
FocusScope {
    id: keys

    signal dismissed()

    // A card is a window of its own, so its focus chain holds only its own
    // controls (and wraps around at the ends).
    function step(forward) {
        var cur = keys.Window.activeFocusItem
        // A row of a list that scrolls walks its own list, and leaves it for
        // the control beyond (ConsoleRow.qml).
        if (cur && typeof cur.stepInList === "function" && cur.stepInList(forward ? 1 : -1))
            return
        var next = (cur ? cur : keys).nextItemInFocusChain(forward)
        if (next && next !== cur) {
            // Into a list that scrolls (ConsoleRow) from outside it: its first
            // row going forward, its last going back. The chain only holds the
            // rows the list has built, in no set order once it has scrolled.
            if (typeof next.entryRow === "function"
                    && !(cur && cur.ListView && cur.ListView.view === next.ListView.view)) {
                var r = next.entryRow(forward)
                if (r)
                    next = r
            }
            next.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason)
        }
    }

    // The first control, so the cursor is visible as soon as the card opens.
    // A card with nothing to press (the weather, the agents) keeps the focus
    // on this scope, where Esc still works.
    function focusFirst() {
        var first = keys.nextItemInFocusChain(true)
        if (first && first !== keys)
            first.forceActiveFocus(Qt.TabFocusReason)
        else
            keys.forceActiveFocus()
    }

    // Tab and Shift+Tab come here first: a control that takes focus would
    // otherwise move it on its own (Qt does that for activeFocusOnTab), past
    // step() and its lists. The same chain, so nothing else changes.
    Shortcut {
        sequences: ["Tab"]
        onActivated: keys.step(true)
    }
    Shortcut {
        sequences: ["Backtab", "Shift+Tab", "Shift+Backtab"]
        onActivated: keys.step(false)
    }

    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_Escape:
            keys.dismissed()
            break
        case Qt.Key_Down:
        case Qt.Key_Right:
        case Qt.Key_Tab:
            keys.step(true)
            break
        case Qt.Key_Up:
        case Qt.Key_Left:
        case Qt.Key_Backtab:
            keys.step(false)
            break
        default:
            return
        }
        event.accepted = true
    }
}
