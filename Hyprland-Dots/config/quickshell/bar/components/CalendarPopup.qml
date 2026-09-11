import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import ".."

Item {
    id: root

    required property var barWindow
    property bool isOpen: false
    property int anchorX: 0
    property var currentDate: new Date()
    property var selectedDate: new Date()
    property var displayDate: new Date()

    signal dateClicked(var clickedDate)
    signal closed()

    // Re-seed the dates every time the popup opens. CenterInfo only toggles
    // isOpen - the popup itself is never destroyed - so without this displayDate
    // stayed on whatever month was last paged to, and currentDate stayed on the
    // date the bar process was started. The visible effects were that reopening
    // the calendar showed the old month instead of this one, and that on a bar
    // that had been running past midnight "today" was highlighted on the wrong
    // cell. Separate Date objects on purpose, so no later in-place mutation of
    // one can move the others.
    onIsOpenChanged: {
        if (!isOpen)
            return
        currentDate = new Date()
        displayDate = new Date()
        selectedDate = new Date()
    }

    // One place that moves the calendar a month, used by both arrows and the
    // wheel. The setDate(1) is the load-bearing part: setMonth() keeps the
    // day-of-month, so stepping forward from a 31st into a shorter month
    // overflows and JS silently normalises it into the month after that -
    // 31 Jan + 1 month becomes 3 March, skipping February outright. Anchoring
    // to the 1st first makes every step exactly one month. This was previously
    // hard to hit because displayDate was only ever set when the bar started;
    // now that it is re-seeded from today on every open, any 29th/30th/31st
    // reaches it.
    function stepMonth(delta) {
        const d = new Date(root.displayDate)
        d.setDate(1)
        d.setMonth(d.getMonth() + delta)
        root.displayDate = d
    }

    // Wheel scrolling: up for earlier months, down for later.
    //
    // This is wired to onWheel on every MouseArea that is front-most over some
    // part of the popup - the day cells, the two arrows, and the full-size
    // MouseArea behind the content - rather than to one WheelHandler covering
    // everything. A WheelHandler on the content Column was tried first and never
    // fired: the day cells' own MouseAreas sit in front of it and consume the
    // wheel event, so it never reached the handler behind them. Each MouseArea
    // handling its own region is the pattern VolumeWidget already uses here, and
    // it works because each one is the front-most item where it matters.
    //
    // The accumulator lives on root, so it is shared no matter which MouseArea
    // the pointer happens to be over.
    property real wheelAccumulated: 0

    function wheelStep(wheel) {
        // A mouse notch is 120 units (eighths of a degree), so a real wheel steps
        // immediately. Trackpads send much smaller deltas, so accumulate rather
        // than treating each event as a month - otherwise one gentle two-finger
        // swipe flies through a year.
        root.wheelAccumulated += wheel.angleDelta.y
        while (root.wheelAccumulated >= 120) {
            root.wheelAccumulated -= 120
            root.stepMonth(-1)
        }
        while (root.wheelAccumulated <= -120) {
            root.wheelAccumulated += 120
            root.stepMonth(1)
        }
    }

    function weekStartJs() {
    	return Qt.locale().firstDayOfWeek 
    }

    function startOfWeek(dateObj) {
        const d = new Date(dateObj)
        const jsDow = d.getDay()
        const diff = (jsDow - weekStartJs() + 7) % 7
        d.setDate(d.getDate() - diff)
        return d
    }

    function endOfWeek(dateObj) {
        const d = new Date(dateObj)
        const jsDow = d.getDay()
        const add = (weekStartJs() + 6 - jsDow + 7) % 7
        d.setDate(d.getDate() + add)
        return d
    }

    HyprlandFocusGrab {
        id: calendarFocusGrab
        windows: [calendarPopupWindow]
        active: root.isOpen
        onCleared: {
            root.closed()
        }
    }

    PopupWindow {
        id: calendarPopupWindow
        visible: root.isOpen
        anchor.window: barWindow
        anchor.rect.x: root.anchorX - 200
        anchor.rect.y: barWindow.designHeight * barWindow.uiScale + 2
        implicitWidth: 400
        implicitHeight: calendarContent.implicitHeight + 12 + 32
        color: "transparent"

        Canvas {
            id: cardRect
            anchors.fill: parent

            property int stemWidth: 60
            property int stemHeight: 12
            property int notchRadius: 10
            property int cardRadius: 12

            onPaint: {
                var ctx = getContext("2d")
                ctx.fillStyle = Theme.colBg

                var sw = stemWidth
                var sh = stemHeight
                var nr = notchRadius
                var r = cardRadius
                var w = width
                var h = height
                var cx = w / 2

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
            onWheel: function (wheel) { root.wheelStep(wheel) }
        }

        Column {
            id: calendarContent
            anchors.fill: cardRect

            anchors.topMargin: cardRect.stemHeight + 16
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.bottomMargin: 16
            spacing: 12

            Row {
                width: parent.width
                // 48 rather than the label's own 32px line height: the taller
                // label would technically still fit the old 36px row, but with
                // only 4px to spare it sat visually flush against the week-day
                // header below it. This keeps the month name breathing.
                height: 48

                Rectangle {
                    width: 36
                    height: 36
                    // The row is now taller than the buttons, and a Row only
                    // positions its children horizontally - without this they sit
                    // at the top, out of line with the month name.
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 6
                    color: prevMonthArea.containsMouse ? Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.12) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "󰅁"
                        font.pixelSize: 24
                        color: Theme.colWhite
                        font.family: Theme.fontFamily
                    }

                    MouseArea {
                        id: prevMonthArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.stepMonth(-1)
                        onWheel: function (wheel) { root.wheelStep(wheel) }
                    }
                }

                Text {
                    width: parent.width - 72
                    height: parent.height
                    // standaloneMonthName, not a "MMMM" format string: in Russian -
                    // and in every language with grammatical case - MMMM gives the
                    // genitive form used *inside* a full date ("10 сентября 2026"),
                    // so a bare month heading came out as "сентября 2026". The
                    // standalone form is the nominative "сентябрь" a heading wants.
                    // The month index is 0-based, same as Date.getMonth().
                    // Russian writes month names lowercase ("сентябрь"), which is
                    // correct prose but reads as a typo in a heading - so the first
                    // letter is lifted here rather than in the locale data.
                    // toUpperCase() is Unicode-aware, so "с" -> "С" works.
                    text: {
                        const name = Qt.locale().standaloneMonthName(root.displayDate.getMonth(),
                                                                     Locale.LongFormat)
                        return name.charAt(0).toUpperCase() + name.slice(1)
                               + " " + root.displayDate.getFullYear()
                    }
                    font.pixelSize: Theme.fontSize + 10
                    color: Theme.colWhite
                    font.family: Theme.fontFamily
                    font.bold: true; style: Text.Outline; styleColor: Theme.colTextShadow
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                Rectangle {
                    width: 36
                    height: 36
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 6
                    color: nextMonthArea.containsMouse ? Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.12) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "󰅂"
                        font.pixelSize: 24
                        color: Theme.colWhite
                        font.family: Theme.fontFamily
                    }

                    MouseArea {
                        id: nextMonthArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.stepMonth(1)
                        onWheel: function (wheel) { root.wheelStep(wheel) }
                    }
                }
            }

            Row {
                width: parent.width
                height: 24

                Repeater {
                    model: {
                        const days = []
                        const loc = Qt.locale()
                        const qtFirst = loc.firstDayOfWeek
                        for (let i = 0; i < 7; ++i) {
                            const qtDay = ((qtFirst - 1 + i) % 7) + 1
                            days.push(loc.dayName(qtDay, Locale.ShortFormat))
                        }
                        return days
                    }

                    Rectangle {
                        width: parent.width / 7
                        height: 24
                        color: "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: Theme.fontSize - 3
                            color: Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.6)
                            font.family: Theme.fontFamily
                            font.bold: true; style: Text.Outline; styleColor: Theme.colTextShadow
                        }
                    }
                }
            }

            Grid {
                id: calendarGrid

                readonly property date firstDay: {
                    const firstOfMonth = new Date(root.displayDate.getFullYear(), root.displayDate.getMonth(), 1)
                    return startOfWeek(firstOfMonth)
                }

                width: parent.width
                height: 240
                columns: 7
                rows: 6

                Repeater {
                    model: 42

                    Rectangle {
                        readonly property date dayDate: {
                            const date = new Date(parent.firstDay)
                            date.setDate(date.getDate() + index)
                            return date
                        }
                        readonly property bool isCurrentMonth: dayDate.getMonth() === root.displayDate.getMonth()
                        readonly property bool isToday: dayDate.toDateString() === root.currentDate.toDateString()
                        readonly property bool isSelected: dayDate.toDateString() === root.selectedDate.toDateString()

                        width: parent.width / 7
                        height: parent.height / 6
                        color: "transparent"

                        Rectangle {
                            anchors.centerIn: parent
                            width: Math.min(parent.width - 4, parent.height - 4, 42)
                            height: width
                            color: isToday ? Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.12) : dayArea.containsMouse ? Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.08) : "transparent"
                            radius: 6

                            Text {
                                anchors.centerIn: parent
                                text: dayDate.getDate()
                                font.pixelSize: Theme.fontSize
                                font.family: Theme.fontFamily
                                color: isToday ? Theme.colWhite : isCurrentMonth ? Theme.colWhite : Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.4)
                                font.bold: isToday
                            }
                        }

                        MouseArea {
                            id: dayArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onWheel: function (wheel) { root.wheelStep(wheel) }
                            onClicked: {
                                root.selectedDate = dayDate
                                root.dateClicked(dayDate)
                            }
                        }
                    }
                }
            }
        }
    }
}
