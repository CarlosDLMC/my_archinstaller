import QtQuick
import QtQuick.Effects
import ".."

RectangularShadow {
    required property var target
    anchors.fill: target
    radius: Appearance.rounding.screenRounding > 0 ? 20 : 0   // under the overview panel, square when it is
    blur: 0.9 * Appearance.sizes.elevationMargin
    offset: Qt.vector2d(0.0, 1.0)
    spread: 1
    color: Appearance.colors.colShadow
    cached: true
}
