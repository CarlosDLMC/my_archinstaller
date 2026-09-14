import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import ".."

// Clipboard picker. Replaces the rofi one: a centred card in the bar's own
// style, with the entry list on the left and a large preview on the right, so
// a copied screenshot can be recognised before it is pasted.
//
// Shape follows Omarchy's clipboard plugin (omacom/omarchy, MIT, DHH) - split
// view, type to filter, keyboard-first - and the overlay plumbing follows
// ShotOsd, which is how every other full-screen dialog in this bar is built.
PanelWindow {
    id: osd

    property var modelData
    screen: modelData

    readonly property bool onFocusedMonitor:
        Hyprland.focusedMonitor && modelData
        && Hyprland.focusedMonitor.name === modelData.name

    readonly property bool shown: ClipboardState.dialogOpen && onFocusedMonitor

    property bool windowVisible: false
    readonly property int fadeMs: 160
    readonly property real uiScale: 1.35

    readonly property int cardW: Math.round(720 * uiScale)
    readonly property int cardH: Math.round(420 * uiScale)
    readonly property int pad: Math.round(18 * uiScale)
    readonly property int radius: Math.round(18 * uiScale)
    readonly property int rowH: Math.round(34 * uiScale)
    readonly property int titleSize: Math.round(13 * uiScale)
    readonly property int rowSize: Math.round(11 * uiScale)
    readonly property int hintSize: Math.round(9 * uiScale)

    visible: windowVisible

    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    onShownChanged: {
        if (shown) {
            windowVisible = true
            goneTimer.stop()
            Qt.callLater(function () { keyCatcher.forceActiveFocus() })
        } else {
            goneTimer.restart()
        }
    }

    Timer {
        id: goneTimer
        interval: osd.fadeMs
        onTriggered: osd.windowVisible = false
    }

    // Dim behind the card, and a click anywhere out there dismisses.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        opacity: osd.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: osd.fadeMs } }

        MouseArea {
            anchors.fill: parent
            onClicked: ClipboardState.close()
        }
    }

    FocusScope {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        // Keys.BeforeItem so navigation is seen before the text field consumes
        // it - the field holds focus the whole time so you can just type.
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function (event) {
            if (event.key === Qt.Key_Escape) {
                ClipboardState.close(); event.accepted = true
            } else if (event.key === Qt.Key_Down) {
                ClipboardState.move(1); event.accepted = true
            } else if (event.key === Qt.Key_Up) {
                ClipboardState.move(-1); event.accepted = true
            } else if (event.key === Qt.Key_PageDown) {
                ClipboardState.move(8); event.accepted = true
            } else if (event.key === Qt.Key_PageUp) {
                ClipboardState.move(-8); event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                ClipboardState.pick(ClipboardState.current); event.accepted = true
            } else if (event.key === Qt.Key_Delete) {
                // Same bindings the rofi picker used, so the muscle memory
                // carries over: Ctrl+Del removes one entry, Alt+Del wipes.
                if (event.modifiers & Qt.ControlModifier) {
                    ClipboardState.remove(ClipboardState.current); event.accepted = true
                } else if (event.modifiers & Qt.AltModifier) {
                    ClipboardState.wipe(); event.accepted = true
                }
            }
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: osd.cardW
            height: osd.cardH
            radius: osd.radius
            color: Theme.colBg
            border.width: 1
            border.color: Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.10)

            opacity: osd.shown ? 1 : 0
            scale: osd.shown ? 1 : 0.97
            Behavior on opacity { NumberAnimation { duration: osd.fadeMs } }
            Behavior on scale {
                NumberAnimation { duration: osd.fadeMs; easing.type: Easing.OutCubic }
            }

            // Clicks inside must not reach the dismiss layer behind.
            MouseArea { anchors.fill: parent }

            Column {
                anchors.fill: parent
                anchors.margins: osd.pad
                spacing: Math.round(10 * osd.uiScale)

                // ------------------------------------------------- search
                Item {
                    width: parent.width
                    height: Math.round(osd.titleSize * 2.0)

                    Text {
                        id: searchGlyph
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰅇"
                        color: Theme.colWhite
                        font.pixelSize: osd.titleSize + 3
                        font.family: Theme.fontFamily
                    }

                    TextInput {
                        id: search
                        anchors.left: searchGlyph.right
                        anchors.leftMargin: 10
                        anchors.right: countText.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.colWhite
                        font.pixelSize: osd.titleSize
                        font.family: Theme.fontFamily
                        clip: true
                        focus: true
                        onTextChanged: ClipboardState.filter = text

                        // Reset the box whenever the dialog opens.
                        Connections {
                            target: ClipboardState
                            function onDialogOpenChanged() {
                                if (ClipboardState.dialogOpen) search.text = ""
                            }
                        }

                        Text {
                            anchors.fill: parent
                            visible: search.text === ""
                            text: "Search clipboard…"
                            color: Theme.colMuted
                            font.pixelSize: osd.titleSize
                            font.family: Theme.fontFamily
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Text {
                        id: countText
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: ClipboardState.loading
                            ? "…"
                            : ClipboardState.filtered.length + " / " + ClipboardState.entries.length
                        color: Theme.colMuted
                        font.pixelSize: osd.hintSize
                        font.family: Theme.fontFamily
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.colMuted
                    opacity: 0.45
                }

                // ------------------------------------------- list + preview
                Item {
                    width: parent.width
                    height: parent.height - Math.round(osd.titleSize * 2.0)
                            - Math.round(osd.hintSize * 2.4) - 1
                            - Math.round(20 * osd.uiScale)

                    ListView {
                        id: list
                        width: Math.round(parent.width * 0.52)
                        height: parent.height
                        clip: true
                        spacing: 2
                        model: ClipboardState.filtered
                        currentIndex: ClipboardState.selectedIndex
                        highlightFollowsCurrentItem: true
                        boundsBehavior: Flickable.StopAtBounds

                        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                        delegate: Rectangle {
                            id: row
                            required property int index
                            required property var modelData

                            readonly property bool selected: index === ClipboardState.selectedIndex
                            readonly property bool isImage: modelData.type === "image"

                            width: list.width - 8
                            height: osd.rowH
                            radius: 6
                            color: selected
                                ? Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.14)
                                : (rowMouse.containsMouse
                                    ? Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.06)
                                    : "transparent")

                            // Ask for the picture only once the row exists, so
                            // scrolling decodes what you look at rather than
                            // all fifty screenshots up front.
                            Component.onCompleted: if (isImage) ClipboardState.requestThumb(modelData.id)

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 8

                                Item {
                                    width: osd.rowH - 10
                                    height: osd.rowH - 10
                                    anchors.verticalCenter: parent.verticalCenter

                                    Image {
                                        id: thumb
                                        anchors.fill: parent
                                        visible: row.isImage && status === Image.Ready
                                        source: row.isImage ? ClipboardState.thumbFor(row.modelData.id) : ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        smooth: true
                                        clip: true
                                        // Decode at thumbnail size: the stored
                                        // image can be 2560x1440, and holding
                                        // that per row is pointless.
                                        sourceSize.width: 96
                                        sourceSize.height: 96
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: !thumb.visible
                                        text: row.isImage ? "󰋩" : "󰦨"
                                        color: Theme.colMuted
                                        font.pixelSize: osd.rowSize + 2
                                        font.family: Theme.fontFamily
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - (osd.rowH - 10) - 16
                                    text: row.isImage
                                        ? "Image  " + row.modelData.w + "×" + row.modelData.h
                                          + "  ·  " + row.modelData.size
                                        : row.modelData.preview
                                    color: row.selected ? Theme.colWhite : Theme.colDim
                                    font.pixelSize: osd.rowSize
                                    font.family: Theme.fontFamily
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                            }

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    ClipboardState.selectedIndex = row.index
                                    ClipboardState.pick(row.modelData)
                                }
                            }
                        }
                    }

                    // ------------------------------------------- preview
                    Rectangle {
                        anchors.left: list.right
                        anchors.leftMargin: osd.pad
                        anchors.right: parent.right
                        height: parent.height
                        radius: 10
                        color: Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.04)

                        readonly property var entry: ClipboardState.current
                        readonly property bool isImage: entry && entry.type === "image"

                        Component.onCompleted:
                            if (isImage) ClipboardState.requestThumb(entry.id)
                        onEntryChanged:
                            if (isImage) ClipboardState.requestThumb(entry.id)

                        Image {
                            id: bigImage
                            anchors.fill: parent
                            anchors.margins: 10
                            visible: parent.isImage && status === Image.Ready
                            source: parent.isImage ? ClipboardState.thumbFor(parent.entry.id) : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            smooth: true
                            sourceSize.width: 900
                            sourceSize.height: 700
                        }

                        Text {
                            anchors.fill: parent
                            anchors.margins: 12
                            visible: parent.entry !== null && !parent.isImage
                            text: parent.entry ? parent.entry.preview : ""
                            color: Theme.colDim
                            font.pixelSize: osd.rowSize
                            font.family: Theme.fontFamily
                            wrapMode: Text.Wrap
                            elide: Text.ElideRight
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: parent.isImage && !bigImage.visible
                            text: "󰋩"
                            color: Theme.colMuted
                            font.pixelSize: Math.round(48 * osd.uiScale)
                            font.family: Theme.fontFamily
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: parent.entry === null
                            text: ClipboardState.loading ? "Reading history…" : "Nothing matches"
                            color: Theme.colMuted
                            font.pixelSize: osd.rowSize
                            font.family: Theme.fontFamily
                        }
                    }
                }

                // -------------------------------------------------- hints
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "↑↓ move   ·   Enter paste   ·   Ctrl+Del remove   ·   Alt+Del wipe   ·   Esc close"
                    color: Theme.colMuted
                    font.pixelSize: osd.hintSize
                    font.family: Theme.fontFamily
                }
            }
        }
    }
}
