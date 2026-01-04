import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

Item {
    id: nightLightWidget

    property bool isOn: false

    implicitWidth: nightLightText.implicitWidth + 16
    implicitHeight: parent.height

    Text {
        id: nightLightText
        anchors.centerIn: parent
        text: "☀"
        color: isOn ? "#FFA500" : Theme.colFg  // Orange when on, normal when off
        font.pixelSize: Theme.fontSize + 4
        font.family: Theme.fontFamily
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            toggleProcess.running = true
        }
    }

    // Status check process
    Process {
        id: statusProc
        command: ["bash", "-c", "$HOME/.config/hypr/scripts/Hyprsunset.sh status"]
        stdout: SplitParser {
            onRead: data => {
                if (!data) return
                try {
                    const status = JSON.parse(data.trim())
                    nightLightWidget.isOn = (status.class === "on")
                } catch(e) {
                    // Fallback: check if hyprsunset process is running
                }
            }
        }
        Component.onCompleted: running = true
    }

    // Toggle process
    Process {
        id: toggleProcess
        command: ["bash", "-c", "$HOME/.config/hypr/scripts/Hyprsunset.sh toggle"]
        running: false
        onExited: {
            // Refresh status after toggle (small delay to let process start/stop)
            statusRefreshTimer.start()
        }
    }

    // Single-shot timer to refresh status after toggle
    Timer {
        id: statusRefreshTimer
        interval: 200
        running: false
        repeat: false
        onTriggered: statusProc.running = true
    }
}
