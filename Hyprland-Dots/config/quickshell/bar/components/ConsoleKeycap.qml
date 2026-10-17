import QtQuick
import ".."

// A key hint on a console: the key on a small raised cap, what it does beside
// it in dim capitals. Used along the bottom of the centred dialogs.
Row {
    id: hint

    property string keys: ""
    property string label: ""
    property int fontSize: Theme.fontSize - 7

    spacing: 6

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: keyText.implicitWidth + 12
        height: keyText.implicitHeight + 4
        radius: 3
        color: Qt.lighter(Theme.colPlate, 1.4)

        // The cap's lower edge.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 2
            radius: parent.radius
            color: Qt.rgba(0, 0, 0, 0.45)
        }

        Text {
            id: keyText
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -1
            text: hint.keys
            color: Theme.colWhite
            font.family: Theme.fontFamily
            font.pixelSize: hint.fontSize
            font.bold: true
        }
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: hint.label
        color: Theme.colGrey
        font.family: Theme.fontFamily
        font.pixelSize: hint.fontSize
        font.bold: true
        font.letterSpacing: 1
    }
}
