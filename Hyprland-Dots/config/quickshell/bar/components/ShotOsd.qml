import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import ".."

// Screenshot dialog: same box as the recording one, minus the audio row.
// Two big buttons (whole monitor / drag a region) and the monitor picker,
// which only appears when there is more than one screen to choose from.
PanelWindow {
    id: osd

    property var modelData
    screen: modelData

    readonly property bool onFocusedMonitor:
        Hyprland.focusedMonitor && modelData
        && Hyprland.focusedMonitor.name === modelData.name

    readonly property bool shown: ShotState.dialogOpen && onFocusedMonitor

    property bool windowVisible: false

    readonly property int fadeMs: 160
    readonly property real uiScale: 1.35

    readonly property int btnWidth:    Math.round(210 * uiScale)
    readonly property int btnHeight:   Math.round(150 * uiScale)
    readonly property int btnRadius:   Math.round(14  * uiScale)
    readonly property int btnIconSize: Math.round(52  * uiScale)
    readonly property int btnTextSize: Math.round(17  * uiScale)

    readonly property int monTileW:    Math.round(150 * uiScale)
    readonly property int monTileH:    Math.round(58  * uiScale)

    readonly property int titleSize:   Math.round(14 * uiScale)
    readonly property int subSize:     Math.round(12 * uiScale)

    readonly property int panelPad:    Math.round(28 * uiScale)
    readonly property int panelRadius: Math.round(18 * uiScale)
    readonly property int gap:         Math.round(14 * uiScale)

    visible: windowVisible

    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    onShownChanged: {
        if (shown) { windowVisible = true; goneTimer.stop() }
        else goneTimer.restart()
    }

    Timer {
        id: goneTimer
        interval: osd.fadeMs
        onTriggered: osd.windowVisible = false
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.5)
        opacity: osd.shown ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: osd.fadeMs } }

        MouseArea {
            anchors.fill: parent
            onClicked: ShotState.close()
        }
    }

    Item {
        anchors.fill: parent
        focus: osd.shown

        Keys.onEscapePressed: ShotState.close()
        Keys.onReturnPressed: ShotState.shotFullscreen()
        Keys.onEnterPressed: ShotState.shotFullscreen()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_F) ShotState.shotFullscreen()
            else if (event.key === Qt.Key_R) ShotState.shotRegion()
            else if (event.key === Qt.Key_W) ShotState.shotWindow()
            else if (event.key === Qt.Key_E) ShotState.shotSwappy()
        }

        Rectangle {
            id: panel
            anchors.centerIn: parent
            width: content.width + osd.panelPad * 2
            height: content.height + osd.panelPad * 2
            radius: osd.panelRadius
            color: Theme.colBg
            border.width: 1
            border.color: Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.14)

            opacity: osd.shown ? 1.0 : 0.0
            scale: osd.shown ? 1.0 : 0.96
            Behavior on opacity { NumberAnimation { duration: osd.fadeMs; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: osd.fadeMs; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent }

            Column {
                id: content
                anchors.centerIn: parent
                spacing: osd.gap

                Text {
                    text: "SCREENSHOT"
                    color: Theme.colDim
                    font.family: Theme.fontFamily
                    font.pixelSize: osd.titleSize
                    font.letterSpacing: 2
                }

                Row {
                    spacing: osd.gap

                    BigButton {
                        width: osd.btnWidth
                        height: osd.btnHeight
                        radius: osd.btnRadius
                        icon: "󰍹"
                        label: "Full screen"
                        hint: Monitors.multiple ? ShotState.targetMonitor : ""
                        iconSize: osd.btnIconSize
                        textSize: osd.btnTextSize
                        subTextSize: osd.subSize
                        onActivated: ShotState.shotFullscreen()
                    }

                    BigButton {
                        width: osd.btnWidth
                        height: osd.btnHeight
                        radius: osd.btnRadius
                        icon: "󰆞"
                        label: "Select region"
                        hint: "drag to choose"
                        iconSize: osd.btnIconSize
                        textSize: osd.btnTextSize
                        subTextSize: osd.subSize
                        onActivated: ShotState.shotRegion()
                    }
                }

                Column {
                    spacing: Math.round(osd.gap * 0.5)
                    visible: Monitors.multiple

                    Text {
                        text: "MONITOR"
                        color: Theme.colDim
                        font.family: Theme.fontFamily
                        font.pixelSize: osd.titleSize
                        font.letterSpacing: 2
                    }

                    Row {
                        spacing: Math.round(osd.gap * 0.6)

                        Repeater {
                            model: Monitors.list

                            Rectangle {
                                id: monTile
                                required property var modelData

                                readonly property bool isTarget:
                                    modelData.name === ShotState.targetMonitor

                                width: osd.monTileW
                                height: osd.monTileH
                                radius: Math.round(osd.btnRadius * 0.7)
                                color: isTarget
                                    ? Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.14)
                                    : "transparent"
                                border.width: isTarget ? 2 : 1
                                border.color: isTarget
                                    ? Theme.colWhite
                                    : Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.18)

                                Behavior on color { ColorAnimation { duration: 110 } }

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 2

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: monTile.modelData.name
                                        color: Theme.colWhite
                                        opacity: monTile.isTarget ? 1.0 : 0.6
                                        font.family: Theme.fontFamily
                                        font.pixelSize: osd.subSize + 2
                                        font.bold: monTile.isTarget
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: monTile.modelData.width + "x" + monTile.modelData.height
                                              + "  " + monTile.modelData.refresh + "Hz"
                                        color: Theme.colWhite
                                        opacity: monTile.isTarget ? 0.7 : 0.4
                                        font.family: Theme.fontFamily
                                        font.pixelSize: osd.subSize
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: ShotState.targetMonitor = monTile.modelData.name
                                    onDoubleClicked: {
                                        ShotState.targetMonitor = monTile.modelData.name
                                        ShotState.shotFullscreen()
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    text: "W  active window     E  annotate"
                    color: Theme.colDim
                    opacity: 0.7
                    font.family: Theme.fontFamily
                    font.pixelSize: osd.subSize
                }
            }
        }
    }
}
