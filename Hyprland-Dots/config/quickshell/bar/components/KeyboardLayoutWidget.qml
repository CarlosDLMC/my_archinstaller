import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Hyprland
import ".."

Rectangle {
    id: kbWidget

    property string currentLayout: "us"

    implicitWidth: kbText.implicitWidth + 16
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
        font.bold: true
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
                var layout = data.trim().toLowerCase()
                // Map full names to short codes
                if (layout.includes("english")) kbWidget.currentLayout = "us"
                else if (layout.includes("spanish")) kbWidget.currentLayout = "es"
                else if (layout.includes("russian")) kbWidget.currentLayout = "ru"
                else kbWidget.currentLayout = layout.substring(0, 2)
            }
        }
        Component.onCompleted: running = true
    }

    // Switch to next layout
    Process {
        id: switchProc
        command: ["sh", "-c", "hyprctl switchxkblayout at-translated-set-2-keyboard next"]
        onExited: {
            // Update layout after switching
            layoutProc.running = true
        }
    }

    // Listen to Hyprland events - specifically for layout changes
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // Hyprland sends "activelayout" event when keyboard layout changes
            if (event.name === "activelayout") {
                layoutProc.running = true
            }
        }
    }
}
