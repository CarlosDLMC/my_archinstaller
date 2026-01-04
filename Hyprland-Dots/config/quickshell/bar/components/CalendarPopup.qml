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

    function weekStartJs() {
        return Qt.locale().firstDayOfWeek % 7
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
        anchor.rect.y: 32
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
                height: 36

                Rectangle {
                    width: 36
                    height: 36
                    radius: 6
                    color: prevMonthArea.containsMouse ? Qt.rgba(Theme.colFg.r, Theme.colFg.g, Theme.colFg.b, 0.12) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "󰅁"
                        font.pixelSize: 24
                        color: Theme.colFg
                        font.family: Theme.fontFamily
                    }

                    MouseArea {
                        id: prevMonthArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            let newDate = new Date(root.displayDate)
                            newDate.setMonth(newDate.getMonth() - 1)
                            root.displayDate = newDate
                        }
                    }
                }

                Text {
                    width: parent.width - 72
                    height: 36
                    text: root.displayDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")
                    font.pixelSize: Theme.fontSize + 2
                    color: Theme.colFg
                    font.family: Theme.fontFamily
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                Rectangle {
                    width: 36
                    height: 36
                    radius: 6
                    color: nextMonthArea.containsMouse ? Qt.rgba(Theme.colFg.r, Theme.colFg.g, Theme.colFg.b, 0.12) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "󰅂"
                        font.pixelSize: 24
                        color: Theme.colFg
                        font.family: Theme.fontFamily
                    }

                    MouseArea {
                        id: nextMonthArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            let newDate = new Date(root.displayDate)
                            newDate.setMonth(newDate.getMonth() + 1)
                            root.displayDate = newDate
                        }
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
                            color: Qt.rgba(Theme.colFg.r, Theme.colFg.g, Theme.colFg.b, 0.6)
                            font.family: Theme.fontFamily
                            font.bold: true
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
                            color: isToday ? Qt.rgba(Theme.colFg.r, Theme.colFg.g, Theme.colFg.b, 0.12) : dayArea.containsMouse ? Qt.rgba(Theme.colFg.r, Theme.colFg.g, Theme.colFg.b, 0.08) : "transparent"
                            radius: 6

                            Text {
                                anchors.centerIn: parent
                                text: dayDate.getDate()
                                font.pixelSize: Theme.fontSize
                                font.family: Theme.fontFamily
                                color: isToday ? Theme.colFg : isCurrentMonth ? Theme.colFg : Qt.rgba(Theme.colFg.r, Theme.colFg.g, Theme.colFg.b, 0.4)
                                font.bold: isToday
                            }
                        }

                        MouseArea {
                            id: dayArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
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
