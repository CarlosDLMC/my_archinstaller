import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

DropdownWidget {
    id: vpnWidget
    popupWidth: 260
    // Sized to what the body measures (it reports cardHeight), plus the card's
    // own 28 of stem and padding. The list scrolls past eight tunnels, so the
    // card has a ceiling without anyone doing arithmetic over row heights.
    property real cardHeight: 200
    popupHeight: Math.ceil(cardHeight) + 28
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
        // Set when switching straight from one tunnel to another: both steps then
        // run as ONE command. The click used to start this same Process twice -
        // down, then at once up - but setting running = true on a Process that is
        // still running does nothing, so the old tunnel went down and the new one
        // never came up. The names go in as positional parameters, like the sync
        // commands below, so sh never re-parses them. vpn-switch.sh holds a guard
        // over the moment between down and up: with a plain down-then-up, nothing
        // blocked traffic in between, and it went out in the clear.
        property string switchFrom: ""
        command: switchFrom !== "" ?
            ["sh", "-c", "$HOME/.config/quickshell/bar/scripts/vpn-switch.sh \"$1\" \"$2\"", "sh", switchFrom, targetVpn] :
            (isDisconnect ?
                ["sudo", "wg-quick", "down", targetVpn] :
                ["sudo", "wg-quick", "up", targetVpn])
        onRunningChanged: {
            if (!running) {
                vpnWidget.isConnecting = false
                switchFrom = ""
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

    // Back to local, both halves, and forget the saved home on the way out.
    //
    // Every path that reaches this one ends with no tunnel - the disconnect
    // button, a tunnel that dropped on its own, the stale-cache check at
    // startup - and with no tunnel the saved home has nothing left to do: an IP
    // lookup is the better answer, and the only one that notices you have moved.
    // The next departure captures it again.
    //
    // The per-half resets below deliberately do not forget, because they run
    // while the tunnel is still up.
    Process {
        id: vpnResetProc
        command: ["sh", "-c", "$HOME/.config/quickshell/bar/scripts/vpn-reset.sh all --forget"]
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

    // Popup content: the tunnel's lamp and name with an off button, the two
    // sync toggles as latching push buttons, and the tunnels on a plate.
    popupContent: Component {
        Column {
            spacing: 8
            onImplicitHeightChanged: vpnWidget.cardHeight = implicitHeight
            Component.onCompleted: vpnWidget.cardHeight = implicitHeight

            Item {
                width: parent.width
                height: Math.max(tunnelName.implicitHeight, offButton.visible ? offButton.implicitHeight : 0)

                ConsoleLamp {
                    id: tunnelLamp
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    lit: vpnWidget.activeVpn !== ""
                }

                ConsoleCaption {
                    id: tunnelCaption
                    anchors.left: tunnelLamp.right
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "ТУННЕЛЬ"
                }

                Text {
                    id: tunnelName
                    anchors.left: tunnelCaption.right
                    anchors.leftMargin: 10
                    anchors.right: offButton.visible ? offButton.left : parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    // From outside (names, titles, SSIDs): plain, never rich text - an <img> in it was fetched.
                    textFormat: Text.PlainText
                    text: vpnWidget.activeVpn !== "" ? vpnWidget.activeVpn : "ОТКЛЮЧЁН"
                    color: vpnWidget.activeVpn !== "" ? Theme.colWhite : Theme.colGrey
                    font.pixelSize: Theme.fontSize - 2
                    font.family: Theme.fontFamily
                    font.bold: true
                    elide: Text.ElideRight
                }

                // Disconnect (only while a tunnel is up)
                ConsoleButton {
                    id: offButton
                    visible: vpnWidget.activeVpn !== ""
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "󰅖"
                    minWidth: 0
                    fontSize: Theme.fontSize - 6
                    onPicked: {
                        vpnActionProc.switchFrom = ""
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

            // One toggle per thing that can follow the tunnel: press to send that
            // half to the exit node, press again to bring it home. They are
            // labelled rather than left as two bare glyphs - this is the one
            // place in the card where a misread click moves the system clock,
            // and "󰑓" twice over says nothing about which half is which.
            //
            // Lit (pushed in) means that half is on the tunnel. Without it the
            // card said nothing about whether the weather was following the
            // tunnel - the exact thing that is easy to lose track of once the
            // two halves can disagree.
            Row {
                id: syncRow
                width: parent.width
                spacing: 6
                visible: vpnWidget.activeVpn !== ""

                Repeater {
                    model: [
                        { kind: "time",    icon: "󰥔", label: "ВРЕМЯ" },
                        { kind: "weather", icon: "󰖐", label: "ПОГОДА" }
                    ]

                    delegate: ConsoleButton {
                        required property var modelData

                        readonly property bool isTime: modelData.kind === "time"

                        width: (syncRow.width - syncRow.spacing) / 2
                        fontSize: Theme.fontSize - 6
                        icon: modelData.icon
                        label: modelData.label
                        // Same ring the network card shows while it is
                        // scanning: an indeterminate wait, no progress to report.
                        busy: isTime ? vpnWidget.timeBusy : vpnWidget.weatherBusy
                        enabled: !busy
                        // Following the tunnel. The button is a toggle, so this
                        // is both what it reports and what the next click undoes.
                        current: isTime ? vpnWidget.timeAway : vpnWidget.weatherAway
                        onPicked: {
                            if (isTime)
                                vpnWidget.toggleTime()
                            else
                                vpnWidget.toggleWeather()
                        }
                    }
                }
            }

            // VPN config list
            ConsolePlate {
                visible: vpnWidget.vpnConfigs.length > 0
                pad: 4
                spacing: 0

                ListView {
                    id: vpnListView
                    readonly property int rowPitch: Math.round((Theme.fontSize - 3) * 1.75) + spacing
                    width: parent.width
                    height: Math.min(count, 8) * rowPitch - spacing
                    clip: true
                    model: vpnWidget.vpnConfigs
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: ConsoleRow {
                        width: vpnListView.width
                        lit: modelData === vpnWidget.activeVpn
                        label: modelData
                        interactive: modelData !== vpnWidget.activeVpn
                        onPicked: {
                            // Connected already? Then down and up run as one
                            // command (see switchFrom on vpnActionProc).
                            vpnActionProc.switchFrom = vpnWidget.activeVpn
                            vpnActionProc.targetVpn = modelData
                            vpnActionProc.isDisconnect = false
                            vpnWidget.isConnecting = true
                            vpnActionProc.running = true
                            vpnWidget.dropdownOpen = false
                        }

                        // Location indicator: config names start with a two-letter country code
                        Text {
                            text: {
                                var flags = { de: "🇩🇪", pl: "🇵🇱", ge: "🇬🇪", es: "🇪🇸",
                                              ua: "🇺🇦", lt: "🇱🇹", id: "🇮🇩" }
                                return flags[modelData.substring(0, 2).toLowerCase()] || ""
                            }
                            font.pixelSize: Theme.fontSize + 2
                        }
                    }
                }
            }
        }
    }
}
