import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

RowLayout {
    id: memWidget
    spacing: 4

    property string memUsage: "0G"

    // Label — dim, same weight as the CPU label
    Text {
        text: "MEM "
        color: Theme.colMem
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
        font.bold: true
        Layout.alignment: Qt.AlignVCenter
    }

    // Value — steps up to full foreground
    Text {
        text: memWidget.memUsage
        color: Theme.colValue
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
        font.bold: true
        Layout.alignment: Qt.AlignVCenter
    }

    Process {
        id: memProc
        command: ["sh", "-c", "free -m | grep Mem"]
        stdout: SplitParser {
            onRead: data => {
                if (!data) return
                var parts = data.trim().split(/\s+/)
                var usedMB = parseInt(parts[2]) || 0
                var usedGB = (usedMB / 1024).toFixed(2)
                memWidget.memUsage = usedGB + "G"
            }
        }
        Component.onCompleted: running = true
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: memProc.running = true
    }
}
