import QtQuick
import ".."

// A big mode button for the capture dialogs, as a key on a control console:
// raised with a dark lower edge, lifted a shade under the pointer, pushed in
// and lit in the wallpaper's accent while pressed. Icon over a label, an
// optional second line for context (which monitor, how it works), and the
// keyboard key that does the same in its corner.
Rectangle {
    id: btn

    property string icon: ""
    property string label: ""
    property string hint: ""
    property string keyHint: ""
    property int iconSize: 52
    property int textSize: 17
    property int subTextSize: 11

    signal activated()

    readonly property bool active: mouse.containsMouse
    readonly property bool down: mouse.pressed

    readonly property color ink: down ? Theme.colBg : (active ? Theme.colWhite : Theme.colGrey)

    color: down ? Theme.colAccent
         : (active ? Qt.lighter(Theme.colPlate, 1.6) : Qt.lighter(Theme.colPlate, 1.25))
    Behavior on color { ColorAnimation { duration: 90 } }

    // The key's lower edge; a pushed-in key has none.
    Rectangle {
        visible: !btn.down
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 4
        radius: btn.radius
        color: Qt.rgba(0, 0, 0, 0.45)
    }

    // The keyboard key, engraved in the corner.
    Text {
        visible: btn.keyHint !== ""
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 10
        text: btn.keyHint
        color: btn.down ? Theme.colBg : Theme.colDim
        font.family: Theme.fontFamily
        font.pixelSize: btn.subTextSize
        font.bold: true
    }

    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: btn.down ? 0 : -2
        spacing: 6

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: btn.icon
            color: btn.ink
            font.family: Theme.fontFamily
            font.pixelSize: btn.iconSize
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: btn.label
            color: btn.ink
            font.family: Theme.fontFamily
            font.pixelSize: btn.textSize
            font.bold: true
            font.letterSpacing: 1
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: btn.hint
            visible: btn.hint !== ""
            color: btn.down ? Theme.colBg : Theme.colDim
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
