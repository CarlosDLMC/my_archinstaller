import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

DropdownWidget {
    id: wifiWidget
    popupWidth: 240
    popupHeight: Math.min(wifiNetworks.length * 40 + 50, 350)
    popupXOffset: 250

    property string wifiSSID: ""
    property int wifiSignal: 0
    property bool wifiConnected: false
    property var wifiNetworks: []

    function updateWifiStatus() {
        wifiCurrentProc.running = true
    }

    onOpened: wifiScanProc.running = true

    // WiFi current connection
    Process {
        id: wifiCurrentProc
        command: ["sh", "-c", "nmcli -t -f ACTIVE,SSID,SIGNAL device wifi list | grep '^yes' | head -1"]
        stdout: SplitParser {
            onRead: data => {
                if (!data || !data.trim()) {
                    wifiWidget.wifiConnected = false
                    wifiWidget.wifiSSID = ""
                    wifiWidget.wifiSignal = 0
                    return
                }
                var parts = data.trim().split(':')
                if (parts.length >= 3) {
                    wifiWidget.wifiConnected = true
                    wifiWidget.wifiSSID = parts[1]
                    wifiWidget.wifiSignal = parseInt(parts[2]) || 0
                }
            }
        }
        Component.onCompleted: running = true
    }

    // WiFi network scan
    Process {
        id: wifiScanProc
        property string output: ""
        command: ["sh", "-c", "nmcli -t -f SSID,SIGNAL,SECURITY device wifi list | grep -v '^:' | sort -t: -k2 -nr | head -15"]
        stdout: SplitParser {
            onRead: data => {
                if (data) wifiScanProc.output += data + "\n"
            }
        }
        onRunningChanged: {
            if (running) {
                output = ""
            } else if (output) {
                var lines = output.trim().split('\n')
                var networks = []
                var seen = {}
                for (var i = 0; i < lines.length; i++) {
                    var parts = lines[i].split(':')
                    if (parts.length >= 2 && parts[0] && !seen[parts[0]]) {
                        seen[parts[0]] = true
                        networks.push({
                            ssid: parts[0],
                            signal: parseInt(parts[1]) || 0,
                            security: parts[2] || ""
                        })
                    }
                }
                wifiWidget.wifiNetworks = networks
            }
        }
    }

    // WiFi connect process
    Process {
        id: wifiConnectProc
        property string targetSSID: ""
        command: ["nmcli", "device", "wifi", "connect", targetSSID]
    }

    // Event-based NetworkManager monitor
    Process {
        id: nmMonitor
        command: ["nmcli", "monitor"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                if (!data) return
                // Update on any NetworkManager event (connection changes)
                wifiWidget.updateWifiStatus()
            }
        }
        Component.onCompleted: running = true
    }

    // Icon content
    Text {
        id: wifiText
        anchors.verticalCenter: parent.verticalCenter
        text: !wifiConnected ? "󰤭" :
              wifiSignal >= 80 ? "󰤨" :
              wifiSignal >= 60 ? "󰤥" :
              wifiSignal >= 40 ? "󰤢" :
              wifiSignal >= 20 ? "󰤟" : "󰤯"
        color: wifiConnected ? Theme.colNetwork : Theme.colMuted
        font.pixelSize: Theme.fontSize + 4
        font.family: Theme.fontFamily
        font.bold: true
    }

    // Popup content
    popupContent: Component {
        Column {
            spacing: 4

            // Header
            Text {
                text: wifiWidget.wifiConnected ? "󰤨 " + wifiWidget.wifiSSID : "󰤭 Not Connected"
                color: Theme.colFg
                font.pixelSize: Theme.fontSize
                font.family: Theme.fontFamily
                font.bold: true
                width: parent.width
                horizontalAlignment: Text.AlignLeft
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.colMuted
            }

            // Network list
            ListView {
                id: networkListView
                width: parent.width
                height: parent.height - 40
                clip: true
                model: wifiWidget.wifiNetworks
                spacing: 2

                delegate: Rectangle {
                    width: networkListView.width
                    height: 36
                    color: mouseArea.containsMouse ? Qt.rgba(255, 255, 255, 0.1) : "transparent"
                    radius: 6

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 8

                        Text {
                            text: modelData.signal >= 80 ? "󰤨" :
                                  modelData.signal >= 60 ? "󰤥" :
                                  modelData.signal >= 40 ? "󰤢" :
                                  modelData.signal >= 20 ? "󰤟" : "󰤯"
                            color: Theme.colNetwork
                            font.pixelSize: Theme.fontSize
                            font.family: Theme.fontFamily
                        }

                        Text {
                            text: modelData.ssid
                            color: modelData.ssid === wifiWidget.wifiSSID ? Theme.colNetwork : Theme.colFg
                            font.pixelSize: Theme.fontSize - 1
                            font.family: Theme.fontFamily
                            font.bold: modelData.ssid === wifiWidget.wifiSSID
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        Text {
                            text: modelData.security ? "󰌾" : ""
                            color: Theme.colMuted
                            font.pixelSize: Theme.fontSize - 2
                            font.family: Theme.fontFamily
                        }
                    }

                    MouseArea {
                        id: mouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            wifiConnectProc.targetSSID = modelData.ssid
                            wifiConnectProc.running = true
                            wifiWidget.dropdownOpen = false
                        }
                    }
                }
            }
        }
    }
}
