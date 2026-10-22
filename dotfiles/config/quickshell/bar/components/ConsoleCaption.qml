import QtQuick
import ".."

// The engraved caption beside a console's controls («ЗАРЯД», «ПРЕДЕЛ ЗАРЯДА»):
// small bold capitals, dim, spaced out a little like lettering on a panel.
Text {
    property int fontSize: Theme.fontSize - 5

    color: Theme.colDim
    font.pixelSize: fontSize
    font.family: Theme.fontFamily
    font.bold: true
    font.letterSpacing: 1
}
