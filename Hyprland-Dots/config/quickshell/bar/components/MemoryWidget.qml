import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

Text {
    id: memWidget

    property string memUsage: "0G"

    text: "MEM " + memUsage
    color: Theme.colMem
    font.pixelSize: Theme.fontSize
    font.family: Theme.fontFamily
    font.bold: true; style: Text.Outline; styleColor: Qt.rgba(color.r, color.g, color.b, 0.3)

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
