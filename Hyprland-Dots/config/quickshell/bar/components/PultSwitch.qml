import QtQuick
import ".."

// One on/off line of the ПУЛЬТ card. The card vocabulary, as in the bluetooth
// header it replaces: a lamp and a label carry the state, and a latching
// ConsoleButton (lit while on) is the switch. Only the button takes focus, so
// CardKeys walks straight from switch to switch.
Item {
    id: sw

    property string icon: ""
    property string label: ""
    // Optional reading after the label - the connected bluetooth device.
    property string detail: ""
    property bool on: false

    signal toggled()

    width: parent ? parent.width : 0
    implicitHeight: Math.max(labelText.implicitHeight, button.implicitHeight) + 4

    ConsoleLamp {
        id: lamp
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        lit: sw.on
    }

    Text {
        id: glyph
        anchors.left: lamp.right
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.fontSize - 2
        horizontalAlignment: Text.AlignHCenter
        text: sw.icon
        color: sw.on ? Theme.colWhite : Theme.colGrey
        font.pixelSize: Theme.fontSize - 4
        font.family: Theme.fontFamily
    }

    Text {
        id: labelText
        anchors.left: glyph.right
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: sw.label
        color: sw.on ? Theme.colWhite : Theme.colGrey
        font.pixelSize: Theme.fontSize - 7
        font.family: Theme.fontFamily
        font.bold: true
        font.letterSpacing: 1
    }

    Text {
        anchors.left: labelText.right
        anchors.leftMargin: 10
        anchors.right: button.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        visible: sw.detail !== ""
        // A device name: plain, never rich text.
        textFormat: Text.PlainText
        text: sw.detail
        color: Theme.colDim
        font.pixelSize: Theme.fontSize - 7
        font.family: Theme.fontFamily
        elide: Text.ElideRight
    }

    ConsoleButton {
        id: button
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        fontSize: Theme.fontSize - 6
        minWidth: 72
        label: sw.on ? "ВКЛ" : "ВЫКЛ"
        current: sw.on
        onPicked: sw.toggled()
    }
}
