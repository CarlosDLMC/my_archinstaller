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

            // The bar scales down on narrower screens so the layout never crowds,
            // but the scale is floored (minScale) so text stays readable instead
            // of shrinking to a literal pixel-copy of the wide monitor. The design
            // width then adapts to the scale so content always fills the screen
            // exactly (no clipping), with the fillWidth center absorbing the slack.
            // Bigger minScale = bigger text, but less room in the center — raise it
            // until CPU starts crowding the clock again, then back off.
            readonly property real referenceWidth: 2560   // your external monitor's width
            readonly property real minScale: 0.90         // readability floor (~20px font on the laptop)
            readonly property real designHeight: 34
            readonly property real uiScale: Math.max(minScale, Math.min(1.0, width / referenceWidth))
            readonly property real designWidth: width / uiScale

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

            // Own namespace, matching the quickshell:<config> convention the
            // overview uses. A Hyprland layerrule blurs this namespace; since
            // the bar has no background of its own, that blurs the wallpaper
            // behind the whole strip - which is the effect being asked for.
            WlrLayershell.namespace: "quickshell:bar"

            implicitHeight: designHeight * uiScale
            // Almost no bar surface: a 20% wash of the background colour
            // under the compositor blur. The exclusion zone is still
            // reserved, so nothing tiles underneath the widgets.
            color: Theme.colBgWash

            margins {
                top: 0
                bottom: 0
                left: 0
                right: 0
            }

            // Content is laid out at the reference (external) size, then scaled
            // down to the actual screen width via the Scale transform below.
            Item {
                id: barContent
                width: barWindow.designWidth
                height: barWindow.designHeight
                transform: Scale {
                    origin.x: 0
                    origin.y: 0
                    xScale: barWindow.uiScale
                    yScale: barWindow.uiScale
                }

            Rectangle {
                anchors.fill: parent
                color: Theme.colBgTransparent  // wash lives on the PanelWindow

                RowLayout {
                    anchors.fill: parent
                    spacing: 0

                    // Left padding
                    Item { width: 12 }

                    // Arch logo, doubling as the power menu. No separator after
                    // it - the logo reads as a mark, not as another widget.
                    PowerWidget {
                        barWindow: barWindow
                        Layout.rightMargin: -6
                    }

                    // Workspaces
                    WorkspaceBar {
                        Layout.preferredHeight: parent.height
                    }

                    // Separator. No margin override - every divider in the bar
                    // uses the same spacing now.
                    Separator {}

                    // Window info (layout + title). The small left margin
                    // balances the divider: the workspace cell to its left ends
                    // with a glyph advance, so without this the rule sits ~15px
                    // from the workspaces but only ~5px from the title.
                    WindowInfo {
                        Layout.preferredHeight: parent.height
                        Layout.preferredWidth: 375
                        Layout.leftMargin: 5
                    }

                    // Center: Time, DND and Weather (fills available space)
                    CenterInfo {
                        id: centerInfo
                        barWindow: barWindow
                        Layout.fillWidth: true
                    }

                    // System stats
                    CpuWidget {}

                    Separator {}

                    MemoryWidget {}

                    Separator {}

                    //DiskWidget {}

                    //Separator {}

                    VolumeWidget {}

                    Separator {}

                    BatteryWidget {
                        barWindow: barWindow
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
                        Layout.rightMargin: 8
                    }

                    // Power profile
                    PowerProfileWidget {
                        barWindow: barWindow
                        Layout.rightMargin: 8
                    }

                    // Night light toggle
                    NightLightWidget {
                        Layout.leftMargin: 8
                    }

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
                        color: Theme.colWhite
                        font.pixelSize: Theme.fontSize
                        font.family: Theme.fontFamily
                        font.bold: true; style: Text.Outline; styleColor: Theme.colTextShadow
                        Layout.alignment: Qt.AlignVCenter

                        Timer {
                            interval: 60000
                            running: true
                            repeat: true
                            onTriggered: dateText.text = Qt.formatDateTime(new Date(), "dd.MM.yyyy")
                        }
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

    // Centred keyboard-layout OSD, one per screen (it shows itself only on
    // the focused monitor). Driven by Hyprland's activelayout event.
    Variants {
        model: Quickshell.screens
        LayoutOsd {}
    }
}
