import QtQuick
import QtQuick.Layouts
import ".."

// Pure renderer: the numbers come from the SystemStats singleton, which reads
// /proc and the hwmon sensor once for the whole shell rather than once per
// screen. See SystemStats.qml for why that matters.
RowLayout {
    id: cpuWidget
    spacing: 4

    // Label
    Text {
        text: "CPU "
        color: Theme.colCpu
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
        font.bold: true; style: Text.Outline; styleColor: Theme.colTextShadow
        Layout.alignment: Qt.AlignVCenter
    }

    // Usage percentage
    Text {
        text: SystemStats.cpuUsage + "% "
        color: Theme.colValue
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
        font.bold: true; style: Text.Outline; styleColor: Theme.colTextShadow
        Layout.alignment: Qt.AlignVCenter
    }

    // Temperature
    Text {
        text: SystemStats.cpuTemp + "ºC"
        color: Theme.colValue
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
        font.bold: true; style: Text.Outline; styleColor: Theme.colTextShadow
        Layout.alignment: Qt.AlignVCenter
    }
}
