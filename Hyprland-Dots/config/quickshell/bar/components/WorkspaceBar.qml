import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import ".."

RowLayout {
    id: workspaceBar
    spacing: 0

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
            Layout.preferredWidth: wsNumber.implicitWidth
            Layout.alignment: Qt.AlignVCenter
            // No pill for active anymore — the [brackets] mark the selection.
            // Keep only a faint hover hint.
            color: wsMouse.containsMouse && !isActive ? Qt.rgba(255, 255, 255, 0.05) : "transparent"
            radius: 4

            property int wsId: index + 1
            property var workspace: Hyprland.workspaces.values.find(ws => ws.id === wsId) ?? null
            property bool isActive: workspaceBar.activeWorkspaceId === wsId
            property bool hasWindows: workspace !== null

            Text {
                id: wsNumber
                anchors.centerIn: parent
                // Active -> [N] bold; inactive -> space-padded N (same monospace width, no jump)
                text: wsRect.isActive ? "[" + wsRect.wsId + "]" : " " + wsRect.wsId + " "
                color: wsRect.isActive ? Theme.colWorkspaceActive :
                       wsRect.hasWindows ? Theme.colFg : Theme.colMuted
                font.pixelSize: Theme.fontSize
                font.family: Theme.fontFamily
                font.bold: wsRect.isActive
                style: Text.Outline
                styleColor: Qt.rgba(color.r, color.g, color.b, 0.3)
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
