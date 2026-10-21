import QtQuick
import QtQuick.Layouts
import ".."

Rectangle {
    id: kbWidget

    // The active layout, from mango's layout stream (Mango.keyboardLayout,
    // its full XKB name: "English (US)", "Russian", ...).
    property string currentLayout: {
        var layout = Mango.keyboardLayout.trim().toLowerCase()
        if (layout === "") return "us"
        if (layout.includes("english")) return "us"
        if (layout.includes("spanish")) return "es"
        if (layout.includes("russian")) return "ru"
        return layout.substring(0, 2)
    }

    implicitWidth: kbText.implicitWidth
    implicitHeight: parent.height
    color: mouseArea.containsMouse ? Qt.rgba(255, 255, 255, 0.1) : "transparent"
    radius: 6

    Text {
        id: kbText
        anchors.centerIn: parent
        // Russian names for the layouts in use; anything else as its code.
        text: ({ "us": "АНГ", "ru": "РУС", "es": "ИСП" })[currentLayout] || currentLayout.toUpperCase()
        color: Theme.colWhite
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
        font.bold: true; style: Text.Outline; styleColor: Theme.colTextShadow
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // The next layout in configured order (no argument = next).
        onClicked: Mango.dispatch("switch_keyboard_layout")
    }
}
