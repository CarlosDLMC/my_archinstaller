import QtQuick
import QtQuick.Layouts
import ".."

// TUI-style pipe divider
Text {
    text: "│"
    color: Theme.colMuted
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize + 4
    Layout.alignment: Qt.AlignVCenter
    Layout.leftMargin: 6
    Layout.rightMargin: 6
}
