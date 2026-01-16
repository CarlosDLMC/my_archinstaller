import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

RowLayout {
    id: cpuWidget
    spacing: 4

    property int cpuUsage: 0
    property int cpuTemp: 0
    property var lastCpuIdle: 0
    property var lastCpuTotal: 0

    // Temperature
    Text {
        text: cpuWidget.cpuTemp + "ºC "
        color: Theme.colCpu
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
        font.bold: true
        Layout.alignment: Qt.AlignVCenter
    }

    // Icon
    Text {
        text: "󰍛 "
        color: Theme.colCpu
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
        font.bold: true
        Layout.alignment: Qt.AlignVCenter
    }

    // Usage percentage
    Text {
        text: cpuWidget.cpuUsage + "%"
        color: Theme.colCpu
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
        font.bold: true
        Layout.alignment: Qt.AlignVCenter
    }

    // CPU usage process
    Process {
        id: cpuProc
        command: ["sh", "-c", "head -1 /proc/stat"]
        stdout: SplitParser {
            onRead: data => {
                if (!data) return
                var parts = data.trim().split(/\s+/)
                var user = parseInt(parts[1]) || 0
                var nice = parseInt(parts[2]) || 0
                var system = parseInt(parts[3]) || 0
                var idle = parseInt(parts[4]) || 0
                var iowait = parseInt(parts[5]) || 0
                var irq = parseInt(parts[6]) || 0
                var softirq = parseInt(parts[7]) || 0

                var total = user + nice + system + idle + iowait + irq + softirq
                var idleTime = idle + iowait

                if (cpuWidget.lastCpuTotal > 0) {
                    var totalDiff = total - cpuWidget.lastCpuTotal
                    var idleDiff = idleTime - cpuWidget.lastCpuIdle
                    if (totalDiff > 0) {
                        cpuWidget.cpuUsage = Math.round(100 * (totalDiff - idleDiff) / totalDiff)
                    }
                }
                cpuWidget.lastCpuTotal = total
                cpuWidget.lastCpuIdle = idleTime
            }
        }
        Component.onCompleted: running = true
    }

    // CPU temperature process
    Process {
        id: tempProc
        command: ["sh", "-c", "cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -1"]
        stdout: SplitParser {
            onRead: data => {
                if (!data) return
                var temp = parseInt(data.trim())
                if (!isNaN(temp)) {
                    cpuWidget.cpuTemp = Math.round(temp / 1000)
                }
            }
        }
        Component.onCompleted: running = true
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: {
            cpuProc.running = true
            tempProc.running = true
        }
    }
}
