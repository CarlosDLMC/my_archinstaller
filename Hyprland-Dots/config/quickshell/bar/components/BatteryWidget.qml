import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

DropdownWidget {
    id: batteryWidget
    popupWidth: 280
    popupHeight: Math.max(160, 70 + (batteryInfo.split('\n').filter(l => l.trim()).length * 60))

    property string batteryInfo: ""
    property int averageLevel: 0
    property bool isCharging: false

    function getBatteryIcon(level, charging) {
        if (charging) return "󰂄"
        if (level <= 10) return "󰂎"
        if (level <= 20) return "󰁺"
        if (level <= 30) return "󰁻"
        if (level <= 40) return "󰁼"
        if (level <= 50) return "󰁽"
        if (level <= 60) return "󰁾"
        if (level <= 70) return "󰁿"
        if (level <= 80) return "󰂀"
        if (level <= 90) return "󰂁"
        if (level < 100) return "󰂂"
        return "󰁹"
    }

    function parseBatteryInfo(output) {
        if (!output) return

        console.log("Battery raw output:", output)
        var lines = output.trim().split('\n').filter(l => l.trim())
        console.log("Battery lines found:", lines.length, "lines:", JSON.stringify(lines))
        var total = 0
        var count = 0
        var charging = false

        for (var i = 0; i < lines.length; i++) {
            // Match "Battery: XX% (Status)" format from lock screen script
            var match = lines[i].match(/Battery:\s*(\d+)%\s+\((.+)\)/)
            if (match) {
                var level = parseInt(match[1])
                var status = match[2]
                total += level
                count++
                if (status === "Charging") charging = true
                console.log("Battery", count, "found: level=", level, "status=", status)
            }
        }

        batteryWidget.averageLevel = count > 0 ? Math.round(total / count) : 0
        batteryWidget.isCharging = charging
        batteryWidget.batteryInfo = output.trim()
        console.log("Final battery info stored:", batteryWidget.batteryInfo)
    }

    // Icon shown in bar (average battery)
    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: batteryWidget.getBatteryIcon(batteryWidget.averageLevel, batteryWidget.isCharging) + " " + batteryWidget.averageLevel + "%"
        color: batteryWidget.averageLevel <= 15 ? "#f53c3c" : "#32CD32"
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
        font.bold: true
    }

    // Popup content
    popupContent: Component {
        Column {
            width: parent.width
            spacing: 12

            Text {
                text: "Battery Status"
                color: Theme.colFg
                font.pixelSize: Theme.fontSize + 2
                font.family: Theme.fontFamily
                font.bold: true
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Repeater {
                model: batteryWidget.batteryInfo.split('\n').filter(l => l.trim())

                Row {
                    width: parent.width
                    spacing: 12

                    property var batteryData: {
                        // Match "Battery: XX% (Status)" format from lock screen script
                        var match = modelData.match(/Battery:\s*(\d+)%\s+\((.+)\)/)
                        if (match) {
                            return {
                                level: parseInt(match[1]),
                                status: match[2],
                                charging: match[2] === "Charging"
                            }
                        }
                        return {level: 0, status: "Unknown", charging: false}
                    }

                    Text {
                        text: batteryWidget.getBatteryIcon(parent.batteryData.level, parent.batteryData.charging)
                        color: parent.batteryData.level <= 15 ? "#f53c3c" : "#32CD32"
                        font.pixelSize: Theme.fontSize + 4
                        font.family: Theme.fontFamily
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        spacing: 4
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            text: "Battery " + (index + 1) + ": " + parent.parent.batteryData.level + "%"
                            color: Theme.colFg
                            font.pixelSize: Theme.fontSize
                            font.family: Theme.fontFamily
                            font.bold: true
                        }

                        Text {
                            text: parent.parent.batteryData.charging ? "Charging" : "Not charging"
                            color: Theme.colMuted
                            font.pixelSize: Theme.fontSize - 2
                            font.family: Theme.fontFamily
                        }
                    }
                }
            }
        }
    }

    // Get battery information using the EXACT same script as the lock screen
    Process {
        id: batteryProc
        property string output: ""
        command: ["sh", "-c", "$HOME/.config/hypr/scripts/Battery.sh"]
        stdout: SplitParser {
            onRead: data => {
                if (!data) return
                batteryProc.output += data + "\n"
            }
        }
        onRunningChanged: {
            if (running) {
                output = ""
            } else if (output) {
                batteryWidget.parseBatteryInfo(output)
            }
        }
        Component.onCompleted: running = true
    }

    function updateBatteries() {
        batteryProc.running = true
    }

    // Event-based battery monitoring using udevadm
    Process {
        id: batteryMonitor
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=power_supply"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                if (data && (data.includes("BAT") || data.includes("AC"))) {
                    batteryWidget.updateBatteries()
                }
            }
        }
        Component.onCompleted: running = true
    }

    // Backup timer (in case udevadm fails)
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: batteryWidget.updateBatteries()
    }
}
