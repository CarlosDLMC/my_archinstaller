import QtQuick
import Quickshell.Services.Pipewire
import ".."

// A live signal meter for one PipeWire node - the line under the audio card's
// input fader that moves when you speak, as omarchy's audio mixer (wiremix)
// shows beside its inputs.
//
// The peak comes from PwNodePeakMonitor, which opens a capture stream on the
// node. That stream exists only while this item does, and the item lives
// inside the card's Loader, so a closed card is not listening to anything.
//
// Drawn as a SegmentGauge in the console idiom, but not with SegmentGauge
// itself: its 200ms colour fade smears a meter that changes every few
// milliseconds into a glow. Fast rise, slow fall, and a peak-hold tick that
// stays a second before it drops - what a desk meter does, so a word can be
// read after it was spoken.
Item {
    id: meter

    property var node: null
    property bool muted: false
    property int gap: 2
    property int segments: Math.max(12, Math.round(width / 12))

    // The scale is in decibels: a linear peak puts ordinary speech in the
    // first few cells. -60 dB is the floor, 0 dB full scale, and the cells
    // above -6 dB light in the alert colour, where the input starts to clip.
    readonly property real floorDb: -60
    readonly property real hotDb: -6

    // 0-1 positions on the scale: what is shown, and the held peak.
    property real level: 0
    property real hold: 0
    property int holdTicks: 0

    implicitHeight: 6

    function toScale(peak) {
        if (!(peak > 0)) return 0
        var db = 20 * Math.log(peak) / Math.LN10
        return Math.max(0, Math.min(1, (db - floorDb) / -floorDb))
    }

    readonly property real target: muted || !node ? 0 : toScale(monitor.peak)
    readonly property int lit: Math.round(level * segments)
    readonly property int hotFrom: Math.round((hotDb - floorDb) / -floorDb * segments)
    readonly property real cell: (width - gap * (segments - 1)) / segments

    PwNodePeakMonitor {
        id: monitor
        node: meter.node
        enabled: !!meter.node && !meter.muted
    }

    // ~30 fps while the card is open: the fall and the hold need a clock,
    // since a silent input stops changing `peak` at all.
    Timer {
        interval: 33
        repeat: true
        running: meter.visible && !!meter.node
        onTriggered: {
            meter.level = Math.max(meter.target, meter.level - 0.025)
            if (meter.target >= meter.hold) {
                meter.hold = meter.target
                meter.holdTicks = 30
            } else if (meter.holdTicks > 0) {
                meter.holdTicks--
            } else {
                meter.hold = Math.max(meter.level, meter.hold - 0.02)
            }
        }
    }

    Row {
        spacing: meter.gap

        Repeater {
            model: meter.segments

            Rectangle {
                width: meter.cell
                height: meter.height
                radius: 1
                color: index >= meter.lit ? Qt.rgba(1, 1, 1, 0.07)
                     : index >= meter.hotFrom ? Theme.colAlert
                     : Theme.colAccent
            }
        }
    }

    // Peak hold: one cell-wide white tick where the loudest recent peak was.
    Rectangle {
        visible: meter.hold > 0.02
        x: Math.min(meter.width - width,
                    Math.floor(meter.hold * meter.segments) * (meter.cell + meter.gap))
        width: Math.max(2, meter.cell)
        height: meter.height
        radius: 1
        color: Theme.colWhite
    }
}
