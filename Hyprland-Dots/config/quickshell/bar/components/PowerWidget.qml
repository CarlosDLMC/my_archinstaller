import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

DropdownWidget {
    id: powerWidget
    popupWidth: 140
    popupHeight: 165
    stemAlignment: "left"   // widget now sits at the bar's left edge

    // Power actions
    Process {
        id: lockProc
        command: ["loginctl", "lock-session"]
    }

    Process {
        id: logoutProc
        command: ["hyprctl", "dispatch", "exit"]
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
            // color14, the vivid red in the palette. color12 (the literal
            // border colour) measured 1.62:1 on the bar and read as a
            // shadow of a logo; this is the same red family with presence.
            color: Theme.colAlert
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

    popupContent: Component {
        Column {
            spacing: 4

            // Lock
            Rectangle {
                width: parent.width
                height: 32
                color: lockMouse.containsMouse ? Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.1) : "transparent"
                radius: 6

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    spacing: 10

                    Text {
                        text: "󰌾"
                        color: Theme.colFg
                        font.pixelSize: Theme.fontSize
                        font.family: Theme.fontFamily
                    }
                    Text {
                        text: "Lock"
                        color: Theme.colWhite
                        font.pixelSize: Theme.fontSize
                        font.family: Theme.fontFamily
                    }
                }

                MouseArea {
                    id: lockMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        powerWidget.dropdownOpen = false
                        lockProc.running = true
                    }
                }
            }

            // Logout
            Rectangle {
                width: parent.width
                height: 32
                color: logoutMouse.containsMouse ? Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.1) : "transparent"
                radius: 6

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    spacing: 10

                    Text {
                        text: "󰍃"
                        color: Theme.colFg
                        font.pixelSize: Theme.fontSize
                        font.family: Theme.fontFamily
                    }
                    Text {
                        text: "Logout"
                        color: Theme.colWhite
                        font.pixelSize: Theme.fontSize
                        font.family: Theme.fontFamily
                    }
                }

                MouseArea {
                    id: logoutMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        powerWidget.dropdownOpen = false
                        logoutProc.running = true
                    }
                }
            }

            // Reboot
            Rectangle {
                width: parent.width
                height: 32
                color: rebootMouse.containsMouse ? Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.1) : "transparent"
                radius: 6

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    spacing: 10

                    Text {
                        text: "󰜉"
                        color: "#ffb86c"
                        font.pixelSize: Theme.fontSize
                        font.family: Theme.fontFamily
                    }
                    Text {
                        text: "Reboot"
                        color: Theme.colWhite
                        font.pixelSize: Theme.fontSize
                        font.family: Theme.fontFamily
                    }
                }

                MouseArea {
                    id: rebootMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        powerWidget.dropdownOpen = false
                        rebootProc.running = true
                    }
                }
            }

            // Shutdown
            Rectangle {
                width: parent.width
                height: 32
                color: shutdownMouse.containsMouse ? Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.1) : "transparent"
                radius: 6

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    spacing: 10

                    Text {
                        text: "󰐥"
                        color: "#ff5555"
                        font.pixelSize: Theme.fontSize
                        font.family: Theme.fontFamily
                    }
                    Text {
                        text: "Shutdown"
                        color: Theme.colWhite
                        font.pixelSize: Theme.fontSize
                        font.family: Theme.fontFamily
                    }
                }

                MouseArea {
                    id: shutdownMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        powerWidget.dropdownOpen = false
                        shutdownProc.running = true
                    }
                }
            }
        }
    }
}
