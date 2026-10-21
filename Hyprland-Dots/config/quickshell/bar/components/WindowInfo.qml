import QtQuick
import QtQuick.Layouts
import ".."

RowLayout {
    id: windowInfo
    spacing: 0

    // The focused window's title, whichever monitor it is on. mango pushes a
    // new snapshot when focus moves and when the focused window retitles
    // itself, and the title clears when nothing is focused (an empty
    // workspace, the last window closed).
    property string activeWindow: Mango.focusedClientTitle

    Text {
        // From outside (names, titles, SSIDs): plain, never rich text - an <img> in it was fetched.
        textFormat: Text.PlainText
        text: activeWindow
        color: Theme.colWindow
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
        font.bold: true; style: Text.Outline; styleColor: Theme.colTextShadow
        Layout.leftMargin: 0
        Layout.maximumWidth: 375
        elide: Text.ElideRight
        maximumLineCount: 1
        visible: activeWindow.length > 0
    }
}
