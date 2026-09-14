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
        // nf-md-brightness_4 (U+F050E), the glyph Omarchy uses for this. The
        // plain Unicode sun this replaces (U+2600) was the only icon in the bar
        // that did not come from the Nerd Font, so it was drawn by a fallback
        // face and sat at a different weight from every widget beside it.
        //
        // One glyph for both states, as upstream: on/off is carried by
        // brightness, which is how the rest of this bar marks active.
        text: "󰔎"
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
