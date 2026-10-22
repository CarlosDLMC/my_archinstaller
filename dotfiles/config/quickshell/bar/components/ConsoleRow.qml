import QtQuick
import QtQuick.Layouts
import ".."

// A row on a console plate that can be picked - a network, a device, a tunnel,
// a profile. A lamp says which one is in use (lit) and the name goes white;
// the rest stay grey. Hover lifts the row a shade off the plate. Anything that
// has to sit at the right edge (a flag, a lock, a spinner) goes in as a child.
Rectangle {
    id: row

    property bool lit: false
    property color tint: Theme.colAccent
    property bool showLamp: true
    property string icon: ""
    property string label: ""
    property string detail: ""
    property color detailColor: Theme.colDim
    property int fontSize: Theme.fontSize - 3
    property bool interactive: true
    default property alias trailing: extra.data
    signal picked()

    // Keyboard (CardKeys.qml): a pickable row takes focus, Enter or Space
    // picks it. Focus looks like hover, plus a white outline.
    activeFocusOnTab: interactive && visible
    readonly property bool hot: (area.containsMouse && interactive) || activeFocus
    border.width: activeFocus ? 2 : 0
    border.color: Theme.colWhite
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            row.picked()
            event.accepted = true
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
            if (row.stepInList(1))
                event.accepted = true
        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Left || event.key === Qt.Key_Backtab) {
            if (row.stepInList(-1))
                event.accepted = true
        }
    }

    // In a list that scrolls (more networks, devices or tunnels than fit), the
    // keys walk the rows here: a ListView only builds the rows in view, so the
    // card's focus chain (CardKeys) never reached the ones below. The list
    // scrolls to the next pickable row and it takes the focus. Past either end
    // the focus goes to the nearest control outside the list - not to the
    // row's neighbour in the focus chain, which can be another row once the
    // list has scrolled (it builds and drops rows as it goes).
    function stepInList(step) {
        var v = ListView.view
        if (!v)
            return false
        for (var n = index + step; n >= 0 && n < v.count; n += step) {
            v.positionViewAtIndex(n, ListView.Contain)
            var it = v.itemAtIndex(n)
            if (it && it.activeFocusOnTab) {
                it.forceActiveFocus(step > 0 ? Qt.TabFocusReason : Qt.BacktabFocusReason)
                return true
            }
        }
        var out = row
        for (var i = 0; i < 1000; i++) {
            out = out.nextItemInFocusChain(step > 0)
            if (!out || out === row)
                return false
            if (!row.inList(out, v)) {
                // Straight into the next list, if that is what comes after.
                if (typeof out.entryRow === "function") {
                    var r = out.entryRow(step > 0)
                    if (r)
                        out = r
                }
                out.forceActiveFocus(step > 0 ? Qt.TabFocusReason : Qt.BacktabFocusReason)
                return true
            }
        }
        return false
    }
    // The row the keys land on coming into this list from outside it: its
    // first pickable row going forward, its last going back (CardKeys.qml).
    function entryRow(forward) {
        var v = ListView.view
        if (!v)
            return null
        var step = forward ? 1 : -1
        for (var n = forward ? 0 : v.count - 1; n >= 0 && n < v.count; n += step) {
            v.positionViewAtIndex(n, ListView.Contain)
            var it = v.itemAtIndex(n)
            if (it && it.activeFocusOnTab)
                return it
        }
        return null
    }
    function inList(item, v) {
        for (var p = item; p; p = p.parent)
            if (p === v)
                return true
        return false
    }
    // However the focus got here, the row is scrolled into view, and the
    // list's current row follows it: the ListView's own Up/Down (a key no row
    // takes) starts from there, not from wherever it was left.
    onActiveFocusChanged: {
        if (activeFocus && ListView.view) {
            ListView.view.currentIndex = index
            ListView.view.positionViewAtIndex(index, ListView.Contain)
        }
    }

    width: parent ? parent.width : 0
    implicitHeight: Math.round(fontSize * 1.75)
    radius: 4
    color: row.hot ? Qt.lighter(Theme.colPlate, 1.6) : "transparent"
    Behavior on color { ColorAnimation { duration: 110 } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        spacing: 8

        ConsoleLamp {
            visible: row.showLamp
            lit: row.lit
            tint: row.tint
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            visible: row.icon !== ""
            text: row.icon
            color: row.lit || row.hot ? Theme.colWhite : Theme.colGrey
            font.pixelSize: row.fontSize
            font.family: Theme.fontFamily
            horizontalAlignment: Text.AlignHCenter
            Layout.preferredWidth: row.fontSize + 2
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            // From outside (names, titles, SSIDs): plain, never rich text - an <img> in it was fetched.
            textFormat: Text.PlainText
            text: row.label
            color: row.lit || row.hot ? Theme.colWhite : Theme.colGrey
            font.pixelSize: row.fontSize
            font.family: Theme.fontFamily
            font.bold: row.lit
            elide: Text.ElideRight
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            visible: row.detail !== ""
            // From outside too, on some rows (a model name, a device state).
            textFormat: Text.PlainText
            text: row.detail
            color: row.detailColor
            font.pixelSize: row.fontSize - 2
            font.family: Theme.fontFamily
            Layout.alignment: Qt.AlignVCenter
        }

        Row {
            id: extra
            visible: children.length > 0
            spacing: 6
            Layout.alignment: Qt.AlignVCenter
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: row.interactive
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.picked()
    }
}
