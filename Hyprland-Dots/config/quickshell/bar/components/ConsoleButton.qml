import QtQuick
import ".."

// A chunky push button on a control console. Up, it stands on the panel with a
// dark lower edge; `current`, it is pushed in and lit in the wallpaper's accent
// (or in `tint` - colAlert for a mute). It can carry a glyph before its label,
// or a glyph alone; `busy` puts a Spinner where the glyph was.
Rectangle {
    id: btn

    property string label: ""
    property string icon: ""
    // The glyph's colour while the button is up (shutdown's is colAlert).
    property color iconColor: Theme.colGrey
    property bool busy: false
    property bool current: false
    property color tint: Theme.colAccent
    property int fontSize: Theme.fontSize - 4
    property int minWidth: 58
    signal picked()

    implicitWidth: Math.max(minWidth, face.implicitWidth + 26)
    implicitHeight: Math.round(fontSize * 2.1)
    radius: 4
    opacity: enabled ? 1 : 0.45
    color: current ? tint
         : (area.containsMouse ? Qt.lighter(Theme.colPlate, 1.6) : Qt.lighter(Theme.colPlate, 1.25))
    Behavior on color { ColorAnimation { duration: 130 } }

    // The button's lower edge. A pushed-in button has none: it sits level.
    Rectangle {
        visible: !btn.current
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 3
        radius: btn.radius
        color: Qt.rgba(0, 0, 0, 0.45)
    }

    Row {
        id: face
        anchors.centerIn: parent
        anchors.verticalCenterOffset: btn.current ? 0 : -1
        spacing: 6

        // Fixed box, so swapping the glyph for the spinner does not move the
        // label sideways.
        Item {
            visible: btn.icon !== "" || btn.busy
            width: btn.fontSize + 2
            height: btn.fontSize + 2
            anchors.verticalCenter: parent.verticalCenter

            Text {
                anchors.centerIn: parent
                visible: !btn.busy
                text: btn.icon
                color: btn.current ? Theme.colBg : (area.containsMouse ? Theme.colWhite : btn.iconColor)
                font.pixelSize: btn.fontSize + 2
                font.family: Theme.fontFamily
            }

            Spinner {
                anchors.centerIn: parent
                visible: btn.busy
                width: btn.fontSize - 2
                height: width
                color: btn.current ? Theme.colBg : Theme.colWhite
            }
        }

        Text {
            id: caption
            visible: btn.label !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: btn.label
            color: btn.current ? Theme.colBg : Theme.colGrey
            font.pixelSize: btn.fontSize
            font.family: Theme.fontFamily
            font.bold: true
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.picked()
    }
}
