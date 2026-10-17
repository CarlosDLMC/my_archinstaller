import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

DropdownWidget {
    id: powerWidget
    popupWidth: 210   // was 140; fits «ПЕРЕЗАГРУЗКА» and «ВЫКЛЮЧЕНИЕ»
    popupHeight: Math.ceil(cardHeight) + 28
    stemAlignment: "left"   // widget now sits at the bar's left edge

    // Power actions
    Process {
        id: lockProc
        command: ["loginctl", "lock-session"]
    }

    Process {
        id: logoutProc
        command: ["hyprctl", "dispatch", "hl.dsp.exit()"]
    }

    Process {
        id: rebootProc
        command: ["systemctl", "reboot"]
    }

    Process {
        id: shutdownProc
        command: ["systemctl", "poweroff"]
    }

    // Icon with spacing
    Item {
        width: powerIcon.width + 16
        height: parent.height

        Text {
            id: powerIcon
            anchors.centerIn: parent
            text: ""
            // The Hyprland active-window border colour: the bar template maps
            // "border" to {{color12}}, which is the same wallust slot
            // UserDecorations.lua uses for col.active_border. So the logo and
            // the focused window's border match, by request.
            //
            // colLogo, not palBorder: color12 is a dark slot, and on some
            // wallpapers it lands on top of the bar's own background (1.00:1
            // on Catppuccin-Mocha_hanged_man_tree - invisible). colLogo keeps
            // the hue and lifts the lightness only far enough to clear 3:1,
            // so the match survives everywhere it can be seen. See Theme.qml.
            color: Theme.colLogo
            // Sized off the BAR, not the text. barContent is laid out at
            // designHeight and then scaled by uiScale as one unit, so a
            // single multiplier fills the bar height at every resolution -
            // 34px on the 2560 monitor, ~31px on the 1920 laptop, and
            // whatever is right on anything else. The 1.09 accounts for the
            // glyph's ink being ~92% of its em box.
            font.pixelSize: Math.round(barWindow.designHeight * 1.09)
            font.family: Theme.fontFamily
        }
    }

    // The card: four push buttons, as on a console. Power-off carries the one
    // alert glyph - it is the button not to press by accident.
    property real cardHeight: 186

    popupContent: Component {
        Column {
            spacing: 6
            onImplicitHeightChanged: powerWidget.cardHeight = implicitHeight
            Component.onCompleted: powerWidget.cardHeight = implicitHeight

            ConsoleButton {
                width: parent.width
                icon: "󰌾"
                label: "БЛОКИРОВКА"
                onPicked: {
                    powerWidget.dropdownOpen = false
                    lockProc.running = true
                }
            }

            ConsoleButton {
                width: parent.width
                icon: "󰍃"
                label: "ВЫХОД"
                onPicked: {
                    powerWidget.dropdownOpen = false
                    logoutProc.running = true
                }
            }

            ConsoleButton {
                width: parent.width
                icon: "󰜉"
                label: "ПЕРЕЗАГРУЗКА"
                onPicked: {
                    powerWidget.dropdownOpen = false
                    rebootProc.running = true
                }
            }

            ConsoleButton {
                width: parent.width
                icon: "󰐥"
                iconColor: Theme.colAlert
                label: "ВЫКЛЮЧЕНИЕ"
                onPicked: {
                    powerWidget.dropdownOpen = false
                    shutdownProc.running = true
                }
            }
        }
    }
}
