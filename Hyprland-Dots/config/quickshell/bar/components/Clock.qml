import QtQuick
import ".."

Text {
    id: clockText
    text: Qt.formatDateTime(new Date(), "HH:mm")
    color: Theme.colClock
    font.pixelSize: Theme.fontSize
    font.family: Theme.fontFamily
    font.bold: true; style: Text.Outline; styleColor: Qt.rgba(color.r, color.g, color.b, 0.3)

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: clockText.text = Qt.formatDateTime(new Date(), "HH:mm")
    }
}
