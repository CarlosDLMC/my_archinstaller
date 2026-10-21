import QtQuick
import ".."

Text {
    id: root
    property bool animateChange: false

    renderType: Text.NativeRendering
    // Window titles go through here: plain, never rich text - an <img> in one was fetched.
    textFormat: Text.PlainText
    verticalAlignment: Text.AlignVCenter
    font {
        hintingPreference: Font.PreferFullHinting
        family: Appearance?.font.family.main ?? "sans-serif"
        pixelSize: Appearance?.font.pixelSize.small ?? 15
    }
    color: Appearance?.m3colors.m3onBackground ?? "white"
}
