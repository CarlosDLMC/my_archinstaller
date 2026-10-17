import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

DropdownWidget {
    id: powerWidget
    popupWidth: 240
    popupHeight: Math.ceil(cardHeight) + 28
    popupXOffset: 200

    property string currentProfile: "balanced"
    property var availableProfiles: ["performance", "balanced", "power-saver"]

    // Profile icons (using nf-md icons)
    function getProfileIcon(profile) {
        switch(profile) {
            case "performance": return "󰓅"  // nf-md-speedometer
            case "balanced": return "󰾅"     // nf-md-scale_balance
            case "power-saver": return "󰌪"  // nf-md-leaf
            default: return "󰾅"
        }
    }

    function getProfileColor(profile) {
        switch(profile) {
            case "performance": return "#f9e2af"  // yellow
            case "balanced": return "#cdd6f4"     // white
            case "power-saver": return "#a6e3a1"  // green
            default: return Theme.colFg
        }
    }

    // The profile daemon over D-Bus (busctl comes with systemd), not the
    // powerprofilesctl CLI: archinstall's "tuned" power-management choice
    // installs tuned-ppd, which serves the same net.hadess.PowerProfiles API
    // but ships no powerprofilesctl, so this widget could neither read nor set
    // a profile there. power-profiles-daemon answers the same calls.
    readonly property var ppdActiveProfile: ["net.hadess.PowerProfiles", "/net/hadess/PowerProfiles", "net.hadess.PowerProfiles", "ActiveProfile"]

    // Get current profile. busctl prints it as: s "balanced"
    Process {
        id: profileGetProc
        command: ["busctl", "--system", "get-property"].concat(powerWidget.ppdActiveProfile)
        stdout: SplitParser {
            onRead: data => {
                const m = /"([^"]+)"/.exec(data || "")
                if (m) {
                    powerWidget.currentProfile = m[1]
                }
            }
        }
        Component.onCompleted: running = true
    }

    // Set profile process
    Process {
        id: profileSetProc
        property string targetProfile: ""
        command: ["busctl", "--system", "set-property"].concat(powerWidget.ppdActiveProfile, ["s", targetProfile])
        onRunningChanged: {
            if (!running && targetProfile !== "") {
                profileGetProc.running = true
            }
        }
    }

    // Event-based monitoring using dbus-monitor
    Process {
        id: profileMonitor
        // setpriv --pdeathsig on both links: the kernel TERMs the shell the
        // moment the bar dies, however it dies, and dbus-monitor the moment
        // the shell does. A restart or a crash used to leave the pair running
        // as orphans, one more pair each time.
        command: ["setpriv", "--pdeathsig", "TERM", "sh", "-c", "setpriv --pdeathsig TERM dbus-monitor --system \"type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path='/net/hadess/PowerProfiles'\" 2>/dev/null | while read line; do echo 'profile_changed'; done"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                if (data) {
                    profileGetProc.running = true
                }
            }
        }
        Component.onCompleted: running = true
    }

    // Icon content
    Text {
        id: powerText
        anchors.verticalCenter: parent.verticalCenter
        text: getProfileIcon(currentProfile)
        color: getProfileColor(currentProfile)
        font.pixelSize: Theme.fontSize + 2
        font.family: Theme.fontFamily
        font.bold: true; style: Text.Outline; styleColor: Theme.colTextShadow
    }

    // The card: one push button per profile, the running one lit - the same
    // vocabulary as the battery card's charge limit. The body reports its own
    // height, so the card is sized to it rather than to a guess.
    property real cardHeight: 170

    popupContent: Component {
        Column {
            spacing: 8
            onImplicitHeightChanged: powerWidget.cardHeight = implicitHeight
            Component.onCompleted: powerWidget.cardHeight = implicitHeight

            ConsoleCaption { text: "РЕЖИМ ПИТАНИЯ" }

            Repeater {
                model: powerWidget.availableProfiles

                ConsoleButton {
                    width: parent.width
                    icon: powerWidget.getProfileIcon(modelData)
                    label: (({ "performance": "Форсаж", "balanced": "Норма", "power-saver": "Экономия" })[modelData] || modelData).toUpperCase()
                    current: modelData === powerWidget.currentProfile
                    onPicked: {
                        if (modelData !== powerWidget.currentProfile) {
                            // Update UI immediately
                            powerWidget.currentProfile = modelData
                            // Then run the command
                            profileSetProc.targetProfile = modelData
                            profileSetProc.running = true
                        }
                        powerWidget.dropdownOpen = false
                    }
                }
            }
        }
    }

    // Periodic timer to keep profile in sync across multiple monitors
    // A safety net behind the dbus-monitor above, which is what actually
    // reports a profile change. At 3000ms this was re-running powerprofilesctl
    // twenty times a minute, per screen, to re-read a value that changes when
    // you click this widget. The monitor covers the real case; this only has
    // to catch it having died.
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: profileGetProc.running = true
    }
}
