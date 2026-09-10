import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Hyprland
import ".."

Rectangle {
    id: kbWidget

    property string currentLayout: "us"

    implicitWidth: kbText.implicitWidth
    implicitHeight: parent.height
    color: mouseArea.containsMouse ? Qt.rgba(255, 255, 255, 0.1) : "transparent"
    radius: 6

    Text {
        id: kbText
        anchors.centerIn: parent
        text: currentLayout.toUpperCase()
        color: Theme.colFg
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
        font.bold: true; style: Text.Outline; styleColor: Theme.colTextShadow
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            switchProc.running = true
        }
    }

    // Get current keyboard layout
    Process {
        id: layoutProc
        command: ["sh", "-c", "hyprctl devices -j | jq -r '.keyboards[] | select(.main == true) | .active_keymap' | head -1"]
        stdout: SplitParser {
            onRead: data => {
                if (!data) return
                kbWidget.applyLayoutName(data)
            }
        }
        Component.onCompleted: running = true
    }

    // Switch to next layout
    Process {
        id: switchProc
        command: ["hyprctl", "switchxkblayout", "all", "next"]
        onExited: {
            // Update layout after switching
            layoutProc.running = true
        }
    }

    function applyLayoutName(name) {
        var layout = name.trim().toLowerCase()
        if (layout.includes("english")) kbWidget.currentLayout = "us"
        else if (layout.includes("spanish")) kbWidget.currentLayout = "es"
        else if (layout.includes("russian")) kbWidget.currentLayout = "ru"
        else kbWidget.currentLayout = layout.substring(0, 2)
    }

    // Listen to Hyprland events - specifically for layout changes.
    // The event payload is "<device>,<Layout Name>", so the name is read
    // straight off it instead of shelling out to hyprctl+jq for every one of
    // the ten per-keyboard events Hyprland fires on each switch.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "activelayout") return
            var i = event.data.indexOf(",")
            if (i < 0) return
            kbWidget.applyLayoutName(event.data.substring(i + 1))
        }
    }
}
