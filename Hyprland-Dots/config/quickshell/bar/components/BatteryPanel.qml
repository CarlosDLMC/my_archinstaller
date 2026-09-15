import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."

// The battery card. Readings ported from Omarchy's power panel (omacom/omarchy,
// MIT, DHH) - level, pack size, cycles, draw, time and the "holding" state -
// in this bar's style, minus their power-profile picker, which this bar already
// has as its own widget.
//
// The charge limit section is not from there. Omarchy reads
// charge_control_end_threshold and displays it; nothing in that repo writes it.
// Setting it is the point of this card on a machine that lives on mains, so it
// is written here.
//
// Everything rendered comes from the BatteryState singleton. This file reads no
// files and spawns no processes: it is one screen's view of readings taken once.
Item {
    id: panel

    readonly property int labelSize: Theme.fontSize - 3
    readonly property int headerSize: Theme.fontSize - 5

    // The presets. 60 is the one worth defaulting to on a machine that is
    // plugged in permanently: a cell held at 4.2V ages on the calendar whether
    // or not it is being cycled, and ~3.85V is where that slows down. 80 is the
    // usual compromise for a laptop that travels. 100 is off.
    readonly property var presets: [
        { value: 60,  label: "60%",  note: "Always plugged in" },
        { value: 80,  label: "80%",  note: "Mixed use" },
        { value: 100, label: "Full", note: "No limit" }
    ]

    function fmtDuration(seconds) {
        if (seconds < 0 || !isFinite(seconds))
            return "—"
        var h = Math.floor(seconds / 3600)
        var m = Math.round((seconds % 3600) / 60)
        if (m === 60) { h += 1; m = 0 }
        if (h > 0)
            return m > 0 ? h + "h " + m + "m" : h + "h"
        return m + "m"
    }

    function fmtWh(microWattHours) {
        if (!(microWattHours > 0))
            return "—"
        return (microWattHours / 1000000).toFixed(1) + " Wh"
    }

    function stateLabel() {
        switch (BatteryState.chargeState) {
        case "charging":    return "Charging"
        case "discharging": return "On battery"
        case "full":        return "Full"
        case "idle":        return "Plugged in"
        case "holding":
            // Two different situations wear the same sysfs state, and calling
            // both of them "Holding at 60%" is how you end up staring at a pack
            // that says 97%. Sitting *at* the limit is the limit working;
            // sitting above it is a pack that was already fuller than the limit
            // when it was set, and which will stay there until something
            // actually drains it - charging stops, but nothing discharges a
            // machine that is on mains.
            if (BatteryState.level > BatteryState.limitEnd + 2)
                return "Above limit · " + BatteryState.limitEnd + "%"
            return "Holding at " + BatteryState.limitEnd + "%"
        default:            return "—"
        }
    }

    // colAlert is the bar's only real hue, so it is spent on one state: a pack
    // that is actually draining and nearly out. Sitting at 60% on mains because
    // that is the limit is the desired state, not a warning.
    function levelColor(level) {
        return (BatteryState.chargeState === "discharging" && level <= 15)
            ? Theme.colAlert
            : Theme.colWhite
    }

    // Health is the number that says whether a pack is worth keeping, and it is
    // the one the old widget did not show. Below 60% of design a pack is past
    // the point where a limit can save it. Ordinal, so it is a brightness ramp -
    // grey for a pack that has lost a chunk, colAlert for the genuine extreme.
    function healthColor(health) {
        if (health <= 0) return Theme.colDim
        if (health < 60) return Theme.colAlert
        if (health < 80) return Theme.colGrey
        return Theme.colWhite
    }

    // ------------------------------------------------------------------
    //  Shared cell types, same shapes NetworkPanel uses
    // ------------------------------------------------------------------

    component SectionHeader: Item {
        property string label: ""
        width: parent ? parent.width : 0
        height: Math.round(panel.headerSize * 1.9)

        Text {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2
            text: parent.label
            color: Theme.colMuted
            font.pixelSize: panel.headerSize
            font.family: Theme.fontFamily
            font.bold: true
        }
    }

    component Divider: Rectangle {
        width: parent ? parent.width : 0
        height: 1
        color: Theme.colMuted
        opacity: 0.45
    }

    component GLabel: Text {
        color: Theme.colDim
        font.pixelSize: panel.labelSize
        font.family: Theme.fontFamily
        Layout.alignment: Qt.AlignVCenter
    }

    component GValue: Text {
        color: Theme.colWhite
        font.pixelSize: panel.labelSize
        font.family: Theme.fontFamily
        font.bold: true
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignRight
        Layout.preferredWidth: 0
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
    }

    component InfoGrid: GridLayout {
        width: parent ? parent.width : 0
        columns: 4
        columnSpacing: 14
        rowSpacing: 3
    }

    component Pill: Rectangle {
        property string label: ""
        property bool current: false
        signal picked()
        implicitWidth: pillText.implicitWidth + 18
        implicitHeight: Math.round(panel.labelSize * 1.9)
        radius: height / 2
        color: current
            ? Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.85)
            : (pillMouse.containsMouse
                ? Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.14)
                : Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.06))
        border.width: 1
        border.color: current
            ? Theme.colWhite
            : Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.22)
        Behavior on color { ColorAnimation { duration: 130 } }

        Text {
            id: pillText
            anchors.centerIn: parent
            text: parent.label
            color: parent.current ? Theme.colBg : Theme.colDim
            font.pixelSize: panel.labelSize
            font.family: Theme.fontFamily
            font.bold: parent.current
        }

        MouseArea {
            id: pillMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.picked()
        }
    }

    readonly property real contentHeight: body.implicitHeight

    Flickable {
        anchors.fill: parent
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: body
            width: parent.width
            spacing: 8

            // ----------------------------------------------------------
            //  Header: level and what the pack is doing
            // ----------------------------------------------------------
            Item {
                width: parent.width
                height: Math.round(Theme.fontSize * 1.5)

                Text {
                    id: headerGlyph
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: BatteryState.holding ? "󱊢" : "󰁹"
                    color: panel.levelColor(BatteryState.level)
                    font.pixelSize: Theme.fontSize
                    font.family: Theme.fontFamily
                }

                Text {
                    anchors.left: headerGlyph.right
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: BatteryState.level + "%"
                    color: panel.levelColor(BatteryState.level)
                    font.pixelSize: Theme.fontSize
                    font.family: Theme.fontFamily
                    font.bold: true
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.stateLabel()
                    color: Theme.colDim
                    font.pixelSize: panel.labelSize
                    font.family: Theme.fontFamily
                }
            }

            // ----------------------------------------------------------
            //  Fill bar. The limit is marked on the track, so a pack that
            //  stops at 60% reads as "arrived" rather than "stuck".
            // ----------------------------------------------------------
            Item {
                width: parent.width
                height: 8

                Rectangle {
                    id: track
                    anchors.fill: parent
                    radius: height / 2
                    color: Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.12)
                }

                Rectangle {
                    anchors.left: track.left
                    anchors.verticalCenter: track.verticalCenter
                    height: track.height
                    radius: track.radius
                    width: Math.max(track.height, track.width * BatteryState.level / 100)
                    color: panel.levelColor(BatteryState.level)
                    Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                }

                // The limit marker, the pills and the note all bind to
                // effectiveLimit rather than limitEnd, so they move on the click
                // instead of ~170ms later when the write round trip lands. The
                // state label above does not: it describes what the hardware is
                // doing right now, and that has not changed yet.
                Rectangle {
                    visible: BatteryState.effectiveLimit > 0 && BatteryState.effectiveLimit < 100
                    x: Math.round(track.width * BatteryState.effectiveLimit / 100) - 1
                    width: 2
                    height: track.height + 6
                    anchors.verticalCenter: track.verticalCenter
                    color: Theme.colGrey
                }
            }

            // ----------------------------------------------------------
            //  Stats
            // ----------------------------------------------------------
            InfoGrid {
                GLabel { text: "Capacity" }
                GValue { text: panel.fmtWh(BatteryState.energyFull) }
                GLabel { text: "Cycles" }
                GValue { text: BatteryState.cycles > 0 ? String(BatteryState.cycles) : "—" }

                GLabel { text: "Health" }
                GValue {
                    text: BatteryState.health > 0 ? BatteryState.health + "%" : "—"
                    color: panel.healthColor(BatteryState.health)
                }
                GLabel {
                    text: BatteryState.chargeState === "charging" ? "To full" : "Time left"
                }
                GValue { text: panel.fmtDuration(BatteryState.secondsLeft) }

                GLabel { text: "Charge" }
                GValue { text: panel.fmtWh(BatteryState.energyNow) }
                GLabel {
                    text: BatteryState.chargeState === "charging" ? "Charging at" : "Draw"
                }
                GValue {
                    text: BatteryState.drawWatts > 0.2
                        ? BatteryState.drawWatts.toFixed(1) + " W"
                        : "—"
                }
            }

            // ----------------------------------------------------------
            //  Per-pack breakdown, only where there is more than one pack
            //  to break down. This is where a ThinkPad's two batteries stop
            //  being one number: on this machine the internal one is at 44%
            //  health and the removable one at 82%.
            // ----------------------------------------------------------
            Divider { visible: BatteryState.packs.length > 1 }
            SectionHeader {
                visible: BatteryState.packs.length > 1
                label: "PACKS"
            }

            Repeater {
                model: BatteryState.packs.length > 1 ? BatteryState.packs : []

                Item {
                    width: body.width
                    height: Math.round(panel.labelSize * 1.7)

                    Text {
                        id: packName
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name
                        color: Theme.colDim
                        font.pixelSize: panel.labelSize
                        font.family: Theme.fontFamily
                    }

                    Text {
                        anchors.left: packName.right
                        anchors.leftMargin: 10
                        anchors.right: packStats.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.model
                        color: Theme.colMuted
                        font.pixelSize: panel.labelSize - 2
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                    }

                    Text {
                        id: packStats
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.capacity + "%  ·  "
                              + (modelData.health > 0 ? modelData.health + "% health" : "—")
                              + "  ·  " + modelData.cycles + " cyc"
                        color: panel.healthColor(modelData.health)
                        font.pixelSize: panel.labelSize
                        font.family: Theme.fontFamily
                        font.bold: true
                    }
                }
            }

            // ----------------------------------------------------------
            //  Charge limit
            // ----------------------------------------------------------
            Divider { visible: BatteryState.limitSupported }
            SectionHeader {
                visible: BatteryState.limitSupported
                label: "CHARGE LIMIT"
            }

            Row {
                visible: BatteryState.limitWritable
                width: parent.width
                spacing: 6

                Repeater {
                    model: panel.presets

                    Pill {
                        label: modelData.label
                        // A limit the hardware clamped to something off-preset
                        // still has to light one of these up, or the card shows
                        // three unselected pills and no way to tell what is set.
                        current: BatteryState.effectiveLimit === modelData.value
                                 || (modelData.value === 100 && BatteryState.effectiveLimit >= 99)
                        onPicked: BatteryState.setLimit(modelData.value)
                    }
                }
            }

            // What the selected preset means - and, when the pack is parked
            // above the limit, the thing that is not obvious: a threshold only
            // stops charging. It does not discharge anything, so a pack that
            // was already fuller than the limit stays where it is until the
            // machine actually runs off it. On a desk that can be months.
            Text {
                visible: BatteryState.limitWritable
                width: parent.width
                text: {
                    var note = ""
                    for (var i = 0; i < panel.presets.length; i++) {
                        if (BatteryState.effectiveLimit === panel.presets[i].value)
                            note = panel.presets[i].note
                    }
                    if (note === "" && BatteryState.effectiveLimit > 0)
                        note = "Stops charging at " + BatteryState.effectiveLimit + "%"

                    if (BatteryState.effectiveLimit > 0 && BatteryState.effectiveLimit < 100
                        && BatteryState.level > BatteryState.effectiveLimit + 2)
                        note += "  ·  unplug to bring the pack down to it"

                    return note
                }
                color: Theme.colMuted
                font.pixelSize: panel.labelSize - 2
                font.family: Theme.fontFamily
                wrapMode: Text.WordWrap
            }

            // The hardware has thresholds but the root helper is not installed,
            // so the pills would be decoration. Say why instead of showing them.
            Text {
                visible: BatteryState.limitSupported && !BatteryState.limitWritable
                width: parent.width
                text: "Limit is " + BatteryState.limitEnd
                      + "%. Run install-scripts/battery_charge_limit.sh to change it from here."
                color: Theme.colWarn
                font.pixelSize: panel.labelSize - 2
                font.family: Theme.fontFamily
                wrapMode: Text.WordWrap
            }
        }
    }
}
