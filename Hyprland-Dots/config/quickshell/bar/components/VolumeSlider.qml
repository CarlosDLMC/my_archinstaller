import QtQuick
import ".."

// A volume track, in the bar's idiom rather than a Qt Controls Slider: the
// same white-at-low-alpha groove, filled bar and 130ms easing as ToggleRow's
// switch, so the audio card reads as part of the same family.
//
// Drag or click anywhere on the track to set, wheel to nudge in 5% steps,
// right-click to mute - the wheel and right-click match what the volume
// widget in the bar already does, so the gesture does not change meaning
// when the card is open.
Item {
    id: slider

    property real value: 0
    // Streams go to 1.5: PipeWire lets an application be boosted past its
    // source material, and that is the whole point of a per-app control.
    // Devices stay at 1.0, where the hardware actually tops out.
    property real maximum: 1.0
    property bool muted: false
    property bool enabled: true
    property int trackHeight: 6

    signal moved(real v)
    signal rightClicked()

    implicitHeight: 18
    opacity: enabled ? 1.0 : 0.4

    readonly property real ratio: maximum > 0
        ? Math.max(0, Math.min(1, value / maximum))
        : 0

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: slider.trackHeight
        radius: height / 2
        color: Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.10)

        Rectangle {
            width: track.width * slider.ratio
            height: parent.height
            radius: height / 2
            // Muted is a state worth seeing, but it is not an alert - the
            // reading simply drops to the inactive grey, the way an idle
            // widget does in the bar.
            color: slider.muted ? Theme.colMuted : Theme.colWhite
            Behavior on color { ColorAnimation { duration: 130 } }
        }
    }

    // The knob carries a background-coloured rim so it stays readable where it
    // sits on top of the filled portion of its own track.
    Rectangle {
        width: 12
        height: 12
        radius: width / 2
        x: Math.round((slider.width - width) * slider.ratio)
        anchors.verticalCenter: parent.verticalCenter
        color: slider.muted ? Theme.colMuted : Theme.colWhite
        border.width: 1
        border.color: Theme.colBg
        Behavior on color { ColorAnimation { duration: 130 } }
    }

    MouseArea {
        anchors.fill: parent
        enabled: slider.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        property bool dragging: false

        function valueAt(mx) {
            if (slider.width <= 0)
                return slider.value
            return Math.max(0, Math.min(1, mx / slider.width)) * slider.maximum
        }

        onPressed: mouse => {
            if (mouse.button !== Qt.LeftButton)
                return
            dragging = true
            slider.moved(valueAt(mouse.x))
        }
        onPositionChanged: mouse => {
            if (dragging)
                slider.moved(valueAt(mouse.x))
        }
        onReleased: dragging = false
        onCanceled: dragging = false
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                slider.rightClicked()
        }
        onWheel: wheel => {
            var step = slider.maximum * 0.05
            var next = slider.value + (wheel.angleDelta.y > 0 ? step : -step)
            slider.moved(Math.max(0, Math.min(slider.maximum, next)))
        }
    }
}
