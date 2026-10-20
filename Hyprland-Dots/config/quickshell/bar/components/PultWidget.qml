import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

// ПУЛЬТ - the control panel at the right end of the bar. It holds the switches
// that do not earn a place on the bar itself: bluetooth (with its paired
// devices, and a search that pairs new ones in place), night light, the power
// profile, and whether the bar shows the CPU and RAM readings at all. It
// replaced three icons - bluetooth, power profile, night light - and the date.
//
// Nothing on the bar shows bluetooth or the profile any more, so neither is
// watched while the card is closed. Both are read when it opens and followed
// over D-Bus only while it stays open; closed, the card costs nothing. The
// old widgets each ran a dbus-monitor (and bluetooth a 10s bluetoothctl poll)
// for the whole session, per screen, to keep an icon current.
DropdownWidget {
    id: pult
    popupWidth: 360
    // Sized to what the body measures, plus the card's 28 of stem and padding.
    property real cardHeight: 200
    popupHeight: Math.ceil(cardHeight) + 28
    stemAlignment: "right"

    // ---- Bluetooth -------------------------------------------------------

    // Whether this machine has bluetooth hardware at all. rfkill as the
    // fallback: a blocked radio empties /sys/class/bluetooth but rfkill still
    // lists it, and blocking is exactly what the off switch does - keying on
    // hci* alone would make the switch vanish once turned off.
    property bool hasAdapter: false
    property bool btPowered: false
    property bool btConnected: false
    property string btConnectedDevice: ""
    property var btDevices: []

    // Search. Discovery runs in the card rather than in blueman-manager: what
    // it finds is listed under НАЙДЕНО, and a click pairs, trusts and connects.
    readonly property bool scanning: btScanProc.running
    property bool scanDone: false
    property var foundDevices: []
    property string pairingMac: ""
    property string pairFailedMac: ""

    // ---- Power profile ---------------------------------------------------

    // False until power-profiles-daemon (or tuned-ppd) answers, so a machine
    // without one shows no profile buttons rather than three dead ones.
    property bool hasProfiles: false
    property string currentProfile: ""
    readonly property var availableProfiles: ["performance", "balanced", "power-saver"]
    // Over D-Bus (busctl comes with systemd), not powerprofilesctl: tuned-ppd
    // serves the same net.hadess.PowerProfiles API but ships no CLI.
    readonly property var ppdActiveProfile: ["net.hadess.PowerProfiles", "/net/hadess/PowerProfiles", "net.hadess.PowerProfiles", "ActiveProfile"]

    function refresh() {
        btPresenceProc.running = true
        profileGetProc.running = true
    }

    // Once at startup, so the card opens at its right size the first time, then
    // on every open (by mouse or by SUPER+CTRL+T / E). A search ends with the
    // card: it is a radio left sweeping for nobody to look at.
    Component.onCompleted: refresh()
    onDropdownOpenChanged: {
        if (dropdownOpen) {
            // Cleared on open, not on close: the stopped search's exit handler
            // lands after the close and would refill the list.
            pult.foundDevices = []
            pult.scanDone = false
            pult.pairFailedMac = ""
            refresh()
        } else {
            stopScan()
        }
    }

    function setBluetooth(on) {
        // Optimistic, for instant feedback; the status read after the power
        // process settles it.
        pult.btPowered = on
        btPowerProc.powerOn = on
        btPowerProc.running = true
        if (on) {
            btStartAppletProc.running = true
        } else {
            stopScan()
            btKillAppletProc.running = true
        }
    }

    function startScan() {
        pult.foundDevices = []
        pult.scanDone = false
        pult.pairFailedMac = ""
        btScanProc.running = true
    }

    // Ending bluetoothctl ends the discovery it started: bluez ties a
    // discovery session to the D-Bus client that asked for it.
    function stopScan() {
        btScanProc.running = false
    }

    function pair(mac) {
        if (pult.pairingMac !== "")
            return
        // Pairing while discovery is still running fails on some controllers.
        stopScan()
        pult.pairFailedMac = ""
        pult.pairingMac = mac
        btPairProc.targetMAC = mac
        btPairProc.running = true
    }

    function setProfile(profile) {
        if (profile === pult.currentProfile)
            return
        pult.currentProfile = profile
        profileSetProc.targetProfile = profile
        profileSetProc.running = true
    }

    function profileLabel(profile) {
        return (({ "performance": "Форсаж", "balanced": "Норма", "power-saver": "Экономия" })[profile] || profile).toUpperCase()
    }

    Process {
        id: btPresenceProc
        command: ["sh", "-c",
            "ls -d /sys/class/bluetooth/hci* >/dev/null 2>&1 && echo yes && exit 0; " +
            "rfkill -n -o TYPE list bluetooth 2>/dev/null | grep -q bluetooth && echo yes || echo no"]
        stdout: SplitParser {
            onRead: data => {
                if (!data) return
                pult.hasAdapter = (data.trim() === "yes")
                if (pult.hasAdapter) {
                    btStatusProc.running = true
                    btConnectedProc.running = true
                    btDevicesProc.running = true
                }
            }
        }
    }

    Process {
        id: btStatusProc
        property string output: ""
        command: ["sh", "-c", "bluetoothctl show | grep -E 'Powered|Name'"]
        stdout: SplitParser {
            onRead: data => {
                if (data) btStatusProc.output += data + "\n"
            }
        }
        onRunningChanged: {
            if (running)
                output = ""
            else
                // No output means no controller (blocked radio, stopped
                // service): that is off, not unchanged.
                pult.btPowered = output.includes("Powered: yes")
        }
    }

    Process {
        id: btConnectedProc
        property string output: ""
        command: ["sh", "-c", "bluetoothctl info 2>/dev/null | grep -E 'Name|Connected' | head -2"]
        stdout: SplitParser {
            onRead: data => {
                if (data) btConnectedProc.output += data + "\n"
            }
        }
        onRunningChanged: {
            if (running) {
                output = ""
            } else if (output.includes("Connected: yes")) {
                pult.btConnected = true
                var nameMatch = output.match(/Name:\s*(.+)/)
                if (nameMatch)
                    pult.btConnectedDevice = nameMatch[1].trim()
            } else {
                pult.btConnected = false
                pult.btConnectedDevice = ""
            }
        }
    }

    Process {
        id: btDevicesProc
        property string output: ""
        command: ["sh", "-c", "bluetoothctl devices Paired"]
        stdout: SplitParser {
            onRead: data => {
                if (data) btDevicesProc.output += data + "\n"
            }
        }
        onRunningChanged: {
            if (running) {
                output = ""
            } else {
                var lines = output.trim().split('\n')
                var devices = []
                for (var i = 0; i < lines.length; i++) {
                    var match = lines[i].match(/Device\s+([0-9A-F:]+)\s+(.+)/)
                    if (match)
                        devices.push({ mac: match[1], name: match[2] })
                }
                pult.btDevices = devices
            }
        }
    }

    // A 30 s discovery. Non-interactive bluetoothctl leaves discovery running
    // until --timeout, then exits - which is what ends the search.
    Process {
        id: btScanProc
        command: ["bluetoothctl", "--timeout", "30", "scan", "on"]
        onRunningChanged: {
            if (!running) {
                pult.scanDone = true
                btFoundProc.running = true
            }
        }
    }

    // What discovery has seen so far: every device bluez knows, less the
    // paired ones (listed above) and the ones that never sent a name - bluez
    // names those after their address, and a room is full of them.
    Process {
        id: btFoundProc
        property string output: ""
        command: ["bluetoothctl", "devices"]
        stdout: SplitParser {
            onRead: data => {
                if (data) btFoundProc.output += data + "\n"
            }
        }
        onRunningChanged: {
            if (running) {
                output = ""
                return
            }
            var paired = {}
            for (var p = 0; p < pult.btDevices.length; p++)
                paired[pult.btDevices[p].mac] = true
            var lines = output.trim().split('\n')
            var found = []
            for (var i = 0; i < lines.length; i++) {
                var match = lines[i].match(/Device\s+([0-9A-F:]+)\s+(.+)/)
                if (!match || paired[match[1]])
                    continue
                if (/^([0-9A-F]{2}-){5}[0-9A-F]{2}$/i.test(match[2].trim()))
                    continue
                found.push({ mac: match[1], name: match[2] })
            }
            pult.foundDevices = found
        }
    }

    Timer {
        interval: 1500
        running: pult.scanning
        repeat: true
        onTriggered: btFoundProc.running = true
    }

    // Pair, trust (so it reconnects by itself later), connect. No agent of
    // its own: a device that needs a code is asked through the session's
    // default agent, and with none bluez pairs "just works", which is what
    // headphones, speakers, mice and pads use.
    Process {
        id: btPairProc
        property string targetMAC: ""
        command: ["sh", "-c",
            "bluetoothctl --timeout 30 pair \"$1\" >/dev/null 2>&1; " +
            "if bluetoothctl info \"$1\" 2>/dev/null | grep -q 'Paired: yes'; then " +
            "bluetoothctl trust \"$1\" >/dev/null 2>&1; " +
            "bluetoothctl --timeout 15 connect \"$1\" >/dev/null 2>&1; echo ok; " +
            "else echo fail; fi",
            "sh", targetMAC]
        stdout: SplitParser {
            onRead: data => {
                if (data && data.trim() === "fail")
                    pult.pairFailedMac = btPairProc.targetMAC
            }
        }
        onRunningChanged: {
            if (running)
                return
            pult.pairingMac = ""
            btDevicesProc.running = true
            btConnectedProc.running = true
            if (pult.pairFailedMac === "")
                pult.foundDevices = pult.foundDevices.filter(d => d.mac !== btPairProc.targetMAC)
        }
    }

    Process {
        id: btConnectProc
        property string targetMAC: ""
        command: ["bluetoothctl", "connect", targetMAC]
    }

    Process {
        id: btDisconnectProc
        command: ["bluetoothctl", "disconnect"]
    }

    // Service + rfkill + controller in one go, as the old bluetooth card did.
    Process {
        id: btPowerProc
        property bool powerOn: true
        command: ["sh", "-c", powerOn ?
            "sudo rfkill unblock bluetooth && sudo systemctl start bluetooth && sleep 0.5 && bluetoothctl power on" :
            "bluetoothctl power off && sudo systemctl stop bluetooth && sudo rfkill block bluetooth"
        ]
        onRunningChanged: {
            if (!running) {
                btStatusProc.running = true
                btConnectedProc.running = true
                btDevicesProc.running = true
            }
        }
    }

    Process {
        id: btKillAppletProc
        command: ["sh", "-c", "killall blueman-applet blueman-tray 2>/dev/null || true"]
    }

    Process {
        id: btStartAppletProc
        command: ["blueman-applet"]
    }

    // Live while open: a device connecting from the list lights its lamp
    // without reopening the card. setpriv --pdeathsig on both links so the pair
    // dies with the bar instead of being orphaned.
    Process {
        id: btMonitor
        command: ["setpriv", "--pdeathsig", "TERM", "sh", "-c", "setpriv --pdeathsig TERM dbus-monitor --system \"type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path_namespace='/org/bluez'\" 2>/dev/null | while read line; do echo 'bt_changed'; done"]
        running: pult.dropdownOpen && pult.hasAdapter
        stdout: SplitParser {
            onRead: data => {
                if (data) btSettle.restart()
            }
        }
    }

    // A search makes bluez emit a stream of RSSI changes; re-read once the
    // stream pauses rather than on every signal.
    Timer {
        id: btSettle
        interval: 400
        onTriggered: {
            btStatusProc.running = true
            btConnectedProc.running = true
        }
    }

    // busctl prints the profile as: s "balanced"
    Process {
        id: profileGetProc
        command: ["busctl", "--system", "get-property"].concat(pult.ppdActiveProfile)
        stdout: SplitParser {
            onRead: data => {
                const m = /"([^"]+)"/.exec(data || "")
                if (m) {
                    pult.currentProfile = m[1]
                    pult.hasProfiles = true
                }
            }
        }
    }

    Process {
        id: profileSetProc
        property string targetProfile: ""
        command: ["busctl", "--system", "set-property"].concat(pult.ppdActiveProfile, ["s", targetProfile])
        onRunningChanged: {
            if (!running && targetProfile !== "")
                profileGetProc.running = true
        }
    }

    Process {
        id: profileMonitor
        command: ["setpriv", "--pdeathsig", "TERM", "sh", "-c", "setpriv --pdeathsig TERM dbus-monitor --system \"type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path='/net/hadess/PowerProfiles'\" 2>/dev/null | while read line; do echo 'profile_changed'; done"]
        running: pult.dropdownOpen && pult.hasProfiles
        stdout: SplitParser {
            onRead: data => {
                if (data) profileGetProc.running = true
            }
        }
    }

    // Icon content. Grey like any idle widget; white while its card is open.
    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "󰒓"
        color: pult.dropdownOpen ? Theme.colWhite : Theme.colGrey
        font.pixelSize: Theme.fontSize + 2
        font.family: Theme.fontFamily
        font.bold: true; style: Text.Outline; styleColor: Theme.colTextShadow
    }

    popupContent: Component {
        Column {
            spacing: 8
            onImplicitHeightChanged: pult.cardHeight = implicitHeight
            Component.onCompleted: pult.cardHeight = implicitHeight

            ConsoleCaption { text: "ПУЛЬТ" }

            ConsolePlate {
                pad: 6
                spacing: 2

                PultSwitch {
                    visible: pult.hasAdapter
                    icon: pult.btConnected ? "󰂱" : "󰂯"
                    label: "BLUETOOTH"
                    detail: pult.btConnected ? pult.btConnectedDevice : ""
                    on: pult.btPowered
                    onToggled: pult.setBluetooth(!pult.btPowered)
                }

                PultSwitch {
                    icon: "󰔎"
                    label: "НОЧНОЙ СВЕТ"
                    on: NightLight.isOn
                    onToggled: NightLight.toggle()
                }

                PultSwitch {
                    icon: "󰍛"
                    label: "ЦП · ОЗУ НА ПАНЕЛИ"
                    on: SystemStats.shown
                    onToggled: SystemStats.setShown(!SystemStats.shown)
                }
            }

            // The paired devices, only while the radio is on.
            Item {
                width: parent.width
                height: searchButton.implicitHeight
                visible: pult.hasAdapter && pult.btPowered

                ConsoleCaption {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "СОПРЯЖЁННЫЕ УСТРОЙСТВА"
                }

                // Starts and stops the search; spins while it runs.
                ConsoleButton {
                    id: searchButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    fontSize: Theme.fontSize - 6
                    icon: "󰍉"
                    busy: pult.scanning
                    label: pult.scanning ? "СТОП" : "ПОИСК"
                    onPicked: pult.scanning ? pult.stopScan() : pult.startScan()
                }
            }

            ConsolePlate {
                visible: pult.hasAdapter && pult.btPowered && pult.btDevices.length > 0
                pad: 4
                spacing: 0

                ListView {
                    id: deviceList
                    readonly property int rowPitch: Math.round((Theme.fontSize - 3) * 1.75) + spacing
                    width: parent.width
                    height: Math.min(count, 6) * rowPitch - spacing
                    clip: true
                    model: pult.btDevices
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: ConsoleRow {
                        width: deviceList.width
                        readonly property bool connected: modelData.name === pult.btConnectedDevice
                        lit: connected
                        icon: "󰂯"
                        label: modelData.name
                        detail: connected ? "ПОДКЛЮЧЕНО" : ""
                        // The card stays open: the monitor above lights the
                        // lamp when the connection lands.
                        onPicked: {
                            if (connected) {
                                btDisconnectProc.running = true
                            } else {
                                btConnectProc.targetMAC = modelData.mac
                                btConnectProc.running = true
                            }
                        }
                    }
                }
            }

            Text {
                visible: pult.hasAdapter && pult.btPowered && pult.btDevices.length === 0
                width: parent.width
                text: "Нет сопряжённых устройств"
                color: Theme.colGrey
                font.pixelSize: Theme.fontSize - 4
                font.family: Theme.fontFamily
                horizontalAlignment: Text.AlignHCenter
            }

            // What the search found. Shown from the moment a search starts
            // until the card closes.
            ConsoleCaption {
                visible: pult.btPowered && (pult.scanning || pult.scanDone)
                text: "НАЙДЕНО"
            }

            ConsolePlate {
                visible: pult.btPowered && pult.foundDevices.length > 0
                pad: 4
                spacing: 0

                ListView {
                    id: foundList
                    readonly property int rowPitch: Math.round((Theme.fontSize - 3) * 1.75) + spacing
                    width: parent.width
                    height: Math.min(count, 6) * rowPitch - spacing
                    clip: true
                    model: pult.foundDevices
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: ConsoleRow {
                        width: foundList.width
                        readonly property bool pairing: modelData.mac === pult.pairingMac
                        readonly property bool failed: modelData.mac === pult.pairFailedMac
                        icon: "󰂯"
                        label: modelData.name
                        detail: pairing ? "СОПРЯЖЕНИЕ…" : (failed ? "ОШИБКА" : "")
                        detailColor: failed ? Theme.colAlert : Theme.colDim
                        onPicked: pult.pair(modelData.mac)

                        Spinner {
                            visible: pairing
                            width: Theme.fontSize - 8
                            height: width
                            color: Theme.colWhite
                        }
                    }
                }
            }

            Text {
                visible: pult.btPowered && pult.foundDevices.length === 0 && (pult.scanning || pult.scanDone)
                width: parent.width
                text: pult.scanning ? "Поиск устройств…" : "Ничего не найдено"
                color: Theme.colGrey
                font.pixelSize: Theme.fontSize - 4
                font.family: Theme.fontFamily
                horizontalAlignment: Text.AlignHCenter
            }

            ConsoleCaption {
                visible: pult.hasProfiles
                text: "РЕЖИМ ПИТАНИЯ"
            }

            Row {
                id: profileRow
                visible: pult.hasProfiles
                width: parent.width
                spacing: 6

                Repeater {
                    model: pult.availableProfiles

                    ConsoleButton {
                        width: (profileRow.width - 2 * profileRow.spacing) / 3
                        fontSize: Theme.fontSize - 6
                        label: pult.profileLabel(modelData)
                        current: modelData === pult.currentProfile
                        onPicked: pult.setProfile(modelData)
                    }
                }
            }
        }
    }
}
