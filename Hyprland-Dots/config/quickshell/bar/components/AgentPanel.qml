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
        if (s < 60) return "now"
        var m = Math.floor(s / 60), h = Math.floor(m / 60), d = Math.floor(h / 24)
        if (d >= 1) return d + "d " + (h % 24) + "h"
        if (h >= 1) return h + "h " + (m % 60) + "m"
        return m + "m"
    }

    // "6m ago" for a cached reading, so a stale number is never mistaken for
    // a current one.
    function agoText(epochSeconds) {
        var s = Math.max(0, Math.round(Date.now() / 1000 - epochSeconds))
        if (s < 90) return "just now"
        var m = Math.round(s / 60)
        if (m < 60) return m + "m ago"
        var h = Math.round(m / 60)
        return h < 48 ? h + "h ago" : Math.round(h / 24) + "d ago"
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

    component SectionHeader: Item {
        property string label: ""
        width: parent ? parent.width : 0
        height: Math.round(panel.headerSize * 1.9)

        Text {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2
            text: parent.label
            color: Theme.colMuted
            font.pixelSize: panel.headerSize
            font.family: Theme.fontFamily
            font.bold: true
        }
    }

    component Divider: Rectangle {
        width: parent ? parent.width : 0
        height: 1
        color: Theme.colMuted
        opacity: 0.45
    }

    // A label, a track, and a value - used by both charts and the meters, so
    // the three sections read as one family rather than three chart styles.
    component MeterRow: Item {
        id: meterRow
        property string label: ""
        property string value: ""
        property string note: ""
        property real fraction: 0
        property color fill: Theme.colWhite
        property bool emphasise: false

        width: parent ? parent.width : 0
        height: Math.round(panel.labelSize * 2.0)

        Text {
            id: rowLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(panel.labelSize * 4.6)
            text: meterRow.label
            color: meterRow.emphasise ? Theme.colWhite : Theme.colDim
            font.pixelSize: panel.labelSize
            font.family: Theme.fontFamily
            font.bold: meterRow.emphasise
            elide: Text.ElideRight
        }

        Rectangle {
            id: track
            anchors.left: rowLabel.right
            anchors.leftMargin: 8
            anchors.right: rowValue.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            height: 8
            radius: 4
            color: Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.10)

            Rectangle {
                // Addressed through the component's own id rather than a
                // parent chain - the chain is what broke the QR matrix.
                // A non-zero reading always draws at least a sliver, so "a
                // little" never looks identical to "none".
                readonly property real f: Math.max(0, Math.min(1, meterRow.fraction))
                width: f > 0 ? Math.max(parent.width * f, 2) : 0
                height: parent.height
                radius: parent.radius
                color: meterRow.fill
                Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            }
        }

        Text {
            id: rowValue
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(panel.labelSize * 3.4)
            horizontalAlignment: Text.AlignRight
            text: meterRow.value
            color: meterRow.fill
            font.pixelSize: panel.labelSize
            font.family: Theme.fontFamily
            font.bold: true
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
            spacing: 3

            // --------------------------------------------------------- hero
            Item {
                width: parent.width
                height: Math.round(panel.labelSize * 2.2)

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󱚣"
                        color: Theme.colWhite
                        font.pixelSize: panel.labelSize + 2
                        font.family: Theme.fontFamily
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Claude Code"
                        color: Theme.colWhite
                        font.pixelSize: panel.labelSize
                        font.family: Theme.fontFamily
                        font.bold: true
                    }
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: AgentUsage.plan
                    visible: text !== ""
                    color: Theme.colDim
                    font.pixelSize: panel.labelSize
                    font.family: Theme.fontFamily
                }
            }

            Divider {}

            // ------------------------------------------------------- limits
            SectionHeader { label: "ALLOWANCE" }

            Text {
                width: parent.width
                visible: AgentUsage.limitsError !== ""
                text: {
                    panel.nowTick
                    if (AgentUsage.limits.length === 0) return AgentUsage.limitsError
                    var age = AgentUsage.staleAt > 0
                        ? " from " + panel.agoText(AgentUsage.staleAt) : ""
                    return AgentUsage.limitsError + "  Showing the last reading" + age + "."
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
                        ? modelData.label + " wk"
                        : modelData.label
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
                        parts.push("session " + panel.untilText(AgentUsage.session.resetsAt))
                    if (AgentUsage.weekly)
                        parts.push("weekly " + panel.untilText(AgentUsage.weekly.resetsAt))
                    return parts.length ? "resets in  " + parts.join("  ·  ") : ""
                }
                color: Theme.colMuted
                font.pixelSize: panel.headerSize
                font.family: Theme.fontFamily
                wrapMode: Text.WordWrap
            }

            // ---------------------------------------------------- by day
            Divider { visible: AgentUsage.byDay.length > 0 }
            SectionHeader {
                label: "TOKENS BY DAY · LAST 7 DAYS"
                visible: AgentUsage.byDay.length > 0
            }

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
                        return today ? "Today" : Qt.formatDateTime(d, "ddd")
                    }
                    value: panel.compact(modelData.tokens)
                    fraction: panel.maxDay > 0 ? modelData.tokens / panel.maxDay : 0
                    fill: Theme.colWhite
                    emphasise: today
                }
            }

            // -------------------------------------------------- by model
            Divider { visible: AgentUsage.byModel.length > 0 }
            SectionHeader {
                label: "TOKENS BY MODEL · ALL TIME"
                visible: AgentUsage.byModel.length > 0
            }

            // Prompt + completion only. Cache reads are two orders of magnitude
            // larger (2,712M against 11.9M for opus-5 here) and would flatten
            // every other bar to nothing.
            Text {
                width: parent.width
                visible: AgentUsage.byModel.length > 0
                text: "prompt + completion, excluding cache"
                color: Theme.colMuted
                font.pixelSize: panel.headerSize
                font.family: Theme.fontFamily
            }

            Repeater {
                model: AgentUsage.byModel

                MeterRow {
                    required property var modelData
                    // "claude-opus-5" -> "opus-5"; the vendor prefix is the
                    // same on every row and only costs width.
                    label: String(modelData.model).replace(/^claude-/, "")
                                                  .replace(/-\d{8}$/, "")
                    value: panel.compact(modelData.tokens)
                    fraction: panel.maxModel > 0 ? modelData.tokens / panel.maxModel : 0
                    fill: Theme.colWhite
                }
            }

            Text {
                width: parent.width
                visible: AgentUsage.byDay.length === 0 && AgentUsage.limits.length === 0
                text: AgentUsage.busy ? "Reading usage…" : "No Claude Code usage found"
                color: Theme.colMuted
                font.pixelSize: panel.labelSize
                font.family: Theme.fontFamily
            }
        }
    }
}
