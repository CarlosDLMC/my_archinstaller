import QtQuick
import QtQuick.Layouts
import ".."

// Pure renderer - see CpuWidget.qml and SystemStats.qml.
RowLayout {
    id: memWidget
    spacing: 4

    // Label — dim, same weight as the CPU label
    Text {
        text: "MEM "
        color: Theme.colMem
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
        font.bold: true; style: Text.Outline; styleColor: Theme.colTextShadow
        Layout.alignment: Qt.AlignVCenter
    }

    // Value — steps up to full foreground
    Text {
        text: SystemStats.memUsage
        color: Theme.colValue
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
        font.bold: true; style: Text.Outline; styleColor: Theme.colTextShadow
        Layout.alignment: Qt.AlignVCenter
    }
}
