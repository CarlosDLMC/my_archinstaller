import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import ".."

RowLayout {
    id: workspaceBar
    spacing: 3

    property int maxWorkspaceWithWindows: {
        var max = 0
        for (var i = 0; i < Hyprland.workspaces.values.length; i++) {
            var ws = Hyprland.workspaces.values[i]
            if (ws.id > max && ws.id <= 9) max = ws.id
        }
        return max
    }

    property int activeWorkspaceId: Hyprland.focusedWorkspace?.id ?? 1
    property int workspacesToShow: Math.max(5, maxWorkspaceWithWindows, activeWorkspaceId)

    Repeater {
        model: workspaceBar.workspacesToShow

        Rectangle {
            id: wsRect
            Layout.preferredHeight: 28
            Layout.preferredWidth: wsNumber.implicitWidth + 16
            Layout.alignment: Qt.AlignVCenter
            color: isActive ? Qt.rgba(Theme.colWorkspaceActive.r, Theme.colWorkspaceActive.g, Theme.colWorkspaceActive.b, 0.15) :
                   wsMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.05) : "transparent"
            radius: 8
            border.width: isActive ? 1 : 0
            border.color: Qt.rgba(Theme.colWorkspaceActive.r, Theme.colWorkspaceActive.g, Theme.colWorkspaceActive.b, 0.3)

            property int wsId: index + 1
            property var workspace: Hyprland.workspaces.values.find(ws => ws.id === wsId) ?? null
            property bool isActive: workspaceBar.activeWorkspaceId === wsId
            property bool hasWindows: workspace !== null

            Behavior on color {
                ColorAnimation { duration: 150 }
            }

            Text {
                id: wsNumber
                anchors.centerIn: parent
                text: wsRect.wsId
                color: wsRect.isActive ? Theme.colWorkspaceActive :
                       wsRect.hasWindows ? Theme.colFg : Theme.colMuted
                font.pixelSize: Theme.fontSize
                font.family: Theme.fontFamily
                font.bold: wsRect.isActive
            }

            MouseArea {
                id: wsMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Hyprland.dispatch("workspace " + wsRect.wsId)
            }
        }
    }
}
