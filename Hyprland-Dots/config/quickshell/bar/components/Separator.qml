import QtQuick
import QtQuick.Layouts
import ".."

// A 1px rule, not a "│" glyph. As a glyph the divider inherited the font's
// line metrics, so it ran nearly the full height of the bar and read as
// loudly as the values it was separating. Here the height and weight are
// set explicitly, which keeps it a divider rather than a character.
//
// The height tracks Theme.fontSize so it stays proportional if the bar's
// text size changes, and the whole thing is inside barContent, so uiScale
// shrinks it on narrower screens along with everything else.
Rectangle {
    Layout.preferredWidth: 1
    Layout.preferredHeight: Math.round(Theme.fontSize * 0.75)
    Layout.alignment: Qt.AlignVCenter
    Layout.leftMargin: 9
    Layout.rightMargin: 9
    color: Theme.colSeparator
    opacity: 0.45
}
