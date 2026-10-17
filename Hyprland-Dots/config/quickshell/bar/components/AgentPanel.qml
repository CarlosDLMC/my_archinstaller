import QtQuick
import QtQuick.Layouts
import ".."

// The agents card's body: plan, allowance meters, tokens by day, tokens by
// model. Functionality ported from Omarchy's agents panel (omacom/omarchy,
// MIT, DHH); the styling is this bar's.
//
// Everything arrives from the AgentUsage singleton - this file only draws.
Item {
    id: panel

    readonly property int labelSize: Theme.fontSize - 3
    readonly property int headerSize: Theme.fontSize - 5

    readonly property real contentHeight: body.implicitHeight

    // Largest value in each chart, so both scale to their own busiest entry
    // the way DHH's do - a fixed ceiling would flatten a quiet week to nothing.
    readonly property real maxDay: {
        var m = 0
        for (var i = 0; i < AgentUsage.byDay.length; i++)
            m = Math.max(m, AgentUsage.byDay[i].tokens)
        return m
    }

    readonly property real maxModel: {
        var m = 0
        for (var i = 0; i < AgentUsage.byModel.length; i++)
            m = Math.max(m, AgentUsage.byModel[i].tokens)
        return m
    }

    function compact(n) {
        if (n === undefined || n === null || isNaN(n)) return "—"
        if (n >= 1000000000) return (n / 1000000000).toFixed(1) + "B"
        if (n >= 1000000) return (n / 1000000).toFixed(1) + "M"
        if (n >= 1000) return (n / 1000).toFixed(0) + "k"
        return String(Math.round(n))
    }

    // "in 2h 14m" / "in 3d". The endpoint gives an absolute instant; a
    // countdown is what you actually want to know.
    function untilText(iso) {
        if (!iso) return ""
        var t = Date.parse(iso)
        if (isNaN(t)) return ""
        var s = Math.max(0, Math.round((t - Date.now()) / 1000))
        if (s < 60) return "сейчас"
        var m = Math.floor(s / 60), h = Math.floor(m / 60), d = Math.floor(h / 24)
        if (d >= 1) return d + " дн " + (h % 24) + " ч"
        if (h >= 1) return h + " ч " + (m % 60) + " мин"
        return m + " мин"
    }

    // The date of the oldest record still on disk. Claude Code prunes its own
    // transcripts (cleanupPeriodDays), so this is where the model chart's
    // history actually begins - and it moves forward as old files are deleted.
    //
    // The year is only shown once the history crosses into a previous one:
    // "SINCE 10 AUG" is unambiguous within the current year and shorter.
    readonly property string sinceLabel: {
        if (AgentUsage.oldestHour <= 0)
            return "НЕТ ДАННЫХ"
        var d = new Date(AgentUsage.oldestHour * 3600 * 1000)
        var fmt = d.getFullYear() === new Date().getFullYear() ? "d MMM" : "d MMM yyyy"
        return "С " + Qt.locale().toString(d, fmt).toUpperCase()
    }

    // "6m ago" for a cached reading, so a stale number is never mistaken for
    // a current one.
    function agoText(epochSeconds) {
        var s = Math.max(0, Math.round(Date.now() / 1000 - epochSeconds))
        if (s < 90) return "только что"
        var m = Math.round(s / 60)
        if (m < 60) return m + " мин назад"
        var h = Math.round(m / 60)
        return h < 48 ? h + " ч назад" : Math.round(h / 24) + " дн назад"
    }

    // The one place hue is spent here: an allowance you are about to exhaust.
    //
    // Anthropic grades each limit itself (severity: normal / warning / ...),
    // which is a better trigger than a threshold picked here - it knows where
    // the cliff is for this plan and model. The 80% fallback only covers an
    // entry that arrives without a grading.
    function meterColor(severity, pct) {
        var sev = String(severity || "").toLowerCase()
        if (sev !== "" && sev !== "normal") return Theme.colAlert
        return pct >= 80 ? Theme.colAlert : Theme.colWhite
    }

    // A tick so the reset countdowns move without the panel being reopened.
    property int nowTick: 0
    Timer {
        interval: 30000
        running: AgentUsage.cardOpen
        repeat: true
        onTriggered: panel.nowTick++
    }

    // A plate's caption. Kept as its own type so the plates below read as
    // "caption, rows" rather than repeating the font settings.
    component SectionHeader: ConsoleCaption {
        property string label: ""
        text: label
    }

    // A label, a segmented gauge, and a value - used by both charts and the
    // meters, so the three sections read as one family rather than three
    // chart styles.
    component MeterRow: Item {
        id: meterRow
        property string label: ""
        property string value: ""
        property string note: ""
        property real fraction: 0
        property color fill: Theme.colWhite
        property bool emphasise: false

        width: parent ? parent.width : 0
        height: Math.round(panel.labelSize * 1.35)

        Text {
            id: rowLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(panel.labelSize * 4.6)
            text: meterRow.label
            color: meterRow.emphasise ? Theme.colWhite : Theme.colGrey
            font.pixelSize: panel.labelSize - 1
            font.family: Theme.fontFamily
            font.bold: meterRow.emphasise
            elide: Text.ElideRight
        }

        SegmentGauge {
            id: track
            anchors.left: rowLabel.right
            anchors.leftMargin: 8
            anchors.right: rowValue.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            height: 10
            segments: Math.max(10, Math.round(width / 10))
            // A non-zero reading always lights at least one segment, so "a
            // little" never looks identical to "none".
            readonly property real f: Math.max(0, Math.min(1, meterRow.fraction))
            value: f > 0 ? Math.max(f * 100, 100 / segments) : 0
            // White stays white (the day chart is a quantity, not a state);
            // the allowance meters light in the accent, or the alert hue when
            // nearly spent.
            tint: Qt.colorEqual(meterRow.fill, Theme.colAlert) ? Theme.colAlert : Theme.colAccent
        }

        Text {
            id: rowValue
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(panel.labelSize * 3.0)
            horizontalAlignment: Text.AlignRight
            text: meterRow.value
            color: meterRow.fill
            font.pixelSize: panel.labelSize
            font.family: Theme.fontFamily
            font.bold: true
        }
    }

    // The model chart is a different shape from the day chart, and deliberately
    // so upstream: days are a label, a gauge and a value, while a model gets
    // its name and total on a line of their own with the gauge across the
    // full width under them. Scaled to the heaviest model, so the top row is
    // always full.
    component ModelRow: Item {
        id: modelRow
        property string name: ""
        property string total: ""
        property string detail: ""
        property real share: 0

        width: parent ? parent.width : 0
        height: modelName.implicitHeight + 4 + 8

        Text {
            id: modelName
            // Hovering swaps the name for the split. Upstream puts this in a
            // tooltip; this bar has no tooltip layer, and the row is the one
            // place the numbers can go without adding one.
            text: modelHover.containsMouse && modelRow.detail !== ""
                ? modelRow.detail : modelRow.name
            color: modelHover.containsMouse ? Theme.colGrey : Theme.colWhite
            font.pixelSize: panel.labelSize - 1
            font.family: Theme.fontFamily
            elide: Text.ElideRight
            anchors.left: parent.left
            anchors.right: modelTotal.left
            anchors.rightMargin: 8
            anchors.top: parent.top
        }

        Text {
            id: modelTotal
            text: modelRow.total
            color: Theme.colWhite
            font.pixelSize: panel.labelSize - 1
            font.family: Theme.fontFamily
            font.bold: true
            anchors.right: parent.right
            anchors.top: parent.top
        }

        SegmentGauge {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 8
            segments: Math.max(10, Math.round(width / 10))
            value: Math.max(0, Math.min(1, modelRow.share)) * 100
        }

        MouseArea {
            id: modelHover
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: body
            width: parent.width
            spacing: 8

            // --------------------------------------------------------- hero
            Item {
                width: parent.width
                height: Math.round(panel.labelSize * 1.8)

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󱚣"
                        color: Theme.colWhite
                        font.pixelSize: panel.labelSize + 2
                        font.family: Theme.fontFamily
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "CLAUDE CODE"
                        color: Theme.colWhite
                        font.pixelSize: panel.labelSize
                        font.family: Theme.fontFamily
                        font.bold: true
                        font.letterSpacing: 1
                    }
                }

                ConsoleCaption {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: AgentUsage.plan.toUpperCase()
                    visible: text !== ""
                }
            }

            // ------------------------------------------------------- limits
            ConsolePlate {
                SectionHeader { label: "ЛИМИТЫ" }

                Text {
                    width: parent.width
                    visible: AgentUsage.limitsError !== ""
                    text: {
                        panel.nowTick
                        if (AgentUsage.limits.length === 0) return AgentUsage.limitsError
                        var age = AgentUsage.staleAt > 0
                            ? " от " + panel.agoText(AgentUsage.staleAt) : ""
                        return AgentUsage.limitsError + "  Показано последнее значение" + age + "."
                    }
                    color: Theme.colAlert
                    font.pixelSize: panel.headerSize
                    font.family: Theme.fontFamily
                    wrapMode: Text.WordWrap
                }

                Repeater {
                    model: AgentUsage.limits

                    MeterRow {
                        required property var modelData
                        // A model-scoped budget says which model it applies to;
                        // the two headline ones speak for the whole plan.
                        label: modelData.window === "7 days" && modelData.label !== "Weekly"
                            ? modelData.label + " нед"
                            : ({ "Session": "Сессия", "Weekly": "Неделя" })[modelData.label] || modelData.label
                        value: Math.round(modelData.percent) + "%"
                        fraction: modelData.percent / 100
                        fill: panel.meterColor(modelData.severity, modelData.percent)
                        // The server marks the limit currently binding you; that is
                        // the row worth the extra weight, not a fixed one.
                        emphasise: modelData.active === true
                    }
                }

                // Reset countdowns, on one line rather than a row each.
                Text {
                    width: parent.width
                    visible: AgentUsage.session !== null || AgentUsage.weekly !== null
                    text: {
                        panel.nowTick        // re-evaluate on the tick
                        var parts = []
                        if (AgentUsage.session)
                            parts.push("сессия " + panel.untilText(AgentUsage.session.resetsAt))
                        if (AgentUsage.weekly)
                            parts.push("неделя " + panel.untilText(AgentUsage.weekly.resetsAt))
                        return parts.length ? "сброс через  " + parts.join("  ·  ") : ""
                    }
                    color: Theme.colGrey
                    font.pixelSize: panel.headerSize
                    font.family: Theme.fontFamily
                    wrapMode: Text.WordWrap
                }
            }

            // ---------------------------------------------------- by day
            ConsolePlate {
                visible: AgentUsage.byDay.length > 0

                SectionHeader { label: "ТОКЕНЫ ПО ДНЯМ · 7 ДНЕЙ" }

                Repeater {
                    model: AgentUsage.byDay

                    MeterRow {
                        required property var modelData
                        required property int index
                        // Today is the last entry, and it is the one you are
                        // actually spending, so it carries the weight.
                        readonly property bool today: index === AgentUsage.byDay.length - 1
                        label: {
                            var d = new Date(modelData.day + "T00:00:00")
                            return today ? "Сегодня" : Qt.locale().toString(d, "ddd")
                        }
                        value: panel.compact(modelData.tokens)
                        fraction: panel.maxDay > 0 ? modelData.tokens / panel.maxDay : 0
                        fill: Theme.colWhite
                        emphasise: today
                    }
                }
            }

            // -------------------------------------------------- by model
            ConsolePlate {
                visible: AgentUsage.byModel.length > 0
                spacing: 8

                // Not "ALL TIME": Claude Code deletes transcripts older than
                // cleanupPeriodDays, so the chart begins wherever the oldest
                // survivor does. The date comes from the data, not from the
                // retention setting, so it stays true whatever that is set to
                // and moves forward on its own as old files are pruned.
                //
                // Prompt + completion only. Cache reads are two orders of
                // magnitude larger (2,712M against 11.9M for opus-5 here) and
                // would flatten every other bar to nothing.
                SectionHeader { label: "ТОКЕНЫ ПО МОДЕЛЯМ · " + panel.sinceLabel }

                Text {
                    width: parent.width
                    text: "запрос + ответ, без кэша"
                    color: Theme.colGrey
                    font.pixelSize: panel.headerSize
                    font.family: Theme.fontFamily
                }

                Repeater {
                    model: AgentUsage.byModel

                    ModelRow {
                        required property var modelData
                        // "claude-opus-5" -> "opus-5"; the vendor prefix is the
                        // same on every row and only costs width.
                        name: String(modelData.model).replace(/^claude-/, "")
                                                     .replace(/-\d{8}$/, "")
                        total: panel.compact(modelData.tokens)
                        detail: "ввод " + panel.compact(modelData.input)
                              + " · вывод " + panel.compact(modelData.output)
                              + " · кэш " + panel.compact(modelData.cacheRead)
                        share: panel.maxModel > 0 ? modelData.tokens / panel.maxModel : 0
                    }
                }
            }

            Text {
                width: parent.width
                visible: AgentUsage.byDay.length === 0 && AgentUsage.limits.length === 0
                text: AgentUsage.busy ? "Чтение данных…" : "Данных Claude Code нет"
                color: Theme.colGrey
                font.pixelSize: panel.labelSize
                font.family: Theme.fontFamily
            }
        }
    }
}
