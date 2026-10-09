import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import ".."

// «ПУСК · ПУЛЬТ» - the power menu window (state in PowerState).
//
// Laid out on a terminal cell grid - 13 x 29 px at 2560x1440, JetBrains Mono
// 22 like hyprlock and foot - so it reads as one TUI window: 113 x 21 cells,
// centred over the dimmed desktop, five push-buttons with the round-1 icons.
// Smaller screens scale the whole grid.
//
// Keys go by physical key (nativeScanCode = XKB keycode), so L/E/U/R/S/B/W
// work in the RU and ES layouts too: L 46, E 26, U 30, R 27, S 39, B 56, W 25.
PanelWindow {
    id: osd

    property var modelData
    screen: modelData

    readonly property bool onFocusedMonitor:
        Hyprland.focusedMonitor && modelData
        && Hyprland.focusedMonitor.name === modelData.name
    readonly property bool shown: PowerState.dialogOpen && onFocusedMonitor
    readonly property bool armed: PowerState.armed

    property bool windowVisible: false
    readonly property int fadeMs: 160

    // ---- the grid
    readonly property real k: Math.max(0.6, Math.min(width / 2560, height / 1440))
    readonly property real cw: 13 * k
    readonly property real ch: 29 * k
    readonly property int px: Math.round(22 * k)
    readonly property string mono: "JetBrainsMono Nerd Font Mono"
    readonly property int ww: 113
    readonly property int wh: 21
    FontMetrics { id: fm; font.family: osd.mono; font.pixelSize: osd.px }
    readonly property real spacingFix: cw - fm.advanceWidth("M")

    visible: windowVisible
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "quickshell:power"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    onShownChanged: {
        if (shown) { windowVisible = true; goneTimer.stop() }
        else goneTimer.restart()
    }
    Timer { id: goneTimer; interval: osd.fadeMs; onTriggered: osd.windowVisible = false }

    // One run of text on the grid: every glyph exactly one cell, optional fill.
    component Cell: Rectangle {
        property alias text: label.text
        property color fg: PowerState.ink
        property bool bold: false
        property int cells: label.text.length
        width: cells * osd.cw
        height: osd.ch
        color: "transparent"
        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            color: parent.fg
            font.family: osd.mono
            font.pixelSize: osd.px
            font.bold: parent.bold
            font.letterSpacing: osd.spacingFix
            font.kerning: false
            font.features: { "liga": 0, "calt": 0 }
        }
    }

    // The dimmed desktop. A click outside the window closes it.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.62)
        opacity: osd.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: osd.fadeMs } }
        MouseArea { anchors.fill: parent; onClicked: PowerState.close() }
    }

    Item {
        id: win
        width: osd.ww * osd.cw
        height: osd.wh * osd.ch
        anchors.centerIn: parent
        opacity: osd.shown ? 1 : 0
        scale: osd.shown ? 1 : 0.97
        Behavior on opacity { NumberAnimation { duration: osd.fadeMs; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: osd.fadeMs; easing.type: Easing.OutCubic } }

        focus: osd.shown
        Keys.onPressed: event => {
            const sc = event.nativeScanCode
            const byKey = { 46: "L", 26: "E", 30: "U", 27: "R", 39: "S", 56: "B", 25: "W" }
            if (event.key === Qt.Key_Escape) {
                if (PowerState.armed) PowerState.disarm()
                else PowerState.close()
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (PowerState.armed) PowerState.fire()
                else PowerState.press(PowerState.modes[PowerState.selected].k)
            } else if (!PowerState.armed && (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab)) {
                PowerState.selected = (PowerState.selected + 4) % 5
            } else if (!PowerState.armed && (event.key === Qt.Key_Right || event.key === Qt.Key_Tab)) {
                PowerState.selected = (PowerState.selected + 1) % 5
            } else if (byKey[sc] !== undefined) {
                PowerState.press(byKey[sc])
            } else {
                return
            }
            event.accepted = true
        }

        MouseArea { anchors.fill: parent }         // clicks inside never close it

        // drop shadow + body
        Rectangle { x: 2 * osd.cw; y: osd.ch; width: parent.width; height: parent.height; color: PowerState.shade }
        Rectangle { anchors.fill: parent; color: PowerState.black }

        // ------------------------------------------------------------ title bar
        Rectangle {
            width: parent.width; height: osd.ch
            color: osd.armed ? PowerState.red : PowerState.grey2
            Row {
                Cell {
                    text: "  ПУСК "
                    color: osd.armed ? PowerState.white : PowerState.red
                    fg: osd.armed ? PowerState.red : PowerState.white
                    bold: true
                }
                Item { width: 2 * osd.cw; height: 1 }
                Cell {
                    text: osd.armed ? "ПЯТИСЕКУНДНАЯ ГОТОВНОСТЬ  ·  " + PowerState.armedName()
                                    : "ПУЛЬТ УПРАВЛЕНИЯ ПИТАНИЕМ"
                    fg: osd.armed ? PowerState.white : PowerState.ink
                    bold: osd.armed
                }
            }
            Row {
                anchors.right: parent.right
                Cell {
                    text: osd.armed ? "ДО ПУСКА  " : "ВРЕМЯ РАБОТЫ "
                    fg: osd.armed ? PowerState.white : PowerState.dim
                    bold: osd.armed
                }
                Cell {
                    text: osd.armed ? "Т−00:00:0" + PowerState.secondsLeft
                                    : "Т+" + PowerState.clock(PowerState.uptime)
                    fg: PowerState.white
                    bold: true
                }
            }
        }

        // ------------------------------------------------------------ frame
        readonly property color frameColor: osd.armed ? PowerState.grey3 : PowerState.dim
        // double outline: rows 1..20, centred in the edge cells
        Rectangle {
            x: osd.cw / 2 - 2; y: 1.5 * osd.ch - 2
            width: parent.width - osd.cw + 4; height: (osd.wh - 1) * osd.ch - osd.ch + 4
            color: "transparent"; border.width: 1; border.color: win.frameColor
        }
        Rectangle {
            x: osd.cw / 2 + 2; y: 1.5 * osd.ch + 2
            width: parent.width - osd.cw - 4; height: (osd.wh - 1) * osd.ch - osd.ch - 4
            color: "transparent"; border.width: 1; border.color: win.frameColor
        }
        // ╟──╢ above the strip
        Rectangle {
            x: osd.cw / 2 + 2; y: 17.5 * osd.ch
            width: parent.width - osd.cw - 4; height: 1
            color: win.frameColor
        }

        // ------------------------------------------------------------ buttons
        Repeater {
            model: PowerState.modes
            Item {
                id: btn
                required property var modelData
                required property int index
                readonly property bool sel: osd.armed ? PowerState.armedKey === modelData.k
                                                     : PowerState.selected === index
                readonly property bool hot: osd.armed && sel
                readonly property bool off: osd.armed && !sel
                readonly property color bg: hot ? PowerState.red : (sel ? PowerState.ink : PowerState.black)
                readonly property color fg: hot ? PowerState.white : (sel ? PowerState.black : (off ? PowerState.grey3 : PowerState.ink))
                readonly property color fg2: hot ? PowerState.white : (sel ? PowerState.black : (off ? PowerState.grey3 : PowerState.dim))

                x: (4 + 21 * index) * osd.cw
                y: 3 * osd.ch
                width: 19 * osd.cw
                height: 12 * osd.ch

                Rectangle { x: 2 * osd.cw; y: osd.ch; width: parent.width; height: parent.height; color: PowerState.grey1 }
                Rectangle { anchors.fill: parent; color: btn.bg }
                Rectangle {
                    x: osd.cw / 2; y: osd.ch / 2
                    width: parent.width - osd.cw; height: parent.height - osd.ch
                    color: "transparent"; border.width: 1
                    border.color: btn.hot ? PowerState.red : (btn.sel ? PowerState.ink : (btn.off ? PowerState.grey2 : PowerState.dim))
                }

                // the icon, or the seconds left in the lock screen's clock digits
                Text {
                    visible: !btn.hot
                    x: osd.cw; y: osd.ch
                    width: parent.width - 2 * osd.cw; height: 5 * osd.ch
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: String.fromCodePoint(btn.modelData.glyph)
                    color: btn.sel || btn.off ? btn.fg : PowerState.ink
                    opacity: btn.sel || btn.off ? 1 : 0.8
                    font.family: "Terminess Nerd Font"
                    font.pixelSize: Math.round(104 * osd.k)
                }
                BigDigit {
                    visible: btn.hot
                    digit: PowerState.secondsLeft
                    x: (9 - 3) * osd.cw; y: osd.ch
                }
                Cell {
                    visible: btn.hot
                    x: (9 + 2) * osd.cw; y: 5 * osd.ch
                    text: "с"; fg: PowerState.white; bold: true
                }

                Cell {
                    x: Math.floor((19 - cells) / 2) * osd.cw; y: 7 * osd.ch
                    text: btn.modelData.name; fg: btn.fg; bold: true
                }
                Cell {
                    x: Math.floor((19 - cells) / 2) * osd.cw; y: 8 * osd.ch
                    text: btn.modelData.slogan; fg: btn.sel ? btn.fg : btn.fg2
                }
                // bottom row: key cap + timing, centred as a group
                Row {
                    readonly property string timing: btn.hot ? "осталось " + PowerState.secondsLeft + " с"
                                                             : (btn.modelData.arm ? "отсчёт 5 с" : "сразу")
                    x: Math.floor((19 - (5 + timing.length)) / 2) * osd.cw
                    y: 10 * osd.ch
                    Cell {
                        text: " " + btn.modelData.k + " "
                        bold: true
                        color: btn.hot ? PowerState.white : (btn.sel ? PowerState.black : PowerState.grey2)
                        fg: btn.hot ? PowerState.red : (btn.sel ? PowerState.white : (btn.off ? PowerState.grey3 : PowerState.ink))
                    }
                    Item { width: 2 * osd.cw; height: 1 }
                    Cell { text: parent.timing; fg: btn.sel ? btn.fg : btn.fg2; bold: btn.hot }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: if (!PowerState.armed) PowerState.selected = btn.index
                    onClicked: PowerState.press(btn.modelData.k)
                }
            }
        }

        // ------------------------------------------------------------ strip
        Item {
            x: 2 * osd.cw; y: 18 * osd.ch
            width: parent.width - 4 * osd.cw; height: osd.ch

            Row {
                visible: !osd.armed
                x: osd.cw
                Cell { text: "ЗАРЯ"; fg: PowerState.white; bold: true }
                Item { width: 2 * osd.cw; height: 1 }
                Cell { text: "Кедр, я Заря. Ваше решение?" }
            }
            Row {
                visible: !osd.armed
                anchors.right: parent.right
                Cell { text: "ENTER › "; fg: PowerState.dim }
                Cell { text: PowerState.modes[PowerState.selected].show }
            }

            Row {
                visible: osd.armed
                Repeater {
                    model: PowerState.litany
                    Row {
                        required property string modelData
                        required property int index
                        readonly property bool done: index < PowerState.step
                        readonly property bool now: index === PowerState.step
                        Cell {
                            text: (parent.done ? " ✓ " : (parent.now ? " ▶ " : " ○ ")) + parent.modelData + " "
                            color: parent.now ? PowerState.red : "transparent"
                            fg: parent.now ? PowerState.white : (parent.done ? PowerState.ink : PowerState.dim)
                            bold: parent.now
                        }
                        Cell {
                            visible: parent.index < PowerState.litany.length - 1
                            text: " › "; fg: PowerState.grey3
                        }
                    }
                }
            }
            Row {
                visible: osd.armed
                anchors.right: parent.right
                Cell { text: "ЭВМ › "; fg: PowerState.dim }
                Cell { text: PowerState.armed ? PowerState.stepAction(PowerState.step) : "" }
            }
        }

        // ------------------------------------------------------------ key line, set into the bottom frame
        Row {
            x: 3 * osd.cw; y: 20 * osd.ch
            Cell { text: " "; color: PowerState.black }
            Repeater {
                model: osd.armed
                    ? [["S · ENTER", "немедленно"], ["ESC", "отставить"]]
                    : [["← →", "выбор"], ["ENTER", "исполнить"], ["ESC", "вольно"]]
                        .concat(PowerState.canFirmware ? [["B", "в UEFI"]] : [])
                        .concat(PowerState.windowsEntry !== "" ? [["W", "в Windows — перебежчик?"]] : [])
                Row {
                    required property var modelData
                    required property int index
                    Cell { visible: parent.index > 0; text: "   "; color: PowerState.black }
                    Cell {
                        text: parent.modelData[0]
                        color: PowerState.black
                        fg: osd.armed ? PowerState.white : PowerState.ink
                        bold: true
                    }
                    Cell {
                        text: " " + parent.modelData[1]
                        color: PowerState.black
                        fg: osd.armed ? PowerState.ink : PowerState.dim
                    }
                }
            }
            Cell { text: " "; color: PowerState.black }
        }
        Cell {
            x: parent.width - (3 + cells) * osd.cw; y: 20 * osd.ch
            text: " «КОСМОС НАШ» "; color: PowerState.black; fg: PowerState.dim
        }
    }

    // The ly / hyprlock bigclock digit (SovietClock.sh), painted as cells.
    component BigDigit: Item {
        property int digit: 0
        readonly property var table: ({
            "0": ["####", "#  #", "#  #", "#  #", "####"],
            "1": ["  ##", "   #", "   #", "   #", "   #"],
            "2": ["####", "   #", "####", "#   ", "####"],
            "3": ["####", "   #", "####", "   #", "####"],
            "4": ["#  #", "#  #", "####", "   #", "   #"],
            "5": ["####", "#   ", "####", "   #", "####"]
        })
        width: 4 * osd.cw; height: 5 * osd.ch
        Repeater {
            model: 20
            Rectangle {
                required property int index
                readonly property int r: Math.floor(index / 4)
                readonly property int c: index % 4
                visible: parent.table[String(parent.digit)][r][c] === "#"
                x: c * osd.cw; y: r * osd.ch
                width: osd.cw; height: osd.ch
                color: PowerState.white
            }
        }
    }
}
