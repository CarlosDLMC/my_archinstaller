import QtQuick
import ".."

// A labelled switch, as wide as its dialog: icon + name on the left, the
// switch on the right, and the whole row is the hit target.
Item {
    id: row

    property string icon: ""
    property string label: ""
    property bool checked: false
    property int labelSize: 15

    signal toggled()

    height: Math.round(labelSize * 2.6)

    readonly property int trackW: Math.round(labelSize * 3.2)
    readonly property int trackH: Math.round(labelSize * 1.65)

    Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: row.icon
            color: row.checked ? Theme.colWhite : Theme.colMuted
            font.family: Theme.fontFamily
            font.pixelSize: row.labelSize + 3
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: row.label
            color: row.checked ? Theme.colWhite : Theme.colDim
            font.family: Theme.fontFamily
            font.pixelSize: row.labelSize
        }
    }

    // The switch: a track with a knob that slides, so "on" reads at a glance
    // from shape as well as brightness (the bar is monochrome by design).
    Rectangle {
        id: track
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: row.trackW
        height: row.trackH
        radius: height / 2
        color: row.checked
            ? Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.85)
            : Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.10)
        border.width: 1
        border.color: row.checked
            ? Theme.colWhite
            : Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.22)

        Behavior on color { ColorAnimation { duration: 130 } }

        Rectangle {
            width: parent.height - 6
            height: width
            radius: width / 2
            y: 3
            x: row.checked ? parent.width - width - 3 : 3
            color: row.checked ? Theme.colBg : Theme.colDim

            Behavior on x { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 130 } }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.toggled()
    }
}
