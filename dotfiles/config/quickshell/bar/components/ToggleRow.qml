import QtQuick
import ".."

// A labelled switch on a console, as wide as its dialog: a lamp, the icon and
// the name on the left, the keyboard key that flips it, and a latching key on
// the right - pushed in and lit «ВКЛ», or standing up «ВЫКЛ». The whole row is
// the hit target.
Item {
    id: row

    property string icon: ""
    property string label: ""
    property string keyHint: ""
    property bool checked: false
    property int labelSize: 15

    signal toggled()

    height: Math.round(labelSize * 2.6)

    Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12

        ConsoleLamp {
            anchors.verticalCenter: parent.verticalCenter
            lit: row.checked
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: row.icon
            color: row.checked ? Theme.colWhite : Theme.colGrey
            font.family: Theme.fontFamily
            font.pixelSize: row.labelSize + 3
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: row.label
            color: row.checked ? Theme.colWhite : Theme.colGrey
            font.family: Theme.fontFamily
            font.pixelSize: row.labelSize
            font.bold: true
            font.letterSpacing: 1
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: row.keyHint !== ""
            text: row.keyHint
            color: Theme.colDim
            font.family: Theme.fontFamily
            font.pixelSize: row.labelSize - 3
            font.bold: true
        }
    }

    // The latching key. Drawn here rather than as a ConsoleButton so the
    // whole row stays one hit target.
    Rectangle {
        id: key
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Math.round(row.labelSize * 4.2)
        height: Math.round(row.labelSize * 1.9)
        radius: 4
        color: row.checked ? Theme.colAccent
             : (area.containsMouse ? Qt.lighter(Theme.colPlate, 1.6) : Qt.lighter(Theme.colPlate, 1.25))
        Behavior on color { ColorAnimation { duration: 130 } }

        Rectangle {
            visible: !row.checked
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 3
            radius: key.radius
            color: Qt.rgba(0, 0, 0, 0.45)
        }

        Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: row.checked ? 0 : -1
            text: row.checked ? "ВКЛ" : "ВЫКЛ"
            color: row.checked ? Theme.colBg : Theme.colGrey
            font.family: Theme.fontFamily
            font.pixelSize: row.labelSize - 2
            font.bold: true
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.toggled()
    }
}
