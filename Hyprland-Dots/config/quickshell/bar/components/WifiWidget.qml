import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

DropdownWidget {
    id: wifiWidget
    // Width follows the longest SSID instead of a fixed 240px, which was
    // only wide enough for ~14 characters and elided anything longer.
    // Clamped so one absurd name cannot stretch the popup off-screen.
    popupWidth: Math.max(260, Math.min(560, Math.ceil(ssidMetrics.width) + 104))
    popupHeight: Math.min(wifiNetworks.length * 40 + 50, 420)
    popupXOffset: 250

    // Widest SSID in the current list, measured in the real font.
    property string longestSsid: {
        var best = wifiSSID || ""
        for (var i = 0; i < wifiNetworks.length; i++)
            if (wifiNetworks[i].ssid.length > best.length) best = wifiNetworks[i].ssid
        return best
    }
    TextMetrics {
        id: ssidMetrics
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        font.bold: true
        text: wifiWidget.longestSsid
    }

    // SSIDs we already hold credentials for. Note these are the profiles'
    // 802-11-wireless.ssid values, NOT their connection names - nmcli
    // renames duplicates ("Foo 1"), so matching on names gives false
    // negatives and would prompt for a password we already have.
    property var savedProfiles: []
    property bool savedProfilesLoaded: false

    // True while an nmcli connect is in flight. Reconnecting to a network we
    // already have a profile for correctly skips the password view, which
    // left the click with no visible effect at all - this is what the popup
    // and the bar icon key their "connecting" state off.
    readonly property bool connecting: wifiConnectProc.running

    // nmcli -t escapes literal colons in values as "\:", so a naive
    // split(':') corrupts any SSID containing one. Walk the string instead.
    function splitTerse(line) {
        var out = [], cur = "", i = 0
        while (i < line.length) {
            var c = line.charAt(i)
            if (c === "\\" && i + 1 < line.length) { cur += line.charAt(i + 1); i += 2; continue }
            if (c === ":") { out.push(cur); cur = ""; i++; continue }
            cur += c; i++
        }
        out.push(cur)
        return out
    }

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

    function isSaved(ssid) {
        for (var i = 0; i < savedProfiles.length; i++)
            if (savedProfiles[i] === ssid) return true
        return false
    }

    function tryConnect(ssid, security) {
        selectedSSID = ssid
        selectedSecurity = security
        connectAttemptFailed = false
        // "nmcli device wifi connect <ssid>" on a secured network with no
        // stored secret PROMPTS ON STDIN. With no tty attached that can hang
        // instead of returning, so onRunningChanged never fires and neither
        // the password view nor the failure path is ever reached - which is
        // exactly the "click does nothing" symptom.
        //
        // So: anything secured that we do not already have a profile for
        // goes straight to the password view. This is not gated on the
        // profile list having loaded - a needless prompt costs one Escape,
        // a hang costs the whole menu.
        if (security && !isSaved(ssid)) {
            passwordMode = true
            return
        }
        wifiConnectProc.command = ["nmcli", "device", "wifi", "connect", ssid]
        wifiConnectProc.running = true
        connectWatchdog.restart()
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
        // Paint from cache straight away...
        wifiScanProc.running = true
        savedProfilesProc.running = true
        // ...then ask NetworkManager for fresh results and re-read as they
        // arrive. A rescan request returns in ~50ms; the results take a
        // couple of seconds, so refresh twice rather than block on them.
        wifiRescanProc.running = true
        rescanRefresh1.restart()
        rescanRefresh2.restart()
        cancelPasswordEntry()
    }

    // Fire-and-forget rescan request
    Process { id: wifiRescanProc; command: ["nmcli", "device", "wifi", "rescan"] }

    Timer { id: rescanRefresh1; interval: 1400; onTriggered: wifiScanProc.running = true }
    Timer { id: rescanRefresh2; interval: 3200; onTriggered: wifiScanProc.running = true }

    // Saved wireless profile names
    Process {
        id: savedProfilesProc
        property string output: ""
        // One nmcli call per profile, so ~700ms for 18 of them. That is fine
        // because nothing waits on it: the popup paints from cache, and until
        // this lands tryConnect falls back to attempting the connection.
        command: ["sh", "-c", "nmcli -t -f NAME,TYPE connection show | grep ':802-11-wireless$' | cut -d: -f1 | while IFS= read -r n; do nmcli -g 802-11-wireless.ssid connection show \"$n\"; done"]
        stdout: SplitParser { onRead: data => { if (data) savedProfilesProc.output += data + "\n" } }
        Component.onCompleted: running = true
        onRunningChanged: {
            if (running) { output = "" }
            else {
                var names = []
                var lines = output.trim().split("\n")
                for (var i = 0; i < lines.length; i++)
                    if (lines[i].trim()) names.push(lines[i].trim())
                wifiWidget.savedProfiles = names
                wifiWidget.savedProfilesLoaded = names.length > 0
            }
        }
    }

    // WiFi current connection
    Process {
        id: wifiCurrentProc
        property string output: ""
        // --rescan no: read NetworkManager's cache instead of forcing a scan.
        // Without it this fired a full scan on every nmcli-monitor event.
        command: ["sh", "-c", "nmcli -t -f IN-USE,SSID,SIGNAL device wifi list --rescan no | grep '^\\*' | head -1"]
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
                    var parts = wifiWidget.splitTerse(output.trim())
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
        // Cached read, so the popup paints immediately. A rescan is kicked
        // off separately and the list refreshes when results land - the old
        // command blocked for ~1.1s whenever NM's cache had gone stale.
        command: ["sh", "-c", "nmcli -t -f SSID,SIGNAL,SECURITY device wifi list --rescan no | grep -v '^:' | sort -t: -k2 -nr | head -30"]
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
                    var parts = wifiWidget.splitTerse(lines[i])
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

    // If nmcli has not returned in 8s it is almost certainly sitting on its
    // own stdin password prompt. Surface the password view rather than
    // leaving the user staring at an unchanged list.
    Timer {
        id: connectWatchdog
        interval: 8000
        onTriggered: {
            if (wifiConnectProc.running) {
                console.log("[wifi] connect timed out after 8s - showing password view")
                wifiConnectProc.running = false
                if (wifiWidget.selectedSSID && wifiWidget.selectedSecurity) {
                    wifiWidget.connectAttemptFailed = true
                    wifiWidget.passwordMode = true
                }
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
                connectWatchdog.stop()
                console.log("[wifi] connect finished, nmcli said: " + JSON.stringify(output))
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

    // Event-based NetworkManager monitor. A single connection change emits
    // a burst of events, so collapse them into one status read.
    Timer {
        id: monitorDebounce
        interval: 400
        onTriggered: wifiWidget.updateWifiStatus()
    }

    Process {
        id: nmMonitor
        command: ["nmcli", "monitor"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                if (!data) return
                monitorDebounce.restart()
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
        // Arc-style nf-md-wifi rather than the cone-style strength ramp.
        // Signal strength is no longer in the glyph shape - it is still in
        // the dropdown, and the icon dims when the link is down.
        text: wifiConnected ? "󰖩" : "󰖪"
        color: wifiConnected ? Theme.colWhite : Theme.colGrey
        font.pixelSize: Theme.fontSize + 4
        font.family: Theme.fontFamily
        font.bold: true; style: Text.Outline; styleColor: Theme.colTextShadow

        // The popup closes on any activewindow event, so the bar icon has to
        // carry the connecting state too. alwaysRunToEnd means the cycle
        // finishes back at full opacity rather than freezing part-faded.
        opacity: 1
        SequentialAnimation on opacity {
            running: wifiWidget.connecting
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation { from: 1.0; to: 0.35; duration: 450; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 0.35; to: 1.0; duration: 450; easing.type: Easing.InOutQuad }
        }

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
            // Fill the Loader explicitly. Without this the Column's height is
            // implicit from its children, while the ListView below sizes
            // itself from parent.height - a circular dependency that resolved
            // wrong and clipped the first network behind the header.
            anchors.fill: parent
            spacing: 4

            // Header
            Row {
                width: parent.width
                spacing: 4

                Text {
                    text: wifiWidget.connecting ? "󰓦  Connecting to " + wifiWidget.selectedSSID + "…" :
                          wifiWidget.passwordMode ? "󰌾  " + wifiWidget.selectedSSID :
                          wifiWidget.wifiConnected ? "󰤨  " + wifiWidget.wifiSSID : "󰤭  Not Connected"
                    color: wifiWidget.connecting ? Theme.colAlert : Theme.colFg
                    font.pixelSize: Theme.fontSize
                    font.family: Theme.fontFamily
                    font.bold: true; style: Text.Outline; styleColor: Theme.colTextShadow
                    width: parent.width - (disconnectBtn.visible ? disconnectBtn.width + 4 : 0)
                    elide: Text.ElideRight
                }

                Text {
                    id: disconnectBtn
                    visible: wifiWidget.wifiConnected && !wifiWidget.passwordMode
                    text: "󰅖"
                    color: disconnectMouse.containsMouse ? Theme.colAlert : Theme.colMuted
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
                            color: Theme.colOnAlert
                            font.pixelSize: Theme.fontSize - 2
                            font.family: Theme.fontFamily
                            font.bold: true; style: Text.Outline; styleColor: Theme.colTextShadow
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
                                  + (wifiWidget.connecting && modelData.ssid === wifiWidget.selectedSSID
                                     ? "  ·  connecting…" : "")
                            color: wifiWidget.connecting && modelData.ssid === wifiWidget.selectedSSID
                                   ? Theme.colAlert
                                   : modelData.ssid === wifiWidget.wifiSSID ? Theme.colNetwork : Theme.colFg
                            font.pixelSize: Theme.fontSize - 1
                            font.family: Theme.fontFamily
                            font.bold: modelData.ssid === wifiWidget.wifiSSID
                            Layout.fillWidth: true
                            // No elide: popupWidth is derived from the longest
                            // SSID, so full names fit. Only a name past the
                            // 560px clamp can still be cut.
                            elide: Text.ElideNone
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
