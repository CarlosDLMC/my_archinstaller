import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import ".."

// GNOME-style keyboard-layout switcher OSD.
//
// Shows every configured layout in most-recently-used order, highlighting the
// selected one, centred on the focused monitor. Each entry is a short code
// above its display name, the same shape GNOME's InputSourceSwitcher uses.
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
    readonly property int tileRadius:  Math.round(12 * uiScale)
    readonly property int codeSize:    Math.round(34 * uiScale)
    readonly property int nameSize:    Math.round(13 * uiScale)
    readonly property int nameWidth:   Math.round(96 * uiScale)
    readonly property int itemSpacing: Math.round(6  * uiScale)
    readonly property int rowSpacing:  Math.round(10 * uiScale)
    readonly property int panelPad:    Math.round(32 * uiScale)
    readonly property int panelRadius: Math.round(18 * uiScale)

    readonly property var items: LayoutState.switcherItems
    readonly property int selected: LayoutState.selectedPos

    readonly property bool onFocusedMonitor:
        Hyprland.focusedMonitor && modelData
        && Hyprland.focusedMonitor.name === modelData.name

    visible: windowVisible && onFocusedMonitor && items.length > 0

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
        width: row.width + osd.panelPad
        height: row.height + osd.panelPad
        radius: osd.panelRadius
        color: Qt.rgba(Theme.colBg.r, Theme.colBg.g, Theme.colBg.b, 0.92)
        border.width: 1
        border.color: Qt.rgba(Theme.colFg.r, Theme.colFg.g, Theme.colFg.b, 0.12)

        opacity: osd.shown ? 1.0 : 0.0
        scale: osd.shown ? 1.0 : 0.94
        Behavior on opacity { NumberAnimation { duration: osd.fadeMs; easing.type: Easing.OutCubic } }
        Behavior on scale   { NumberAnimation { duration: osd.fadeMs; easing.type: Easing.OutCubic } }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: osd.rowSpacing

            Repeater {
                model: osd.items

                Column {
                    required property var modelData
                    required property int index

                    readonly property bool isSelected: index === osd.selected
                    spacing: osd.itemSpacing

                    // Short code in a tile, like GNOME's styled bin.
                    Rectangle {
                        width: osd.tileSize
                        height: osd.tileSize
                        radius: osd.tileRadius
                        color: parent.isSelected
                               ? Qt.rgba(Theme.colFg.r, Theme.colFg.g, Theme.colFg.b, 0.16)
                               : "transparent"
                        border.width: parent.isSelected ? 2 : 1
                        border.color: parent.isSelected
                               ? Theme.colFg
                               : Qt.rgba(Theme.colFg.r, Theme.colFg.g, Theme.colFg.b, 0.18)

                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: (modelData.short || "").toUpperCase()
                            color: Theme.colFg
                            opacity: parent.parent.isSelected ? 1.0 : 0.55
                            font.family: Theme.fontFamily
                            font.pixelSize: osd.codeSize
                            font.bold: true
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: osd.nameWidth
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: modelData.name || ""
                        color: Theme.colFg
                        opacity: parent.isSelected ? 0.85 : 0.4
                        font.family: Theme.fontFamily
                        font.pixelSize: osd.nameSize
                    }
                }
            }
        }
    }
}
