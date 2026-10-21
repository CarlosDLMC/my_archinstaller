//@ pragma UseQApplication
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

import "components"
import "overview/modules/overview"

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

            // Close popups when focus moves to another window. mango pushes a
            // new snapshot for many things besides focus (a retitle, a tag
            // change), so only a different focused window id counts.
            Connections {
                target: Mango
                function onFocusedClientIdChanged() {
                    barWindow.closeAllPopups()
                }
            }

            // ---- The cards from the keyboard (BarCards.qml, SUPER+CTRL+<letter>) ----
            // The shortcut opens the card on the focused monitor's bar, with its
            // first control focused; the same shortcut again closes it.
            Connections {
                target: BarCards
                function onToggleRequested(card, screenName) {
                    if (!barWindow.modelData || screenName !== barWindow.modelData.name)
                        return
                    var open = {
                        "audio":     [volumeWidget.dropdownOpen,       () => volumeWidget.navOpen()],
                        "network":   [wifiWidget.dropdownOpen,         () => wifiWidget.navOpen()],
                        "power":     [powerWidget.dropdownOpen,        () => powerWidget.navOpen()],
                        // Bluetooth and the power profile live in the ПУЛЬТ card
                        // now; their two shortcuts both open it.
                        "bluetooth": [pultWidget.dropdownOpen,         () => pultWidget.navOpen()],
                        "calendar":  [centerInfo.calendarVisible,      () => centerInfo.navOpenCalendar()],
                        "weather":   [centerInfo.popupVisible,         () => centerInfo.navOpenWeather()],
                        "vpn":       [vpnWidget.dropdownOpen,          () => vpnWidget.navOpen()],
                        "profile":   [pultWidget.dropdownOpen,         () => pultWidget.navOpen()],
                        "battery":   [batteryWidget.dropdownOpen,      () => batteryWidget.navOpen()],
                        "agent":     [agentWidget.dropdownOpen,        () => agentWidget.navOpen()]
                    }[card]
                    if (!open)
                        return
                    // A hidden widget (no battery, no Wi-Fi, no Claude Code) has
                    // no card: opened anyway, it hung off the screen's left edge.
                    if ((card === "battery" && !batteryWidget.visible)
                        || (card === "network" && !wifiWidget.visible)
                        || (card === "agent" && !agentWidget.visible))
                        return
                    var wasOpen = open[0]
                    barWindow.closeAllPopups()
                    centerInfo.popupVisible = false
                    centerInfo.calendarVisible = false
                    if (!wasOpen)
                        open[1]()
                }
            }

            anchors {
                top: true
                left: true
                right: true
            }

            // Own namespace, matching the quickshell:<config> convention. mango
            // blurs every layer surface under its visible pixels; the bar's wash
            // covers the whole strip, so the wallpaper behind it is blurred -
            // which is the effect being asked for.
            WlrLayershell.namespace: "quickshell:bar"

            implicitHeight: designHeight * uiScale
            // Windows start right under the bar with no gap, the rest of the
            // screen edge has 12 px. mango has one outer gap for top and bottom
            // (gap_outer_vertical=12 in ~/.config/mango/settings.conf), so the
            // bar reserves 12 px less than its height and that gap fills the
            // rest: the windows' top edge lands on the bar's bottom edge. Game
            // mode has no gaps, and the bar reserves all of its height.
            readonly property int outerGap: Mango.gameMode ? 0 : 12
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: Math.max(0, Math.round(implicitHeight) - outerGap)
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

                    // Arch logo with a small Lock/Logout/Reboot/Shutdown dropdown. No separator after
                    // it - the logo reads as a mark, not as another widget.
                    PowerWidget {
                        id: powerWidget
                        barWindow: barWindow
                        Layout.rightMargin: -6
                    }

                    // Workspaces
                    WorkspaceBar {
                        screenName: barWindow.modelData ? barWindow.modelData.name : ""
                        Layout.preferredHeight: parent.height
                    }

                    // Separator. No margin override - every divider in the bar
                    // uses the same spacing now.
                    Separator {}

                    // Window info (layout + title). The small left margin
                    // balances the divider: the workspace cell to its left ends
                    // with a glyph advance, so without this the rule sits ~15px
                    // from the workspaces but only ~5px from the title.
                    //
                    // Not fillWidth. WindowInfo's root is a RowLayout, and a
                    // nested layout fills by default: while its title is hidden
                    // (an empty workspace, right after login) it took all the
                    // slack, CenterInfo shrank to ~1px, its anti-overlap clamp
                    // had no room, and below ~1650 logical px (1366x768, 1080p
                    // at 1.25) the clock was drawn over the CPU readout.
                    WindowInfo {
                        Layout.preferredHeight: parent.height
                        Layout.preferredWidth: 375
                        Layout.fillWidth: false
                        Layout.leftMargin: 5
                    }

                    // Center: Time, DND and Weather (fills available space)
                    CenterInfo {
                        id: centerInfo
                        barWindow: barWindow
                        Layout.fillWidth: true
                    }

                    // Claude Code usage. Hides itself on a machine that has
                    // never run it, so the separator is tied to it.
                    AgentWidget {
                        id: agentWidget
                        barWindow: barWindow
                    }

                    Separator { visible: agentWidget.visible }

                    // System stats. The ПУЛЬТ card can hide them; their
                    // separators go with them.
                    CpuWidget { visible: SystemStats.shown }

                    Separator { visible: SystemStats.shown }

                    MemoryWidget { visible: SystemStats.shown }

                    Separator { visible: SystemStats.shown }

                    //DiskWidget {}

                    //Separator {}

                    // Volume, battery, Wi-Fi and the VPN, divided. Each
                    // separator is tied to the widget after it: a hidden widget
                    // is dropped from the layout, but its separator is a
                    // sibling and would otherwise stay, leaving "| |" on a
                    // machine without that hardware.
                    //
                    // barWindow: the volume readout is a DropdownWidget now -
                    // right-click opens the audio card.
                    VolumeWidget {
                        id: volumeWidget
                        barWindow: barWindow
                    }

                    Separator { visible: batteryWidget.visible }

                    BatteryWidget {
                        id: batteryWidget
                        barWindow: barWindow
                    }

                    Separator { visible: wifiWidget.visible }

                    // WiFi indicator
                    WifiWidget {
                        id: wifiWidget
                        barWindow: barWindow
                    }

                    Separator {}

                    // VPN selector
                    VpnWidget {
                        id: vpnWidget
                        barWindow: barWindow
                        centerInfoRef: centerInfo
                        Layout.rightMargin: 0
                    }

                    Separator {}

                    // Keyboard layout
                    KeyboardLayoutWidget { id: kbLayoutWidget }

                    Separator {}

                    // ПУЛЬТ: bluetooth, night light, power profile and the
                    // stats switch. Took the place of their three icons and of
                    // the date, which the clock's calendar already shows.
                    PultWidget {
                        id: pultWidget
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

    // Centred keyboard-layout OSD, one per screen (it shows itself only on
    // the focused monitor). Driven by LayoutState (mango's layout stream).
    Variants {
        model: Quickshell.screens
        LayoutOsd {}
    }

    // Screen-recording dialog, one per screen (it shows itself only on the
    // focused monitor). Driven by RecordState (IPC target "record").
    Variants {
        model: Quickshell.screens
        OnDemand {
            id: recordOsdSlot
            required property var modelData
            open: RecordState.dialogOpen
            RecordOsd { modelData: recordOsdSlot.modelData }
        }
    }

    // Clipboard picker, same deal. Driven by ClipboardState (IPC "clipboard").
    Variants {
        model: Quickshell.screens
        OnDemand {
            id: clipboardOsdSlot
            required property var modelData
            open: ClipboardState.dialogOpen
            ClipboardOsd { modelData: clipboardOsdSlot.modelData }
        }
    }

    // Screenshot dialog, same deal. Driven by ShotState (IPC "shot").
    Variants {
        model: Quickshell.screens
        OnDemand {
            id: shotOsdSlot
            required property var modelData
            open: ShotState.dialogOpen
            ShotOsd { modelData: shotOsdSlot.modelData }
        }
    }

    // Polkit password prompt, same deal. PolkitState holds the agent, which
    // replaces hyprpolkitagent.
    Variants {
        model: Quickshell.screens
        OnDemand {
            id: polkitOsdSlot
            required property var modelData
            open: PolkitState.open
            PolkitOsd { modelData: polkitOsdSlot.modelData }
        }
    }

    // Power menu «ПУСК · ПУЛЬТ», same deal. Driven by PowerState (IPC "power",
    // CTRL+ALT+P); replaces wlogout.
    Variants {
        model: Quickshell.screens
        OnDemand {
            id: powerOsdSlot
            required property var modelData
            open: PowerState.dialogOpen
            PowerOsd { modelData: powerOsdSlot.modelData }
        }
    }

    // Wallpaper carousel, same deal. Driven by WallpaperState (IPC "wallpaper",
    // SUPER W), which holds the list and the thumbnails.
    Variants {
        model: Quickshell.screens
        OnDemand {
            id: wallpaperOsdSlot
            required property var modelData
            open: WallpaperState.dialogOpen
            WallpaperOsd { modelData: wallpaperOsdSlot.modelData }
        }
    }

    // The workspace overview (SUPER+A): IPC target "overview". Its surfaces
    // map only while it is open.
    Overview {}

    // ...the wallpaper carousel's transition after a pick: two slanted edges
    // opening from the centre, on the layer just above awww's.
    Variants {
        model: Quickshell.screens
        OnDemand {
            id: wallpaperRevealSlot
            required property var modelData
            open: WallpaperState.revealPhase !== ""
            WallpaperReveal { modelData: wallpaperRevealSlot.modelData }
        }
    }
}
