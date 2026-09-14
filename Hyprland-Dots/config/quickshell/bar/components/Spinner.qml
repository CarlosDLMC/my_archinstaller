import QtQuick
import ".."

// A ring of dots that chases its own tail, for "something is happening and I
// cannot tell you how far along it is".
//
// Drawn rather than set in type: the Nerd Font spinner glyphs this replaces
// are single characters rotated with a RotationAnimator, and a glyph spun
// about its own box wobbles - the ink is not centred in the cell, so it
// visibly orbits rather than turning. Eight circles on a real circle cannot
// do that.
//
// The tail is opacity graded around the ring, so rotating it smoothly reads as
// a comet rather than a wheel. Nothing here is themed by hue: like the rest of
// the bar it is one colour at varying brightness.
Item {
    id: spinner

    property int dots: 8
    property real dotSize: Math.max(2, Math.round(width / 7))
    property color color: Theme.colDim
    // Lowest opacity in the tail. The brightest dot is always 1.
    property real tailOpacity: 0.12
    property int periodMs: 900
    property bool running: visible

    implicitWidth: 16
    implicitHeight: 16

    Item {
        id: ring
        anchors.fill: parent

        Repeater {
            model: spinner.dots

            Rectangle {
                required property int index

                // ringRadius, not radius: Rectangle already has a `radius`
                // (its corner rounding), and redeclaring it is a hard error.
                readonly property real angle: index * 2 * Math.PI / spinner.dots
                readonly property real ringRadius:
                    Math.min(spinner.width, spinner.height) / 2 - spinner.dotSize / 2

                width: spinner.dotSize
                height: width
                radius: width / 2
                color: spinner.color

                x: spinner.width / 2 - width / 2 + Math.cos(angle) * ringRadius
                y: spinner.height / 2 - height / 2 + Math.sin(angle) * ringRadius

                // Brightest at the head, fading backwards around the ring.
                opacity: spinner.tailOpacity
                         + (1 - spinner.tailOpacity) * (index / (spinner.dots - 1))
            }
        }

        RotationAnimator on rotation {
            running: spinner.running
            loops: Animation.Infinite
            from: 0
            to: 360
            duration: spinner.periodMs
        }
    }
}
