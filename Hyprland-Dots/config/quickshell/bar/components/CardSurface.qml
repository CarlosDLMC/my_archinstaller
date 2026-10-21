import QtQuick
import Quickshell
import Quickshell.Wayland

// One of the bar's cards on screen: a full-screen, see-through layer surface
// with the card drawn at (cardX, cardY) under the bar.
//
// - A click anywhere outside the card closes it (dismissed). The surface
//   covers the screen and is transparent outside the card, so that click
//   lands here instead of on the window or bar widget under it.
// - While it is open it holds the keyboard (exclusive), so a card takes typing
//   whether it was opened by a click or from the keyboard: the Wi-Fi password,
//   CardKeys' arrows and Esc. Keybinds still work over it.
// - mango blurs a layer surface only under its non-transparent pixels, so only
//   the card is blurred.
//
// Under Hyprland the cards were popups of the bar and a focus grab
// (hyprland-focus-grab) did the first two; mango never gives a popup the
// keyboard and has no such grab.
PanelWindow {
    id: surface

    required property var barWindow
    property bool open: false
    // The card's place on the screen: left edge, top edge (just under the bar
    // by default) and size.
    property real cardX: 0
    property real cardY: barWindow.designHeight * barWindow.uiScale + 2
    property real cardWidth: 200
    property real cardHeight: 150
    default property alias content: card.data

    signal dismissed()

    screen: barWindow.modelData
    visible: open
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:card"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    color: "transparent"

    // Everything outside the card: any button closes it; the wheel is eaten.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: surface.dismissed()
        onWheel: wheel => wheel.accepted = true
    }

    Item {
        id: card
        x: surface.cardX
        y: surface.cardY
        width: surface.cardWidth
        height: surface.cardHeight
    }
}
