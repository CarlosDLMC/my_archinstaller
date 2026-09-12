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

    // Label
    Text {
        text: "CPU "
        color: Theme.colCpu
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
        font.bold: true; style: Text.Outline; styleColor: Theme.colTextShadow
        Layout.alignment: Qt.AlignVCenter
    }

    // Usage percentage
    Text {
        text: cpuWidget.cpuUsage + "% "
        color: Theme.colValue
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
        font.bold: true; style: Text.Outline; styleColor: Theme.colTextShadow
        Layout.alignment: Qt.AlignVCenter
    }

    // Temperature
    Text {
        text: cpuWidget.cpuTemp + "ºC"
        color: Theme.colValue
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
        font.bold: true; style: Text.Outline; styleColor: Theme.colTextShadow
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

    // CPU temperature.
    //
    // Not thermal_zone0. That is simply whichever zone the kernel registered
    // first, and it is the wrong sensor on both vendors. On this Intel ThinkPad
    // zone0 is `acpitz` - a chassis sensor that reads a couple of degrees below
    // the actual package temperature in `coretemp`. On an AMD desktop it is
    // worse than inaccurate: those boards commonly expose no ACPI thermal zone
    // at all, the CPU temperature lives only in `k10temp` under hwmon, so the
    // glob matched nothing and the widget sat at 0ºC forever with no error.
    //
    // So ask the CPU's own hwmon driver first - temp1_input is the package on
    // coretemp and Tctl on k10temp - then fall back to the package thermal zone
    // ahead of the chassis one, and only then to the old blind first-zone read.
    Process {
        id: tempProc
        command: ["sh", "-c",
            'for d in /sys/class/hwmon/hwmon*; do case "$(cat "$d/name" 2>/dev/null)" in k10temp|zenpower|coretemp) [ -r "$d/temp1_input" ] && { cat "$d/temp1_input"; exit 0; };; esac; done\n' +
            'for want in x86_pkg_temp acpitz; do for z in /sys/class/thermal/thermal_zone*; do [ "$(cat "$z/type" 2>/dev/null)" = "$want" ] && [ -r "$z/temp" ] && { cat "$z/temp"; exit 0; }; done; done\n' +
            'cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -1\n'
        ]
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
