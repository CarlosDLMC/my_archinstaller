import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

DropdownWidget {
    id: vpnWidget
    popupWidth: 240
    // Rows are 36 with 2 of spacing; 72 is the header, divider, stem and padding
    // above them, and the sync row costs its 28 plus one gap while a tunnel is
    // up. Same arithmetic as WifiWidget, for the same reason: the old
    // `* 40 + 50` was short of the chrome and drew a half row.
    popupHeight: Math.min(vpnConfigs.length * 38 + 72
                          + (activeVpn !== "" ? 32 : 0), 350)
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

    // ------------------------------------------------------------------
    //  Sync: two buttons, because they are not the same size of change
    // ------------------------------------------------------------------
    //  The weather half rewrites one string in ~/.cache and the bar picks it up.
    //  The clock half runs `timedatectl set-timezone`, which moves the system
    //  clock for every process on the machine - journal timestamps, file mtimes,
    //  every other app. They used to be one button, so wanting the weather to
    //  follow the tunnel meant taking the clock with it.
    //
    //  In both: targetVpn goes in as a positional parameter, not glued onto the
    //  command string. Concatenated, the config name was re-parsed by sh:
    //  "us west" arrived as $1="us" with the rest dropped (a silent, wrong
    //  sync), and anything with a ;, | or $() in it would have run as a
    //  command. The names come from /etc/wireguard, which only root can
    //  write, so this was never reachable by anyone who was not already
    //  root - it is the quiet truncation that actually bites.
    //
    //  Still sh -c rather than a bare argv array, because $HOME has to be
    //  expanded by something, and Process does not do it.

    Process {
        id: timeSyncProc
        property string targetVpn: ""
        command: ["sh", "-c", "$HOME/.config/quickshell/bar/scripts/vpn-sync.sh \"$1\" time", "sh", targetVpn]
        onRunningChanged: {
            if (!running && centerInfoRef)
                centerInfoRef.refreshTimezone()
        }
    }

    Process {
        id: weatherSyncProc
        property string targetVpn: ""
        command: ["sh", "-c", "$HOME/.config/quickshell/bar/scripts/vpn-sync.sh \"$1\" weather", "sh", targetVpn]
        onRunningChanged: {
            if (!running && centerInfoRef)
                centerInfoRef.refreshWeather()
        }
    }

    //  ...and the same two halves in reverse. These are what make the buttons
    //  toggles rather than one-way switches: either half can come home while the
    //  tunnel stays up, which is the case the old single reset could not express
    //  - it only ever ran on disconnect.
    Process {
        id: timeResetProc
        command: ["sh", "-c", "$HOME/.config/quickshell/bar/scripts/vpn-reset.sh time"]
        onRunningChanged: {
            if (!running && centerInfoRef)
                centerInfoRef.refreshTimezone()
        }
    }

    Process {
        id: weatherResetProc
        command: ["sh", "-c", "$HOME/.config/quickshell/bar/scripts/vpn-reset.sh weather"]
        onRunningChanged: {
            if (!running && centerInfoRef)
                centerInfoRef.refreshWeather()
        }
    }

    //  Which halves are currently following the tunnel. CenterInfo already owns
    //  both answers - it watches those two cache files to render the clock and
    //  the weather - so the card reads them from there rather than watching the
    //  same files again, once per screen.
    readonly property bool timeAway: centerInfoRef ? centerInfoRef.customTimezone !== "" : false
    readonly property bool weatherAway: centerInfoRef ? centerInfoRef.weatherCity !== "" : false

    //  A floor under how briefly the spinner can show. Setting a timezone is
    //  effectively instant, so without this the clock button's spinner appears
    //  and disappears inside one frame, which reads as a click that did nothing
    //  rather than as work that happened.
    Timer { id: timeSpinFloor; interval: 450; repeat: false }
    Timer { id: weatherSpinFloor; interval: 450; repeat: false }

    readonly property bool timeBusy:
        timeSyncProc.running || timeResetProc.running || timeSpinFloor.running
    readonly property bool weatherBusy:
        weatherSyncProc.running || weatherResetProc.running || weatherSpinFloor.running

    function toggleTime() {
        timeSpinFloor.restart()
        if (vpnWidget.timeAway) {
            timeResetProc.running = true
        } else {
            timeSyncProc.targetVpn = vpnWidget.activeVpn
            timeSyncProc.running = true
        }
    }

    function toggleWeather() {
        weatherSpinFloor.restart()
        if (vpnWidget.weatherAway) {
            weatherResetProc.running = true
        } else {
            weatherSyncProc.targetVpn = vpnWidget.activeVpn
            weatherSyncProc.running = true
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
        // Colour is the only on/off signal, so the two ends differ in both
        // hue and lightness: neutral grey when down, the one saturated
        // colour in the palette when up. This is the single place the alert
        // hue is used for something that is not a problem - a live tunnel is
        // worth seeing at a glance.
        color: vpnWidget.activeVpn ? Theme.colAlert : Theme.colFaint
        font.pixelSize: Theme.fontSize + 4
        font.family: Theme.fontFamily
        font.bold: true; style: Text.Outline; styleColor: Theme.colTextShadow
    }

    // Popup content
    popupContent: Component {
        Column {
            spacing: 4

            // Header
            RowLayout {
                id: headerRow
                width: parent.width
                spacing: 8

                Text {
                    text: vpnWidget.activeVpn ? "󰖂 " + vpnWidget.activeVpn : "󰖂 Disconnected"
                    color: Theme.colFg
                    font.pixelSize: Theme.fontSize
                    font.family: Theme.fontFamily
                    font.bold: true; style: Text.Outline; styleColor: Theme.colTextShadow
                    Layout.fillWidth: true
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
                id: headerDivider
                width: parent.width
                height: 1
                color: Theme.colMuted
            }

            // One toggle per thing that can follow the tunnel: press to send that
            // half to the exit node, press again to bring it home. They are
            // labelled rather than left as two bare glyphs - this is the one
            // place in the card where a misread click moves the system clock,
            // and "󰑓" twice over says nothing about which half is which.
            Row {
                id: syncRow
                width: parent.width
                height: 28
                spacing: 6
                visible: vpnWidget.activeVpn !== ""

                Repeater {
                    model: [
                        { kind: "time",    icon: "󰥔", label: "Time" },
                        { kind: "weather", icon: "󰖐", label: "Weather" }
                    ]

                    delegate: Rectangle {
                        required property var modelData

                        readonly property bool isTime: modelData.kind === "time"
                        readonly property bool busy: isTime ? vpnWidget.timeBusy
                                                            : vpnWidget.weatherBusy
                        // Following the tunnel. The button is a toggle, so this
                        // is both what it reports and what the next click undoes.
                        readonly property bool away: isTime ? vpnWidget.timeAway
                                                            : vpnWidget.weatherAway

                        width: (syncRow.width - syncRow.spacing) / 2
                        height: syncRow.height
                        radius: 6
                        // Filled means this half is on the tunnel: the bar's own
                        // white-active/grey-idle rule, which is the only state
                        // signal a 28px button has room for. Without it the card
                        // said nothing about whether the weather was following
                        // the tunnel - the exact thing that is easy to lose track
                        // of once the two halves can disagree.
                        color: away
                            ? Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b,
                                      syncMouse.containsMouse ? 0.26 : 0.18)
                            : Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b,
                                      syncMouse.containsMouse ? 0.14 : 0.04)
                        Behavior on color { ColorAnimation { duration: 110 } }

                        Row {
                            anchors.centerIn: parent
                            spacing: 6

                            // Fixed box, so swapping the glyph for the spinner
                            // does not shift the label sideways.
                            Item {
                                width: Theme.fontSize
                                height: Theme.fontSize
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.centerIn: parent
                                    visible: !busy
                                    text: modelData.icon
                                    color: away || syncMouse.containsMouse
                                        ? Theme.colWhite : Theme.colGrey
                                    font.pixelSize: Theme.fontSize
                                    font.family: Theme.fontFamily
                                }

                                // Same ring the network card shows while it is
                                // scanning: an indeterminate wait, no progress to
                                // report.
                                Spinner {
                                    anchors.centerIn: parent
                                    visible: busy
                                    width: Theme.fontSize - 3
                                    height: width
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                color: away || syncMouse.containsMouse
                                    ? Theme.colWhite : Theme.colGrey
                                font.pixelSize: Theme.fontSize - 2
                                font.family: Theme.fontFamily
                                style: Text.Outline; styleColor: Theme.colTextShadow
                            }
                        }

                        MouseArea {
                            id: syncMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !busy
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (isTime)
                                    vpnWidget.toggleTime()
                                else
                                    vpnWidget.toggleWeather()
                            }
                        }
                    }
                }
            }

            // VPN config list
            ListView {
                id: vpnListView
                width: parent.width
                // Measured off the siblings above rather than a constant: the
                // old `parent.height - 40` predates the sync row and would cut
                // the list short by exactly its height whenever a tunnel is up.
                height: parent.height - headerRow.height - headerDivider.height
                        - (syncRow.visible ? syncRow.height + parent.spacing : 0)
                        - parent.spacing * 2
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
