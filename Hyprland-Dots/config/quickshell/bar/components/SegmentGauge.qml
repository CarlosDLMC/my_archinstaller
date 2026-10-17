import QtQuick
import ".."

// A segmented gauge, as on a console instrument: `segments` cells, the share
// `value` of 100 lit in `tint`, the rest dark. An optional `marker` (0-100)
// stands a tick on the scale - the battery card puts the charge limit there.
Item {
    id: gauge

    property real value: 0
    property real marker: -1
    property int segments: 28
    property int gap: 2
    property color tint: Theme.colAccent

    readonly property int lit: Math.round(Math.max(0, Math.min(100, value)) / 100 * segments)
    readonly property real cell: (width - gap * (segments - 1)) / segments

    implicitHeight: 12

    Row {
        spacing: gauge.gap

        Repeater {
            model: gauge.segments

            Rectangle {
                width: gauge.cell
                height: gauge.height
                radius: 1
                color: index < gauge.lit ? gauge.tint : Qt.rgba(1, 1, 1, 0.07)
                Behavior on color { ColorAnimation { duration: 200 } }
            }
        }
    }

    Rectangle {
        visible: gauge.marker > 0 && gauge.marker < 100
        x: Math.round(gauge.width * gauge.marker / 100) - 1
        anchors.verticalCenter: parent.verticalCenter
        width: 2
        height: gauge.height + 8
        color: Theme.colWhite
    }
}
