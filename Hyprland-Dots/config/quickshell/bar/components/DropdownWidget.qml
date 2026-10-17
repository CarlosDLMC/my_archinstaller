import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import ".."

Item {
    id: root
    Layout.preferredWidth: iconContainer.width
    Layout.preferredHeight: parent.height

    required property var barWindow
    property int popupWidth: 200
    property int popupHeight: 150
    property int popupXOffset: 200
    property bool dropdownOpen: false
    property string stemAlignment: "center"  // "left", "center", or "right"
    property alias popupContent: popupLoader.sourceComponent

    // Which button opens the card. Left by default, so every existing widget
    // behaves exactly as before; VolumeWidget sets this to Right, because its
    // left-click already means mute and that is worth more than consistency.
    property int triggerButton: Qt.LeftButton

    signal opened()
    // Clicks on a button that is NOT the trigger, and wheel events, are handed
    // back to the widget instead of being swallowed by the card's hit area -
    // a widget can carry its own gestures and still have a dropdown.
    signal otherClicked(int button)
    signal wheelMoved(real deltaY)

    default property alias iconContent: iconContainer.data

    // Opened from the keyboard (BarCards.qml): the card's first control takes
    // focus as soon as it is built, and Esc closes it again.
    property bool keyboardOpened: false
    onDropdownOpenChanged: if (!dropdownOpen) keyboardOpened = false

    function navOpen() {
        keyboardOpened = true
        if (dropdownOpen) {
            cardKeys.focusFirst()    // already open (by the mouse): just take the keys
            return
        }
        dropdownOpen = true
        root.opened()
    }

    Connections {
        target: barWindow
        function onCloseAllPopups() {
            dropdownOpen = false
        }
    }

    Row {
        id: iconContainer
        anchors.centerIn: parent
        height: parent.height
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: mouse => {
            if (mouse.button !== root.triggerButton) {
                root.otherClicked(mouse.button)
                return
            }
            dropdownOpen = !dropdownOpen
            if (dropdownOpen) {
                root.opened()
            }
        }
        onWheel: wheel => root.wheelMoved(wheel.angleDelta.y)
    }

    HyprlandFocusGrab {
        id: focusGrab
        windows: [popup]
        active: dropdownOpen
        onCleared: dropdownOpen = false
    }

    PopupWindow {
        id: popup
        visible: dropdownOpen
        anchor.window: barWindow
        anchor.rect.x: {
            var iconCenter = (root.x + iconContainer.x + iconContainer.width/2) * barWindow.uiScale
            if (stemAlignment === "right") {
                return iconCenter - popupWidth + cardRect.stemWidth/2 + 10
            } else if (stemAlignment === "left") {
                return iconCenter - cardRect.stemWidth/2 - 10
            } else {
                return iconCenter - popupWidth/2
            }
        }
        anchor.rect.y: barWindow.designHeight * barWindow.uiScale + 2
        implicitWidth: popupWidth
        implicitHeight: popupHeight
        color: "transparent"

        // Main card with notch corners
        Canvas {
            id: cardRect
            anchors.fill: parent

            property int rawStemWidth: iconContainer.width + 16
            property int stemWidth: Math.min(rawStemWidth, width - 60)  // ensure room for notch corners
            property int stemHeight: 12
            property int notchRadius: 10
            property int cardRadius: 12

            onStemWidthChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.fillStyle = Theme.colBg

                var sw = stemWidth
                var sh = stemHeight
                var nr = notchRadius
                var r = cardRadius
                var w = width
                var h = height

                // Calculate stem center based on alignment
                var cx
                if (root.stemAlignment === "right") {
                    cx = w - sw/2 - 10
                } else if (root.stemAlignment === "left") {
                    cx = sw/2 + 10
                } else {
                    cx = w / 2
                }

                var stemLeft = cx - sw/2
                var stemRight = cx + sw/2

                ctx.beginPath()
                ctx.moveTo(stemLeft + r, 0)
                ctx.lineTo(stemRight - r, 0)
                ctx.arcTo(stemRight, 0, stemRight, r, r)
                ctx.lineTo(stemRight, sh - nr)
                ctx.arcTo(stemRight, sh, stemRight + nr, sh, nr)
                ctx.lineTo(w - r, sh)
                ctx.arcTo(w, sh, w, sh + r, r)
                ctx.lineTo(w, h - r)
                ctx.arcTo(w, h, w - r, h, r)
                ctx.lineTo(r, h)
                ctx.arcTo(0, h, 0, h - r, r)
                ctx.lineTo(0, sh + r)
                ctx.arcTo(0, sh, r, sh, r)
                ctx.lineTo(stemLeft - nr, sh)
                ctx.arcTo(stemLeft, sh, stemLeft, sh - nr, nr)
                ctx.lineTo(stemLeft, r)
                ctx.arcTo(stemLeft, 0, stemLeft + r, 0, r)
                ctx.closePath()
                ctx.fill()
            }
        }

        MouseArea {
            anchors.fill: parent
        }

        // Built when the card opens and dropped when it closes. Without an
        // `active:` every card - network, audio, battery, agents, ... - was
        // built at startup and kept for good, open or not; the bar started
        // ~90MB heavier for cards that were mostly never looked at.
        CardKeys {
            id: cardKeys
            anchors.fill: parent
            focus: true
            onDismissed: root.dropdownOpen = false

            Loader {
                id: popupLoader
                active: root.dropdownOpen
                anchors.fill: parent
                anchors.topMargin: cardRect.stemHeight + 8
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                anchors.bottomMargin: 8
                // After the card's own Component.onCompleted, which may still
                // be filling it in.
                onLoaded: if (root.keyboardOpened) Qt.callLater(cardKeys.focusFirst)
            }
        }

        onVisibleChanged: {
            if (!visible) {
                dropdownOpen = false
            }
        }
    }
}
