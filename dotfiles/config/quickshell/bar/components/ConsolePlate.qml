import QtQuick
import ".."

// A recessed plate on a control console: one group of readings, set into the
// card a shade darker than it, with a faint lower lip catching the light.
// The console cards (BatteryPanel first) stack these instead of dividers.
Rectangle {
    id: plate

    default property alias content: inner.data
    property int pad: 10
    property int spacing: 6

    width: parent ? parent.width : 0
    implicitHeight: inner.implicitHeight + 2 * pad
    radius: 5
    color: Theme.colPlate

    // The lower lip: light where the plate meets the panel below it.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: plate.radius
        anchors.rightMargin: plate.radius
        height: 1
        color: Qt.rgba(1, 1, 1, 0.07)
    }

    Column {
        id: inner
        x: plate.pad
        y: plate.pad
        width: plate.width - 2 * plate.pad
        spacing: plate.spacing
    }
}
