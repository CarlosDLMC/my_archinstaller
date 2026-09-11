import QtQuick
import ".."

// A big mode button for the capture dialogs: icon over a label, with an
// optional second line for context (which monitor, how it works).
Rectangle {
    id: btn

    property string icon: ""
    property string label: ""
    property string hint: ""
    property int iconSize: 52
    property int textSize: 17
    property int subTextSize: 11

    signal activated()

    readonly property bool active: mouse.containsMouse

    color: active
        ? Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.14)
        : Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.04)
    border.width: active ? 2 : 1
    border.color: active
        ? Theme.colWhite
        : Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.18)

    Behavior on color { ColorAnimation { duration: 110 } }
    scale: mouse.pressed ? 0.975 : 1.0
    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

    Column {
        anchors.centerIn: parent
        spacing: 6

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: btn.icon
            color: Theme.colWhite
            opacity: btn.active ? 1.0 : 0.75
            font.family: Theme.fontFamily
            font.pixelSize: btn.iconSize
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: btn.label
            color: Theme.colWhite
            opacity: btn.active ? 1.0 : 0.8
            font.family: Theme.fontFamily
            font.pixelSize: btn.textSize
            font.bold: true
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: btn.hint
            visible: btn.hint !== ""
            color: Theme.colWhite
            opacity: 0.45
            font.family: Theme.fontFamily
            font.pixelSize: btn.subTextSize
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.activated()
    }
}
