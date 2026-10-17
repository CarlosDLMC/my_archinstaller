import QtQuick
import ".."

// An indicator lamp on a control console: dark glass when off; lit, it glows
// in the wallpaper's accent (or in `tint`, e.g. colAlert for a fault).
Item {
    id: lamp

    property bool lit: false
    property color tint: Theme.colAccent

    implicitWidth: 10
    implicitHeight: 10

    // The halo around a lit lamp.
    Rectangle {
        anchors.centerIn: parent
        width: 18
        height: 18
        radius: 9
        color: lamp.tint
        opacity: lamp.lit ? 0.22 : 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
    }

    Rectangle {
        anchors.centerIn: parent
        width: 9
        height: 9
        radius: 4.5
        color: lamp.lit ? lamp.tint : Qt.darker(Theme.colPlate, 1.3)
        border.width: 1
        border.color: lamp.lit ? Qt.lighter(lamp.tint, 1.25) : Qt.rgba(1, 1, 1, 0.12)
        Behavior on color { ColorAnimation { duration: 160 } }
    }
}
