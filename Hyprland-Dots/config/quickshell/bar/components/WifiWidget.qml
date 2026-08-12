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

    // Password entry mode
    property bool passwordMode: false
    property string selectedSSID: ""
    property string selectedSecurity: ""
    property string enteredPassword: ""
    property bool connectAttemptFailed: false

    function updateWifiStatus() {
        wifiCurrentProc.running = true
    }

    function tryConnect(ssid, security) {
        selectedSSID = ssid
        selectedSecurity = security
        connectAttemptFailed = false
        // Try connecting without password first (works for open or saved networks)
        wifiConnectProc.command = ["nmcli", "device", "wifi", "connect", ssid]
        wifiConnectProc.running = true
    }

    function connectWithPassword() {
        if (selectedSSID && enteredPassword) {
            wifiConnectProc.command = ["nmcli", "device", "wifi", "connect", selectedSSID, "password", enteredPassword]
            wifiConnectProc.running = true
            passwordMode = false
            enteredPassword = ""
        }
    }

    function cancelPasswordEntry() {
        passwordMode = false
        selectedSSID = ""
        selectedSecurity = ""
        enteredPassword = ""
        connectAttemptFailed = false
    }

    onOpened: {
        wifiScanProc.running = true
        cancelPasswordEntry()
    }

    // WiFi current connection
    Process {
        id: wifiCurrentProc
        property string output: ""
        command: ["sh", "-c", "nmcli -t -f ACTIVE,SSID,SIGNAL device wifi list | grep '^yes' | head -1"]
        stdout: SplitParser {
            onRead: data => {
                if (data) wifiCurrentProc.output += data
            }
        }
        onRunningChanged: {
            if (running) {
                output = ""
            } else {
                // Process finished - check output
                if (!output || !output.trim()) {
                    wifiWidget.wifiConnected = false
                    wifiWidget.wifiSSID = ""
                    wifiWidget.wifiSignal = 0
                } else {
                    var parts = output.trim().split(':')
                    if (parts.length >= 3) {
                        wifiWidget.wifiConnected = true
                        wifiWidget.wifiSSID = parts[1]
                        wifiWidget.wifiSignal = parseInt(parts[2]) || 0
                    }
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
        property string output: ""
        stdout: SplitParser {
            onRead: data => {
                if (data) wifiConnectProc.output += data
            }
        }
        stderr: SplitParser {
            onRead: data => {
                if (data) wifiConnectProc.output += data
            }
        }
        onRunningChanged: {
            if (running) {
                output = ""
            } else {
                // Refresh status after connect/disconnect
                wifiCurrentProc.running = true

                // Check if connection failed and we need password
                var failed = output.toLowerCase().includes("error") ||
                            output.toLowerCase().includes("secrets were required") ||
                            output.toLowerCase().includes("no suitable connection") ||
                            output.toLowerCase().includes("failed")

                if (failed && wifiWidget.selectedSSID && wifiWidget.selectedSecurity && !wifiWidget.passwordMode) {
                    // Connection failed on secured network - show password input
                    wifiWidget.connectAttemptFailed = true
                    wifiWidget.passwordMode = true
                } else if (!failed && wifiWidget.selectedSSID) {
                    // Connection succeeded - close dropdown
                    wifiWidget.dropdownOpen = false
                    wifiWidget.cancelPasswordEntry()
                }
            }
        }
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

    // Process to open nm-connection-editor
    Process {
        id: nmEditorProc
        command: ["nm-connection-editor"]
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
        font.bold: true; style: Text.Outline; styleColor: Qt.rgba(color.r, color.g, color.b, 0.3)

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                    nmEditorProc.running = true
                }
            }
        }
    }

    // Popup content
    popupContent: Component {
        Column {
            spacing: 4

            // Header
            Row {
                width: parent.width
                spacing: 4

                Text {
                    text: wifiWidget.passwordMode ? "󰌾  " + wifiWidget.selectedSSID :
                          wifiWidget.wifiConnected ? "󰤨  " + wifiWidget.wifiSSID : "󰤭  Not Connected"
                    color: Theme.colFg
                    font.pixelSize: Theme.fontSize
                    font.family: Theme.fontFamily
                    font.bold: true; style: Text.Outline; styleColor: Qt.rgba(color.r, color.g, color.b, 0.3)
                    width: parent.width - (disconnectBtn.visible ? disconnectBtn.width + 4 : 0)
                    elide: Text.ElideRight
                }

                Text {
                    id: disconnectBtn
                    visible: wifiWidget.wifiConnected && !wifiWidget.passwordMode
                    text: "󰅖"
                    color: disconnectMouse.containsMouse ? "#ff5555" : Theme.colMuted
                    font.pixelSize: Theme.fontSize
                    font.family: Theme.fontFamily

                    MouseArea {
                        id: disconnectMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            wifiConnectProc.command = ["nmcli", "connection", "down", wifiWidget.wifiSSID]
                            wifiConnectProc.running = true
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.colMuted
            }

            // Password entry view
            Column {
                visible: wifiWidget.passwordMode
                width: parent.width
                spacing: 8

                Item { width: 1; height: 4 }

                Text {
                    text: "Enter password:"
                    color: Theme.colMuted
                    font.pixelSize: Theme.fontSize - 2
                    font.family: Theme.fontFamily
                }

                Rectangle {
                    width: parent.width
                    height: 32
                    color: Qt.rgba(255, 255, 255, 0.1)
                    radius: 6
                    border.color: passwordInput.activeFocus ? Theme.colNetwork : Theme.colMuted
                    border.width: 1

                    TextInput {
                        id: passwordInput
                        anchors.fill: parent
                        anchors.margins: 8
                        color: Theme.colFg
                        font.pixelSize: Theme.fontSize - 1
                        font.family: Theme.fontFamily
                        echoMode: TextInput.Password
                        clip: true
                        onTextChanged: wifiWidget.enteredPassword = text
                        Keys.onReturnPressed: wifiWidget.connectWithPassword()
                        Keys.onEscapePressed: wifiWidget.cancelPasswordEntry()
                        Component.onCompleted: {
                            if (wifiWidget.passwordMode) forceActiveFocus()
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: 8

                    Rectangle {
                        width: (parent.width - 8) / 2
                        height: 30
                        color: cancelMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.15) : Qt.rgba(255, 255, 255, 0.1)
                        radius: 6

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: Theme.colFg
                            font.pixelSize: Theme.fontSize - 2
                            font.family: Theme.fontFamily
                        }

                        MouseArea {
                            id: cancelMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: wifiWidget.cancelPasswordEntry()
                        }
                    }

                    Rectangle {
                        width: (parent.width - 8) / 2
                        height: 30
                        color: connectMouse.containsMouse ? Qt.rgba(Theme.colNetwork.r, Theme.colNetwork.g, Theme.colNetwork.b, 0.8) : Theme.colNetwork
                        radius: 6

                        Text {
                            anchors.centerIn: parent
                            text: "Connect"
                            color: "#1e1e2e"
                            font.pixelSize: Theme.fontSize - 2
                            font.family: Theme.fontFamily
                            font.bold: true; style: Text.Outline; styleColor: Qt.rgba(color.r, color.g, color.b, 0.3)
                        }

                        MouseArea {
                            id: connectMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: wifiWidget.connectWithPassword()
                        }
                    }
                }
            }

            // Network list
            ListView {
                id: networkListView
                visible: !wifiWidget.passwordMode
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
                            // Always try to connect first (works for open or saved networks)
                            // If it fails and has security, password input will be shown
                            wifiWidget.tryConnect(modelData.ssid, modelData.security)
                        }
                    }
                }
            }
        }
    }
}
