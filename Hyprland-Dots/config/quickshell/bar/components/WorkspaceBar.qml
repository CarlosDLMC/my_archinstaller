import QtQuick
import QtQuick.Layouts
import ".."

// The workspaces of this bar's monitor (mango's tags), numbered. Shows at
// least 1-5, and up to the highest one that holds windows or is shown.
RowLayout {
    id: workspaceBar
    spacing: 0

    required property var screenName
    readonly property var monitorData: Mango.monitor(screenName)
    readonly property var tags: monitorData ? monitorData.tags : []

    property int maxWorkspaceWithWindows: {
        var max = 0
        for (var i = 0; i < tags.length; i++) {
            if (tags[i].client_count > 0 && tags[i].index > max) max = tags[i].index
        }
        return max
    }

    property int activeWorkspaceId: monitorData && monitorData.active_tags.length > 0
                                    ? monitorData.active_tags[0] : 1
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
            property var workspace: workspaceBar.tags.find(t => t.index === wsId) ?? null
            property bool isActive: workspaceBar.activeWorkspaceId === wsId
            property bool hasWindows: workspace !== null && workspace.client_count > 0

            Text {
                id: wsNumber
                anchors.centerIn: parent
                // Active -> [N] bold; inactive -> space-padded N (same monospace width, no jump)
                text: wsRect.isActive ? "[" + wsRect.wsId + "]" : " " + wsRect.wsId + " "
                // White when the workspace holds something, grey when empty.
                // The [brackets] mark which one is focused, not the colour.
                color: (wsRect.isActive || wsRect.hasWindows) ? Theme.colWorkspaceActive
                                                              : Theme.colWorkspaceInactive
                font.pixelSize: Theme.fontSize
                font.family: Theme.fontFamily
                font.bold: wsRect.isActive
                style: Text.Outline
                styleColor: Theme.colTextShadow
            }

            MouseArea {
                id: wsMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // On this bar's monitor, whichever has focus.
                onClicked: Mango.dispatch("viewcrossmon," + wsRect.wsId + ",^" + workspaceBar.screenName + "$")
            }
        }
    }
}
