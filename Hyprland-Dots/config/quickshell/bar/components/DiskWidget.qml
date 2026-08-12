import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

Text {
    id: diskWidget

    property int diskUsage: 0

    text: "DSK " + diskUsage + "%"
    color: Theme.colDisk
    font.pixelSize: Theme.fontSize
    font.family: Theme.fontFamily
    font.bold: true; style: Text.Outline; styleColor: Qt.rgba(color.r, color.g, color.b, 0.3)

    Process {
        id: diskProc
        command: ["sh", "-c", "df / | tail -1"]
        stdout: SplitParser {
            onRead: data => {
                if (!data) return
                var parts = data.trim().split(/\s+/)
                var percentStr = parts[4] || "0%"
                diskWidget.diskUsage = parseInt(percentStr.replace('%', '')) || 0
            }
        }
        Component.onCompleted: running = true
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: diskProc.running = true
    }
}
