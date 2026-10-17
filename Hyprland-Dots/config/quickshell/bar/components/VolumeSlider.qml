import QtQuick
import ".."

// A volume fader, in the console cards' idiom rather than a Qt Controls
// Slider: the level is a SegmentGauge (the battery card's gauge), with a fader
// cap standing on it where the level is.
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

    implicitHeight: 20
    opacity: enabled ? 1.0 : 0.4

    readonly property real ratio: maximum > 0
        ? Math.max(0, Math.min(1, value / maximum))
        : 0

    // The scale. Streams run to 150%, so theirs carries a tick at 100% -
    // everything past it is boost.
    SegmentGauge {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 10
        segments: Math.max(12, Math.round(width / 12))
        value: slider.ratio * 100
        marker: slider.maximum > 1 ? 100 / slider.maximum * 100 : -1
        // Muted is a state worth seeing, but it is not an alert - the
        // reading simply drops to the inactive colour, the way an idle
        // widget does in the bar.
        tint: slider.muted ? Theme.colMuted : Theme.colAccent
    }

    // The fader cap carries a background-coloured rim so it stays readable
    // where it stands on the lit part of the scale.
    Rectangle {
        width: 6
        height: 20
        radius: 2
        x: Math.round((slider.width - width) * slider.ratio)
        anchors.verticalCenter: parent.verticalCenter
        color: slider.muted ? Theme.colGrey : Theme.colWhite
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
