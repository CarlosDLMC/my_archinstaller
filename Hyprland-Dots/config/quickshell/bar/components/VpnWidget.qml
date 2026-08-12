import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

DropdownWidget {
    id: vpnWidget
    popupWidth: 240
    popupHeight: Math.min(vpnConfigs.length * 40 + 50, 350)
    popupXOffset: 250

    required property var centerInfoRef

    property string activeVpn: ""
    property var vpnConfigs: []
    property bool isConnecting: false
    property int statusCheckCounter: 0
    property bool initialCheckDone: false

    function updateVpnStatus() {
        statusCheckCounter++
    }

    onOpened: vpnListProc.running = true

    // Check active VPN - triggered by statusCheckCounter changes
    Process {
        id: vpnStatusProc
        property string output: ""
        command: ["sh", "-c", "wg show interfaces 2>&1 || echo ''"]
        running: vpnWidget.statusCheckCounter > 0
        stdout: SplitParser {
            onRead: data => {
                if (data) vpnStatusProc.output += data
            }
        }
        onRunningChanged: {
            if (running) {
                output = ""
            } else {
                var trimmed = output.trim()
                var wasActive = vpnWidget.activeVpn !== ""
                if (!trimmed || trimmed === "") {
                    vpnWidget.activeVpn = ""
                    // VPN dropped unexpectedly — reset timezone/weather to local
                    if (wasActive) {
                        vpnResetProc.running = true
                    } else if (!vpnWidget.initialCheckDone) {
                        // First check after startup: reset if stale cache exists
                        staleCacheCheckProc.running = true
                    }
                } else {
                    var interfaces = trimmed.split(/\s+/)
                    vpnWidget.activeVpn = interfaces[0] || ""
                }
                vpnWidget.initialCheckDone = true
            }
        }
    }

    // Initial status check
    Component.onCompleted: {
        vpnWidget.updateVpnStatus()
    }

    // List available VPN configs
    Process {
        id: vpnListProc
        property string output: ""
        command: ["sh", "-c", "sudo find /etc/wireguard -name '*.conf' -exec basename {} .conf \\; 2>/dev/null | sort"]
        stdout: SplitParser {
            onRead: data => {
                if (data) vpnListProc.output += data + "\n"
            }
        }
        onRunningChanged: {
            if (running) {
                output = ""
            } else if (output) {
                var lines = output.trim().split('\n').filter(l => l.trim())
                var configs = []
                for (var i = 0; i < lines.length; i++) {
                    if (lines[i].trim()) {
                        configs.push(lines[i].trim())
                    }
                }
                vpnWidget.vpnConfigs = configs
            }
        }
    }

    // VPN connect/disconnect process
    Process {
        id: vpnActionProc
        property string targetVpn: ""
        property bool isDisconnect: false
        command: isDisconnect ?
            ["sudo", "wg-quick", "down", targetVpn] :
            ["sudo", "wg-quick", "up", targetVpn]
        onRunningChanged: {
            if (!running) {
                vpnWidget.isConnecting = false
                // Clear status immediately if disconnecting
                if (isDisconnect) {
                    vpnWidget.activeVpn = ""
                }
                // Schedule status update with slight delay to ensure wg updates
                statusUpdateTimer.restart()
            }
        }
    }

    // Delayed status update timer
    Timer {
        id: statusUpdateTimer
        interval: 500
        repeat: false
        onTriggered: vpnWidget.updateVpnStatus()
    }

    // VPN sync process (timezone + weather)
    Process {
        id: vpnSyncProc
        property string targetVpn: ""
        command: ["sh", "-c", "$HOME/.config/quickshell/bar/scripts/vpn-sync.sh " + targetVpn]
        onRunningChanged: {
            if (!running) {
                // Trigger immediate refresh in CenterInfo
                if (centerInfoRef) {
                    centerInfoRef.refreshTimezone()
                    centerInfoRef.refreshWeather()
                }
            }
        }
    }

    // VPN reset process (back to local)
    Process {
        id: vpnResetProc
        command: ["sh", "-c", "$HOME/.config/quickshell/bar/scripts/vpn-reset.sh"]
        onRunningChanged: {
            if (!running) {
                vpnWidget.updateVpnStatus()
                // Trigger immediate refresh in CenterInfo
                if (centerInfoRef) {
                    centerInfoRef.refreshTimezone()
                    centerInfoRef.refreshWeather()
                }
            }
        }
    }

    // Check if stale city cache exists (startup only)
    Process {
        id: staleCacheCheckProc
        property string output: ""
        command: ["sh", "-c", "cat ~/.cache/quickshell/weather_city 2>/dev/null"]
        stdout: SplitParser {
            onRead: data => {
                if (data) staleCacheCheckProc.output += data
            }
        }
        onRunningChanged: {
            if (running) {
                output = ""
            } else if (output.trim()) {
                // Stale city cache exists with no VPN — reset
                vpnResetProc.running = true
            }
        }
    }

    // Monitor for VPN changes (check every 5 seconds)
    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: vpnWidget.updateVpnStatus()
    }

    // Icon content
    Text {
        id: vpnText
        anchors.verticalCenter: parent.verticalCenter
        text: vpnWidget.activeVpn ? "󰖂" : "󰖂"
        color: vpnWidget.activeVpn ? Theme.colNetwork : Theme.colMuted
        font.pixelSize: Theme.fontSize + 4
        font.family: Theme.fontFamily
        font.bold: true; style: Text.Outline; styleColor: Qt.rgba(color.r, color.g, color.b, 0.3)
    }

    // Popup content
    popupContent: Component {
        Column {
            spacing: 4

            // Header
            RowLayout {
                width: parent.width
                spacing: 8

                Text {
                    text: vpnWidget.activeVpn ? "󰖂 " + vpnWidget.activeVpn : "󰖂 Disconnected"
                    color: Theme.colFg
                    font.pixelSize: Theme.fontSize
                    font.family: Theme.fontFamily
                    font.bold: true; style: Text.Outline; styleColor: Qt.rgba(color.r, color.g, color.b, 0.3)
                    Layout.fillWidth: true
                }

                // Sync button (timezone + weather) - only show when connected
                Rectangle {
                    visible: vpnWidget.activeVpn !== ""
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 24
                    color: syncMouseArea.containsMouse ? Qt.rgba(100, 255, 100, 0.2) : "transparent"
                    radius: 4

                    Text {
                        anchors.centerIn: parent
                        text: "󰑓"
                        color: Theme.colNetwork
                        font.pixelSize: Theme.fontSize
                        font.family: Theme.fontFamily
                    }

                    MouseArea {
                        id: syncMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            vpnSyncProc.targetVpn = vpnWidget.activeVpn
                            vpnSyncProc.running = true
                        }
                    }
                }

                // Disconnect button (only show when connected)
                Rectangle {
                    visible: vpnWidget.activeVpn !== ""
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 24
                    color: disconnectMouseArea.containsMouse ? Qt.rgba(255, 100, 100, 0.2) : "transparent"
                    radius: 4

                    Text {
                        anchors.centerIn: parent
                        text: "󰅖"
                        color: Theme.colMuted
                        font.pixelSize: Theme.fontSize
                        font.family: Theme.fontFamily
                    }

                    MouseArea {
                        id: disconnectMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            vpnActionProc.targetVpn = vpnWidget.activeVpn
                            vpnActionProc.isDisconnect = true
                            vpnWidget.isConnecting = true
                            vpnActionProc.running = true
                            // Also reset timezone/weather to local
                            vpnResetProc.running = true
                            vpnWidget.dropdownOpen = false
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.colMuted
            }

            // VPN config list
            ListView {
                id: vpnListView
                width: parent.width
                height: parent.height - 40
                clip: true
                model: vpnWidget.vpnConfigs
                spacing: 2

                delegate: Rectangle {
                    width: vpnListView.width
                    height: 36
                    color: mouseArea.containsMouse ? Qt.rgba(255, 255, 255, 0.1) : "transparent"
                    radius: 6

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 8

                        Text {
                            text: modelData === vpnWidget.activeVpn ? "󰄬" : "󰖂"
                            color: modelData === vpnWidget.activeVpn ? Theme.colNetwork : Theme.colMuted
                            font.pixelSize: Theme.fontSize
                            font.family: Theme.fontFamily
                        }

                        Text {
                            text: modelData
                            color: modelData === vpnWidget.activeVpn ? Theme.colNetwork : Theme.colFg
                            font.pixelSize: Theme.fontSize - 1
                            font.family: Theme.fontFamily
                            font.bold: modelData === vpnWidget.activeVpn
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        // Location indicator based on config name
                        Text {
                            text: {
                                var name = modelData.toLowerCase()
                                if (name.includes("de")) return "🇩🇪"
                                if (name.includes("pl")) return "🇵🇱"
                                if (name.includes("ge")) return "🇬🇪"
                                if (name.includes("es")) return "🇪🇸"
                                if (name.includes("ua")) return "🇺🇦"
                                if (name.includes("lt")) return "🇱🇹"
                                if (name.includes("id")) return "🇮🇩"
                                return ""
                            }
                            font.pixelSize: Theme.fontSize + 2
                        }
                    }

                    MouseArea {
                        id: mouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: modelData !== vpnWidget.activeVpn
                        onClicked: {
                            // Disconnect current if connected
                            if (vpnWidget.activeVpn) {
                                vpnActionProc.targetVpn = vpnWidget.activeVpn
                                vpnActionProc.isDisconnect = true
                                vpnActionProc.running = true
                            }
                            // Connect to new VPN
                            vpnActionProc.targetVpn = modelData
                            vpnActionProc.isDisconnect = false
                            vpnWidget.isConnecting = true
                            vpnActionProc.running = true
                            vpnWidget.dropdownOpen = false
                        }
                    }
                }
            }
        }
    }
}
