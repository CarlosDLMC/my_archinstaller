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
        { value: 60,  label: "60%",  note: "Всегда от сети" },
        { value: 80,  label: "80%",  note: "Смешанный режим" },
        { value: 100, label: "100%", note: "Без ограничения" }
    ]

    function fmtDuration(seconds) {
        if (seconds < 0 || !isFinite(seconds))
            return "—"
        var h = Math.floor(seconds / 3600)
        var m = Math.round((seconds % 3600) / 60)
        if (m === 60) { h += 1; m = 0 }
        if (h > 0)
            return m > 0 ? h + " ч " + m + " мин" : h + " ч"
        return m + " мин"
    }

    function fmtWh(microWattHours) {
        if (!(microWattHours > 0))
            return "—"
        return (microWattHours / 1000000).toFixed(1) + " Вт·ч"
    }

    function stateLabel() {
        switch (BatteryState.chargeState) {
        case "charging":    return "Зарядка"
        case "discharging": return "От батареи"
        case "full":        return "Заряжена"
        case "idle":        return "От сети"
        case "holding":
            // Two different situations wear the same sysfs state, and calling
            // both of them "Holding at 60%" is how you end up staring at a pack
            // that says 97%. Sitting *at* the limit is the limit working;
            // sitting above it is a pack that was already fuller than the limit
            // when it was set, and which will stay there until something
            // actually drains it - charging stops, but nothing discharges a
            // machine that is on mains.
            if (BatteryState.level > BatteryState.limitEnd + 2)
                return "Выше предела · " + BatteryState.limitEnd + "%"
            return "Удержание " + BatteryState.limitEnd + "%"
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
    //  The console: recessed plates (ConsolePlate), a segmented gauge, lamps
    //  and push buttons, in the wallpaper's colours - the «ПУСК · ПУЛЬТ» power
    //  menu's control-panel idea, applied to the card. Labels are small caps.
    // ------------------------------------------------------------------

    component GLabel: Text {
        color: Theme.colDim
        font.pixelSize: panel.labelSize - 1
        font.family: Theme.fontFamily
        font.letterSpacing: 1
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
        rowSpacing: 4
    }

    readonly property bool charging: BatteryState.chargeState === "charging"
    readonly property bool onMains: BatteryState.onAc
    readonly property bool low: BatteryState.chargeState === "discharging" && BatteryState.level <= 15
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
            //  The main instrument: the level as a readout, a lamp for
            //  mains, the gauge with the charge limit as its tick (so a
            //  pack stopped at 60% reads as "arrived", not "stuck"), and
            //  time and draw underneath.
            // ----------------------------------------------------------
            ConsolePlate {
                Item {
                    width: parent.width
                    height: readout.implicitHeight

                    ConsoleCaption {
                        id: levelCap
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "ЗАРЯД"
                    }

                    Text {
                        id: readout
                        anchors.left: levelCap.right
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: BatteryState.level + "%"
                        color: panel.levelColor(BatteryState.level)
                        font.pixelSize: Theme.fontSize + 6
                        font.family: Theme.fontFamily
                        font.bold: true
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        ConsoleLamp {
                            anchors.verticalCenter: parent.verticalCenter
                            lit: panel.onMains
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: panel.stateLabel().toUpperCase()
                            color: Theme.colGrey
                            font.pixelSize: panel.labelSize - 1
                            font.family: Theme.fontFamily
                            font.bold: true
                        }
                    }
                }

                // The limit tick and the buttons bind to effectiveLimit rather
                // than limitEnd, so they move on the click instead of ~170ms
                // later when the write round trip lands.
                SegmentGauge {
                    width: parent.width
                    value: BatteryState.level
                    marker: BatteryState.effectiveLimit
                    tint: panel.low ? Theme.colAlert : Theme.colAccent
                }

                // Nothing to predict and nothing flowing - a pack held at its
                // limit on mains - leaves the row out instead of two dashes.
                Item {
                    visible: BatteryState.secondsLeft >= 0 || BatteryState.drawWatts > 0.2
                    width: parent.width
                    height: timeLine.implicitHeight

                    Text {
                        id: timeLine
                        anchors.left: parent.left
                        text: (panel.charging ? "ДО ПОЛНОЙ  " : "ОСТАЛОСЬ  ")
                              + panel.fmtDuration(BatteryState.secondsLeft)
                        color: Theme.colDim
                        font.pixelSize: panel.labelSize - 2
                        font.family: Theme.fontFamily
                    }
                    Text {
                        anchors.right: parent.right
                        text: (panel.charging ? "ЗАРЯДКА  " : "РАСХОД  ")
                              + (BatteryState.drawWatts > 0.2 ? BatteryState.drawWatts.toFixed(1) + " Вт" : "—")
                        color: Theme.colDim
                        font.pixelSize: panel.labelSize - 2
                        font.family: Theme.fontFamily
                    }
                }
            }

            // ----------------------------------------------------------
            //  The pack's data
            // ----------------------------------------------------------
            ConsolePlate {
                InfoGrid {
                    GLabel { text: "ЁМКОСТЬ" }
                    GValue { text: panel.fmtWh(BatteryState.energyFull) }
                    GLabel { text: "ЦИКЛЫ" }
                    GValue { text: BatteryState.cycles > 0 ? String(BatteryState.cycles) : "—" }

                    GLabel { text: "РЕСУРС" }
                    GValue {
                        text: BatteryState.health > 0 ? BatteryState.health + "%" : "—"
                        color: panel.healthColor(BatteryState.health)
                    }
                    GLabel { text: "ЗАПАС" }
                    GValue { text: panel.fmtWh(BatteryState.energyNow) }
                }
            }

            // ----------------------------------------------------------
            //  One lamp per pack, only where there is more than one pack.
            //  This is where a ThinkPad's two batteries stop being one
            //  number: here the internal one is at 44% health and the
            //  removable one at 82%. A worn-out pack's lamp is colAlert.
            // ----------------------------------------------------------
            ConsolePlate {
                visible: BatteryState.packs.length > 1

                Repeater {
                    model: BatteryState.packs.length > 1 ? BatteryState.packs : []

                    Item {
                        width: parent.width
                        height: Math.round(panel.labelSize * 1.5)

                        ConsoleLamp {
                            id: packLamp
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            lit: true
                            tint: modelData.health > 0 && modelData.health < 60 ? Theme.colAlert : Theme.colAccent
                        }

                        Text {
                            id: packName
                            anchors.left: packLamp.right
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            // From outside (names, titles, SSIDs): plain, never rich text - an <img> in it was fetched.
                            textFormat: Text.PlainText
                            text: modelData.name
                            color: Theme.colWhite
                            font.pixelSize: panel.labelSize
                            font.family: Theme.fontFamily
                            font.bold: true
                        }

                        Text {
                            anchors.left: packName.right
                            anchors.leftMargin: 10
                            anchors.right: packStats.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            // From outside (names, titles, SSIDs): plain, never rich text - an <img> in it was fetched.
                            textFormat: Text.PlainText
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
                            text: modelData.capacity + "% · "
                                  + (modelData.health > 0 ? "ресурс " + modelData.health + "%" : "—")
                                  + " · " + modelData.cycles + " цикл."
                            color: panel.healthColor(modelData.health)
                            font.pixelSize: panel.labelSize - 1
                            font.family: Theme.fontFamily
                        }
                    }
                }
            }

            // ----------------------------------------------------------
            //  Charge limit: push buttons
            // ----------------------------------------------------------
            Item {
                visible: BatteryState.limitWritable
                width: parent.width
                height: limitButtons.implicitHeight

                ConsoleCaption {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "ПРЕДЕЛ ЗАРЯДА"
                }

                Row {
                    id: limitButtons
                    anchors.right: parent.right
                    spacing: 6

                    Repeater {
                        model: panel.presets

                        ConsoleButton {
                            label: modelData.label
                            // A limit the hardware clamped to something
                            // off-preset still has to light one of these up.
                            current: BatteryState.effectiveLimit === modelData.value
                                     || (modelData.value === 100 && BatteryState.effectiveLimit >= 99)
                            onPicked: BatteryState.setLimit(modelData.value)
                        }
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
                horizontalAlignment: Text.AlignRight
                text: {
                    var note = ""
                    for (var i = 0; i < panel.presets.length; i++) {
                        if (BatteryState.effectiveLimit === panel.presets[i].value)
                            note = panel.presets[i].note
                    }
                    if (note === "" && BatteryState.effectiveLimit > 0)
                        note = "Зарядка до " + BatteryState.effectiveLimit + "%"

                    if (BatteryState.effectiveLimit > 0 && BatteryState.effectiveLimit < 100
                        && BatteryState.level > BatteryState.effectiveLimit + 2)
                        note += "  ·  отключите питание, чтобы разрядить до него"

                    return note
                }
                color: Theme.colMuted
                font.pixelSize: panel.labelSize - 2
                font.family: Theme.fontFamily
                wrapMode: Text.WordWrap
            }

            // The hardware has thresholds but the root helper is not installed,
            // so the buttons would be decoration. Say why instead of showing them.
            Text {
                visible: BatteryState.limitSupported && !BatteryState.limitWritable
                width: parent.width
                text: "Предел " + BatteryState.limitEnd
                      + "%. Чтобы менять его здесь, запустите install-scripts/battery_charge_limit.sh."
                color: Theme.colWarn
                font.pixelSize: panel.labelSize - 2
                font.family: Theme.fontFamily
                wrapMode: Text.WordWrap
            }
        }
    }
}
