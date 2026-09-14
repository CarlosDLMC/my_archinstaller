import QtQuick
import QtQuick.Layouts
import ".."

// Pure renderer - state and the toggle live in the NightLight singleton, which
// watches Hyprsunset.sh's state file instead of polling it.
Item {
    id: nightLightWidget

    implicitWidth: nightLightText.implicitWidth
    implicitHeight: parent.height

    Text {
        id: nightLightText
        anchors.centerIn: parent
        text: "☀"
        color: NightLight.isOn ? Theme.colWhite : Theme.colGrey  // white when on, grey when off
        font.pixelSize: Theme.fontSize + 4
        font.family: Theme.fontFamily
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: NightLight.toggle()
    }
}
