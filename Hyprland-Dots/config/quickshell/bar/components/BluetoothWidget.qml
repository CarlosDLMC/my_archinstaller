import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

DropdownWidget {
    id: btWidget
    popupWidth: 400
    // Sized to what the body measures, plus the card's 28 of stem and padding.
    property real cardHeight: 160
    popupHeight: Math.ceil(cardHeight) + 28
    popupXOffset: 280

    property bool btPowered: false
    property bool btConnected: false
    property string btConnectedDevice: ""
    property var btDevices: []

    // Whether this machine has bluetooth hardware at all - which is not the
    // same question as whether an adapter is live right now.
    //
    // A desktop without a dongle has neither, and still hides the widget, which
    // is what this was added for. But blocking the radio also empties
    // /sys/class/bluetooth while rfkill goes on listing it, and blocking is
    // exactly what this widget's own power toggle does: keying visibility on
    // hci* alone meant turning bluetooth off from the bar made the control
    // vanish, leaving no way to turn it back on short of restarting the bar.
    // Fall back to rfkill so a blocked radio still renders its "off" icon.
    property bool hasAdapter: false

    visible: hasAdapter

    Process {
        id: btPresenceProc
        command: ["sh", "-c",
            "ls -d /sys/class/bluetooth/hci* >/dev/null 2>&1 && echo yes && exit 0; " +
            "rfkill -n -o TYPE list bluetooth 2>/dev/null | grep -q bluetooth && echo yes || echo no"]
        stdout: SplitParser {
            onRead: data => {
                if (data) btWidget.hasAdapter = (data.trim() === "yes")
            }
        }
        Component.onCompleted: running = true
    }

    onOpened: btDevicesProc.running = true

    // Bluetooth status check
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
            if (running) {
                output = ""
            } else {
                // No output at all means bluetoothctl found no controller
                // (blocked radio, stopped service). That is off, not unchanged
                // - leaving the old value made the bar claim bluetooth was
                // still on after the adapter went away.
                btWidget.btPowered = output.includes("Powered: yes")
            }
        }
        Component.onCompleted: running = true
    }

    // Bluetooth connected device check
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
            } else {
                if (output.includes("Connected: yes")) {
                    btWidget.btConnected = true
                    var nameMatch = output.match(/Name:\s*(.+)/)
                    if (nameMatch) {
                        btWidget.btConnectedDevice = nameMatch[1].trim()
                    }
                } else {
                    btWidget.btConnected = false
                    btWidget.btConnectedDevice = ""
                }
            }
        }
        Component.onCompleted: running = true
    }

    // Bluetooth paired devices list
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
            } else if (output) {
                var lines = output.trim().split('\n')
                var devices = []
                for (var i = 0; i < lines.length; i++) {
                    var match = lines[i].match(/Device\s+([0-9A-F:]+)\s+(.+)/)
                    if (match) {
                        devices.push({
                            mac: match[1],
                            name: match[2]
                        })
                    }
                }
                btWidget.btDevices = devices
            }
        }
        Component.onCompleted: running = true
    }

    // Bluetooth connect process
    Process {
        id: btConnectProc
        property string targetMAC: ""
        command: ["bluetoothctl", "connect", targetMAC]
    }

    // Bluetooth disconnect process
    Process {
        id: btDisconnectProc
        command: ["bluetoothctl", "disconnect"]
    }

    // Bluetooth power toggle - combined script to handle service + rfkill
    Process {
        id: btPowerProc
        property bool powerOn: true
        command: ["sh", "-c", powerOn ?
            "sudo rfkill unblock bluetooth && sudo systemctl start bluetooth && sleep 0.5 && bluetoothctl power on" :
            "bluetoothctl power off && sudo systemctl stop bluetooth && sudo rfkill block bluetooth"
        ]
        onRunningChanged: {
            if (!running) {
                // Immediately check status after toggle completes
                btStatusProc.running = true
                btConnectedProc.running = true
            }
        }
    }

    // Kill blueman-applet and blueman-tray
    Process {
        id: btKillAppletProc
        command: ["sh", "-c", "killall blueman-applet blueman-tray 2>/dev/null || true"]
    }

    // Start blueman-applet
    Process {
        id: btStartAppletProc
        command: ["blueman-applet"]
    }

    // Open blueman-manager for scanning/pairing
    Process {
        id: btManagerProc
        command: ["sh", "-c",
            "if ! systemctl is-active --quiet bluetooth; then " +
            "sudo rfkill unblock bluetooth && sudo systemctl start bluetooth && sleep 1; " +
            "fi && blueman-manager"
        ]
    }

    // Event-based monitoring using dbus-monitor
    // Gated on the adapter existing, like the status probes below. This is an
    // `sh` wrapping a `dbus-monitor` piped into a `while read` loop - three
    // processes that stayed alive on a machine with no bluetooth at all.
    Process {
        id: btMonitor
        // setpriv --pdeathsig on both links: the kernel TERMs the shell the
        // moment the bar dies, however it dies, and dbus-monitor the moment
        // the shell does. A restart or a crash used to leave the pair running
        // as orphans, one more pair each time.
        command: ["setpriv", "--pdeathsig", "TERM", "sh", "-c", "setpriv --pdeathsig TERM dbus-monitor --system \"type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path_namespace='/org/bluez'\" 2>/dev/null | while read line; do echo 'bt_changed'; done"]
        running: btWidget.hasAdapter
        stdout: SplitParser {
            onRead: data => {
                if (data) {
                    btStatusProc.running = true
                    btConnectedProc.running = true
                }
            }
        }
    }

    // Every Process above fires once at startup and then only on user action,
    // so a radio that came or went after the bar started stayed invisible until
    // the bar was restarted. dbus-monitor does not cover it either: bluez has
    // no adapter to emit PropertiesChanged for while the radio is blocked.
    //
    // The presence probe stays unconditional - it is what notices an adapter
    // arriving - but the two bluetoothctl reads behind it are gated, so a
    // machine with no radio pays for one cheap sysfs check here and nothing
    // else.
    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: {
            btPresenceProc.running = true
            if (btWidget.hasAdapter) {
                btStatusProc.running = true
                btConnectedProc.running = true
            }
        }
    }

    // Icon content
    Text {
        id: btText
        anchors.verticalCenter: parent.verticalCenter
        text: !btPowered ? "󰂲" :
              btConnected ? "󰂱" : "󰂯"
        color: !btPowered ? Theme.colMuted :
               btConnected ? Theme.colWhite : Theme.colGrey
        font.pixelSize: Theme.fontSize + 4
        font.family: Theme.fontFamily
        font.bold: true; style: Text.Outline; styleColor: Theme.colTextShadow
    }

    // Popup content: the radio's lamp and power button, then the paired
    // devices on a plate, a lamp lit on the connected one.
    popupContent: Component {
        Column {
            spacing: 8
            onImplicitHeightChanged: btWidget.cardHeight = implicitHeight
            Component.onCompleted: btWidget.cardHeight = implicitHeight

            Item {
                width: parent.width
                height: Math.max(btState.implicitHeight, powerButton.implicitHeight)

                ConsoleLamp {
                    id: btLamp
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    lit: btWidget.btPowered
                }

                ConsoleCaption {
                    id: btCaption
                    anchors.left: btLamp.right
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "BLUETOOTH"
                }

                Text {
                    id: btState
                    anchors.left: btCaption.right
                    anchors.leftMargin: 10
                    anchors.right: powerButton.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    // From outside (names, titles, SSIDs): plain, never rich text - an <img> in it was fetched.
                    textFormat: Text.PlainText
                    text: !btWidget.btPowered ? "ВЫКЛЮЧЕН"
                        : btWidget.btConnected ? btWidget.btConnectedDevice : "ВКЛЮЧЁН"
                    color: btWidget.btConnected ? Theme.colWhite : Theme.colGrey
                    font.pixelSize: Theme.fontSize - 2
                    font.family: Theme.fontFamily
                    font.bold: true
                    elide: Text.ElideRight
                }

                // The radio's power: a latching button, lit while it is on.
                ConsoleButton {
                    id: powerButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    fontSize: Theme.fontSize - 6
                    icon: "󰐥"
                    label: btWidget.btPowered ? "ВКЛ" : "ВЫКЛ"
                    current: btWidget.btPowered
                    onPicked: {
                        // Optimistically update UI immediately for instant feedback
                        var newState = !btWidget.btPowered
                        btWidget.btPowered = newState

                        btPowerProc.powerOn = newState
                        btPowerProc.running = true

                        // Start or stop blueman-applet based on power state
                        if (newState) {
                            // Turning on - start blueman-applet
                            btStartAppletProc.running = true
                        } else {
                            // Turning off - kill blueman-applet
                            btKillAppletProc.running = true
                        }
                    }
                }
            }

            // Paired devices header with manager button
            Item {
                width: parent.width
                height: searchButton.implicitHeight
                visible: btWidget.btPowered

                ConsoleCaption {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "СОПРЯЖЁННЫЕ УСТРОЙСТВА"
                }

                ConsoleButton {
                    id: searchButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    fontSize: Theme.fontSize - 6
                    icon: "󰍉"
                    label: "ПОИСК"
                    onPicked: btManagerProc.running = true
                }
            }

            // Device list
            ConsolePlate {
                visible: btWidget.btPowered && btWidget.btDevices.length > 0
                pad: 4
                spacing: 0

                ListView {
                    id: btDeviceListView
                    readonly property int rowPitch: Math.round((Theme.fontSize - 3) * 1.75) + spacing
                    width: parent.width
                    height: Math.min(count, 8) * rowPitch - spacing
                    clip: true
                    model: btWidget.btDevices
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: ConsoleRow {
                        width: btDeviceListView.width
                        readonly property bool connected: modelData.name === btWidget.btConnectedDevice
                        lit: connected
                        icon: "󰂯"
                        label: modelData.name
                        detail: connected ? "ПОДКЛЮЧЕНО" : ""
                        onPicked: {
                            if (connected) {
                                btDisconnectProc.running = true
                            } else {
                                btConnectProc.targetMAC = modelData.mac
                                btConnectProc.running = true
                            }
                            btWidget.dropdownOpen = false
                        }
                    }
                }
            }

            // Empty state
            Text {
                text: btWidget.btPowered ? "Нет сопряжённых устройств" : "Включите Bluetooth, чтобы увидеть устройства"
                color: Theme.colGrey
                font.pixelSize: Theme.fontSize - 4
                font.family: Theme.fontFamily
                visible: btWidget.btDevices.length === 0 || !btWidget.btPowered
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }
    }
}
