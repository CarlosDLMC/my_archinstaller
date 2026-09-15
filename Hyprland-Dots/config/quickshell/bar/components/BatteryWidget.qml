import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."

// Battery level in the bar, with the full readout and the charge-limit picker
// on click. Every reading comes from the BatteryState singleton, so this file
// is a pure renderer: no Process, no FileView, nothing that costs twice on a
// two-monitor desktop. That was the old widget's shape - it ran Battery.sh and
// a udevadm monitor once per screen.
DropdownWidget {
    id: batteryWidget

    popupWidth: 380
    // Sized to what the card measured rather than to arithmetic over row
    // counts: text height follows the font's line metrics, not pixelSize, so
    // counting rows clips the last one.
    property real cardHeight: 0
    popupHeight: Math.max(200, Math.min(Math.ceil(cardHeight) + 30, 620))
    popupXOffset: 200

    // A desktop has no battery, and an invisible item is dropped from the
    // RowLayout entirely, so it leaves no gap. shell.qml ties the neighbouring
    // separator to this. The singleton gates its own monitor and timer on the
    // same fact, so hiding here really does stop the work - see the "hiding is
    // not stopping" note in CLAUDE.md.
    visible: BatteryState.present

    function barIcon() {
        var level = BatteryState.level
        // Holding at a limit is not charging and not draining. The plug glyph
        // says "on mains" without the charging bolt claiming the pack is
        // filling, which is the thing a limit makes untrue for most of the day.
        if (BatteryState.holding)
            return "󰚥"
        if (BatteryState.chargeState === "charging")
            return "󰂄"
        if (level <= 10) return "󰂎"
        if (level <= 20) return "󰁺"
        if (level <= 30) return "󰁻"
        if (level <= 40) return "󰁼"
        if (level <= 50) return "󰁽"
        if (level <= 60) return "󰁾"
        if (level <= 70) return "󰁿"
        if (level <= 80) return "󰂀"
        if (level <= 90) return "󰂁"
        if (level < 100) return "󰂂"
        return "󰁹"
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: batteryWidget.barIcon() + " " + BatteryState.level + "%"
        // Low is only worth an alert while it is actually draining. Sitting at
        // 60% on mains because that is the limit is the desired state, not a
        // warning, and colouring it red is how you teach yourself to ignore the
        // colour.
        color: (BatteryState.chargeState === "discharging" && BatteryState.level <= 15)
            ? Theme.colAlert
            : Theme.colWhite
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
        font.bold: true; style: Text.Outline; styleColor: Theme.colTextShadow
    }

    // The 60s tick already re-reads the thresholds, so this is not the only path
    // to a limit changed from outside - it just makes the card open on a current
    // reading instead of one up to a minute old.
    onOpened: BatteryState.readThresholds()

    popupContent: Component {
        BatteryPanel {
            anchors.fill: parent
            onContentHeightChanged: batteryWidget.cardHeight = contentHeight
            Component.onCompleted: batteryWidget.cardHeight = contentHeight
        }
    }
}
