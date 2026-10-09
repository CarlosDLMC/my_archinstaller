import QtQuick
import QtQuick.Layouts
import ".."

// Arch logo at the bar's left edge. A click opens the power menu - the same
// «ПУСК · ПУЛЬТ» window as CTRL+ALT+P (PowerState / PowerOsd). It used to
// open a dropdown of its own.
Item {
    id: powerWidget

    required property var barWindow
    Layout.preferredWidth: powerIcon.width + 16
    Layout.preferredHeight: parent.height

    // Icon with spacing
    Item {
        width: powerIcon.width + 16
        height: parent.height
        anchors.centerIn: parent

        Text {
            id: powerIcon
            anchors.centerIn: parent
            text: ""
            // The Hyprland active-window border colour: the bar template maps
            // "border" to {{color12}}, which is the same wallust slot
            // UserDecorations.lua uses for col.active_border. So the logo and
            // the focused window's border match, by request.
            //
            // colLogo, not palBorder: color12 is a dark slot, and on some
            // wallpapers it lands on top of the bar's own background (1.00:1
            // on Catppuccin-Mocha_hanged_man_tree - invisible). colLogo keeps
            // the hue and lifts the lightness only far enough to clear 3:1,
            // so the match survives everywhere it can be seen. See Theme.qml.
            color: Theme.colLogo
            // Sized off the BAR, not the text. barContent is laid out at
            // designHeight and then scaled by uiScale as one unit, so a
            // single multiplier fills the bar height at every resolution -
            // 34px on the 2560 monitor, ~31px on the 1920 laptop, and
            // whatever is right on anything else. The 1.09 accounts for the
            // glyph's ink being ~92% of its em box.
            font.pixelSize: Math.round(barWindow.designHeight * 1.09)
            font.family: Theme.fontFamily
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: PowerState.toggle()
    }
}
