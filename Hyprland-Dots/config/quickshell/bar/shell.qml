//@ pragma UseQApplication
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

import "components"

ShellRoot {
    id: root

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: barWindow
            property var modelData
            screen: modelData

            signal closeAllPopups()

            // Listen to Hyprland events to close popups when focus changes
            Connections {
                target: Hyprland
                function onRawEvent(event) {
                    // Close popups when active window changes or layer closes
                    if (event.name === "activewindow" || event.name === "activewindowv2") {
                        barWindow.closeAllPopups()
                    }
                }
            }

            anchors {
                top: true
                left: true
                right: true
            }

            implicitHeight: 34
            color: Theme.colBg

            margins {
                top: 0
                bottom: 0
                left: 0
                right: 0
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.colBg

                RowLayout {
                    anchors.fill: parent
                    spacing: 0

                    // Left padding
                    Item { width: 12 }

                    // Workspaces
                    WorkspaceBar {
                        Layout.preferredHeight: parent.height
                    }

                    // Separator
                    Rectangle {
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 16
                        Layout.alignment: Qt.AlignVCenter
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        color: Theme.colMuted
                    }

                    // Window info (layout + title)
                    WindowInfo {
                        Layout.preferredHeight: parent.height
                        Layout.preferredWidth: 300
                    }

                    // Left spacer
                    Item { Layout.fillWidth: true }

                    // Center: Time, DND and Weather
                    CenterInfo {
                        id: centerInfo
                        barWindow: barWindow
                    }

                    // Right spacer
                    Item { Layout.fillWidth: true }

                    // System stats
                    CpuWidget {
                        Layout.rightMargin: 8
                    }

                    Separator {}

                    MemoryWidget {
                        Layout.rightMargin: 8
                    }

                    Separator {}

                    //DiskWidget {
                    //    Layout.rightMargin: 8
                    //}

                    //Separator {}

                    VolumeWidget {
                        Layout.rightMargin: 8
                    }

                    Separator {}

                    BatteryWidget {
                        Layout.rightMargin: 8
                    }

                    Separator {}

                    // WiFi indicator
                    WifiWidget {
                        barWindow: barWindow
                    }

                    Separator {}

                    // Bluetooth indicator
                    BluetoothWidget {
                        barWindow: barWindow
                    }

                    // Power profile
                    PowerProfileWidget {
                        barWindow: barWindow
                    }

                    // Night light toggle
                    NightLightWidget {}

                    Separator {}

                    // Keyboard layout
                    KeyboardLayoutWidget {}

                    Separator {}

                    // VPN selector
                    VpnWidget {
                        barWindow: barWindow
                        centerInfoRef: centerInfo
                        Layout.rightMargin: 0
                    }

                    Separator {}

                    // Date display
                    Text {
                        id: dateText
                        text: Qt.formatDateTime(new Date(), "dd.MM.yyyy")
                        color: Theme.colFg
                        font.pixelSize: Theme.fontSize
                        font.family: Theme.fontFamily
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter

                        Timer {
                            interval: 60000
                            running: true
                            repeat: true
                            onTriggered: dateText.text = Qt.formatDateTime(new Date(), "dd.MM.yyyy")
                        }
                    }

                    Separator {}

                    // Power menu
                    PowerWidget {
                        barWindow: barWindow
                    }

                    // Right padding
                    Item { width: 8 }
                }

                // Click overlay to close popups - sits on top but propagates clicks
                MouseArea {
                    anchors.fill: parent
                    propagateComposedEvents: true
                    onClicked: (mouse) => {
                        barWindow.closeAllPopups()
                        mouse.accepted = false
                    }
                }
            }
        }
    }
}
