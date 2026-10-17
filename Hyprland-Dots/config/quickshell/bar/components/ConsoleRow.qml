import QtQuick
import QtQuick.Layouts
import ".."

// A row on a console plate that can be picked - a network, a device, a tunnel,
// a profile. A lamp says which one is in use (lit) and the name goes white;
// the rest stay grey. Hover lifts the row a shade off the plate. Anything that
// has to sit at the right edge (a flag, a lock, a spinner) goes in as a child.
Rectangle {
    id: row

    property bool lit: false
    property color tint: Theme.colAccent
    property bool showLamp: true
    property string icon: ""
    property string label: ""
    property string detail: ""
    property color detailColor: Theme.colDim
    property int fontSize: Theme.fontSize - 3
    property bool interactive: true
    default property alias trailing: extra.data
    signal picked()

    // Keyboard (CardKeys.qml): a pickable row takes focus, Enter or Space
    // picks it. Focus looks like hover, plus a white outline.
    activeFocusOnTab: interactive && visible
    readonly property bool hot: (area.containsMouse && interactive) || activeFocus
    border.width: activeFocus ? 2 : 0
    border.color: Theme.colWhite
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            row.picked()
            event.accepted = true
        }
    }

    width: parent ? parent.width : 0
    implicitHeight: Math.round(fontSize * 1.75)
    radius: 4
    color: row.hot ? Qt.lighter(Theme.colPlate, 1.6) : "transparent"
    Behavior on color { ColorAnimation { duration: 110 } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        spacing: 8

        ConsoleLamp {
            visible: row.showLamp
            lit: row.lit
            tint: row.tint
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            visible: row.icon !== ""
            text: row.icon
            color: row.lit || row.hot ? Theme.colWhite : Theme.colGrey
            font.pixelSize: row.fontSize
            font.family: Theme.fontFamily
            horizontalAlignment: Text.AlignHCenter
            Layout.preferredWidth: row.fontSize + 2
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            // From outside (names, titles, SSIDs): plain, never rich text - an <img> in it was fetched.
            textFormat: Text.PlainText
            text: row.label
            color: row.lit || row.hot ? Theme.colWhite : Theme.colGrey
            font.pixelSize: row.fontSize
            font.family: Theme.fontFamily
            font.bold: row.lit
            elide: Text.ElideRight
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            visible: row.detail !== ""
            // From outside too, on some rows (a model name, a device state).
            textFormat: Text.PlainText
            text: row.detail
            color: row.detailColor
            font.pixelSize: row.fontSize - 2
            font.family: Theme.fontFamily
            Layout.alignment: Qt.AlignVCenter
        }

        Row {
            id: extra
            visible: children.length > 0
            spacing: 6
            Layout.alignment: Qt.AlignVCenter
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: row.interactive
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.picked()
    }
}
