import QtQuick
import ".."

// A chunky push button on a control console. Up, it stands on the panel with a
// dark lower edge; `current`, it is pushed in and lit in the wallpaper's accent.
Rectangle {
    id: btn

    property string label: ""
    property bool current: false
    property int fontSize: Theme.fontSize - 4
    signal picked()

    implicitWidth: Math.max(58, caption.implicitWidth + 26)
    implicitHeight: Math.round(fontSize * 2.1)
    radius: 4
    color: current ? Theme.colAccent
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

    Text {
        id: caption
        anchors.centerIn: parent
        anchors.verticalCenterOffset: btn.current ? 0 : -1
        text: btn.label
        color: btn.current ? Theme.colBg : Theme.colGrey
        font.pixelSize: btn.fontSize
        font.family: Theme.fontFamily
        font.bold: true
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.picked()
    }
}
