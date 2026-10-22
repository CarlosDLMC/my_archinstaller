import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

// GNOME-style keyboard-layout switcher OSD, dressed as a control console like
// the bar's cards.
//
// Shows every configured layout in most-recently-used order, centred on the
// focused monitor: one push-button key per layout on a recessed plate, the
// selected one pushed in and lit in the wallpaper's accent, its Russian code
// on the key (АНГ, РУС - the bar's names) and a lamp and its name under it.
// The pointer can hover to preview and click to pick, and the popup holds
// still for as long as the cursor is on it.
PanelWindow {
    id: osd

    property var modelData
    screen: modelData

    property bool shown: false          // drives the fade
    property bool windowVisible: false  // stays true through the fade-out

    readonly property int visibleMs: LayoutState.osdVisibleMs
    readonly property int fadeMs: LayoutState.osdFadeMs

    // Overall size of the popup. Every dimension below scales from this one
    // number, so resizing is a single edit.
    readonly property real uiScale: 1.4

    readonly property int tileSize:    Math.round(76 * uiScale)
    readonly property int tileRadius:  Math.round(5  * uiScale)
    readonly property int codeSize:    Math.round(28 * uiScale)
    readonly property int nameSize:    Math.round(13 * uiScale)
    readonly property int nameWidth:   Math.round(96 * uiScale)
    readonly property int itemSpacing: Math.round(8  * uiScale)
    readonly property int rowSpacing:  Math.round(10 * uiScale)
    readonly property int platePad:    Math.round(12 * uiScale)
    readonly property int panelPad:    Math.round(28 * uiScale)
    readonly property int panelRadius: Math.round(12 * uiScale)

    // The bar's names for the layouts (KeyboardLayoutWidget), and theirs in
    // full. Anything not listed shows as xkb gives it.
    function codeOf(item) {
        return ({ "us": "АНГ", "ru": "РУС", "es": "ИСП" })[item.code]
               || (item.short || "").toUpperCase()
    }
    function nameOf(item) {
        return ({ "English (US)": "АНГЛИЙСКАЯ", "Russian": "РУССКАЯ", "Spanish": "ИСПАНСКАЯ" })[item.name]
               || (item.name || "").toUpperCase()
    }

    // Entry under the pointer, or -1. Hovering only previews the highlight;
    // the layout changes on click, as GNOME's switcher does.
    property int hoveredPos: -1

    readonly property var items: LayoutState.switcherItems
    readonly property int selected: LayoutState.selectedPos

    readonly property bool onFocusedMonitor:
        !!modelData && Mango.focusedMonitorName === modelData.name

    visible: windowVisible && onFocusedMonitor && items.length > 0

    // Without a mask the entire surface swallows pointer events at screen
    // centre for as long as the popup is up. Restrict input to the panel.
    mask: Region { item: panel }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    // No anchors => layer-shell centres the surface on the output.
    implicitWidth: panel.width + 40
    implicitHeight: panel.height + 40

    Connections {
        target: LayoutState

        function onShowOsd() {
            osd.windowVisible = true
            osd.shown = true
            hideTimer.restart()
            goneTimer.stop()
        }

        // Dismiss immediately (a click picked an entry).
        function onHideOsd() {
            osd.hoveredPos = -1
            osd.shown = false
            hideTimer.stop()
            goneTimer.restart()
        }
    }

    Timer {
        id: hideTimer
        interval: osd.visibleMs
        onTriggered: { osd.shown = false; goneTimer.restart() }
    }

    Timer {
        id: goneTimer
        interval: osd.fadeMs
        onTriggered: osd.windowVisible = false
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: body.width + osd.panelPad
        height: body.height + osd.panelPad
        radius: osd.panelRadius
        color: Qt.rgba(Theme.colBg.r, Theme.colBg.g, Theme.colBg.b, 0.96)

        opacity: osd.shown ? 1.0 : 0.0
        scale: osd.shown ? 1.0 : 0.94
        Behavior on opacity { NumberAnimation { duration: osd.fadeMs; easing.type: Easing.OutCubic } }
        Behavior on scale   { NumberAnimation { duration: osd.fadeMs; easing.type: Easing.OutCubic } }

        Column {
            id: body
            anchors.centerIn: parent
            spacing: osd.itemSpacing

            ConsoleCaption {
                text: "РАСКЛАДКА"
                fontSize: osd.nameSize
            }

            ConsolePlate {
                width: row.width + 2 * pad
                pad: osd.platePad

                Row {
                    id: row
                    spacing: osd.rowSpacing

                    Repeater {
                        model: osd.items

                        Column {
                            id: entry
                            required property var modelData
                            required property int index

                            readonly property bool isSelected:
                                index === (osd.hoveredPos >= 0 ? osd.hoveredPos : osd.selected)

                            width: osd.nameWidth
                            spacing: osd.itemSpacing

                            // The key: up, it stands on the plate with a dark
                            // lower edge; selected, it is pushed in and lit.
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: osd.tileSize
                                height: osd.tileSize
                                radius: osd.tileRadius
                                color: entry.isSelected ? Theme.colAccent : Qt.lighter(Theme.colPlate, 1.25)
                                Behavior on color { ColorAnimation { duration: 120 } }

                                Rectangle {
                                    visible: !entry.isSelected
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: Math.round(3 * osd.uiScale)
                                    radius: parent.radius
                                    color: Qt.rgba(0, 0, 0, 0.45)
                                }

                                Text {
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: entry.isSelected ? 0 : -2
                                    text: osd.codeOf(entry.modelData)
                                    color: entry.isSelected ? Theme.colBg : Theme.colGrey
                                    font.family: Theme.fontFamily
                                    font.pixelSize: osd.codeSize
                                    font.bold: true
                                }
                            }

                            // A lamp and the layout's name under its key.
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: Math.round(5 * osd.uiScale)

                                ConsoleLamp {
                                    anchors.verticalCenter: parent.verticalCenter
                                    lit: entry.isSelected
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.min(implicitWidth, osd.nameWidth - 20)
                                    elide: Text.ElideRight
                                    text: osd.nameOf(entry.modelData)
                                    color: entry.isSelected ? Theme.colWhite : Theme.colGrey
                                    font.family: Theme.fontFamily
                                    font.pixelSize: osd.nameSize
                                    font.bold: true
                                    font.letterSpacing: 1
                                }
                            }
                        }
                    }
                }
            }
        }

        // One mouse area over the whole panel, hit-testing the entry under the
        // cursor. Overlapping per-entry areas would make enter/exit unreliable
        // and would fight the Row's layout.
        MouseArea {
            id: panelMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: osd.hoveredPos >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor

            // Nearest entry to the cursor. Clamped rather than returning -1
            // off-entry, so sliding across the row never drops the highlight
            // back to the current selection in the gaps between tiles.
            function posAt(mx) {
                if (osd.items.length === 0) return -1
                var step = osd.nameWidth + osd.rowSpacing
                // The row sits inside the plate now, so map the x into it.
                var i = Math.floor(row.mapFromItem(panelMouse, mx, 0).x / step)
                return Math.max(0, Math.min(osd.items.length - 1, i))
            }

            onEntered: {
                // Freeze: no auto-hide and no MRU commit while pointed at.
                hideTimer.stop()
                goneTimer.stop()
                osd.windowVisible = true
                osd.shown = true
                LayoutState.holdOsd()
            }

            onExited: {
                osd.hoveredPos = -1
                LayoutState.releaseOsd()
                hideTimer.restart()
            }

            onPositionChanged: mouse => osd.hoveredPos = posAt(mouse.x)

            onClicked: mouse => {
                var p = posAt(mouse.x)
                if (p >= 0) LayoutState.selectPos(p)
            }
        }
    }
}
