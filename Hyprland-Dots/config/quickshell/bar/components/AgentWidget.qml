import QtQuick
import QtQuick.Layouts
import ".."

// Claude Code usage in the bar: the agent glyph and the share of the 5-hour
// session used, which is the number that says whether you are about to be cut
// off. Click for the card - plan, allowance meters, tokens by day and model.
//
// Hidden entirely until there is something to report, the way the battery and
// wifi widgets hide on hardware that is not there: a machine that has never
// run Claude Code should not carry a dead readout.
DropdownWidget {
    id: agentWidget

    popupWidth: 420
    // The cap follows the screen rather than a fixed number: a 620px ceiling
    // left TOKENS BY MODEL below the fold on every monitor. Past the cap the
    // body still scrolls.
    readonly property real maxHeight:
        (barWindow && barWindow.screen ? barWindow.screen.height : 1080) * 0.85
    popupHeight: Math.max(160, Math.min(Math.ceil(measuredHeight) + 30, maxHeight))
    stemAlignment: "center"

    // Keyed on Claude Code being present, NOT on a successful probe: a rate
    // limited endpoint used to make the whole widget disappear from the bar.
    visible: AgentUsage.installed

    property real measuredHeight: 0

    // The singleton does the expensive half only while a card is open. With a
    // bar per screen there can be more than one of these, so this is an OR
    // rather than a plain assignment - closing one must not stop the other.
    onDropdownOpenChanged: AgentUsage.cardOpen = dropdownOpen

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "󱚣"
        // Fixed. The icon never changes colour - usage is not an alert, and a
        // bar item that recolours itself is a distraction for something you
        // look at deliberately. The numbers and their warnings live in the card.
        color: Theme.colWhite
        font.pixelSize: Theme.fontSize
        font.family: Theme.fontFamily
        font.bold: true; style: Text.Outline; styleColor: Theme.colTextShadow
    }

    // Middle-click forces a refresh without waiting for the timer.
    onOtherClicked: button => {
        if (button === Qt.MiddleButton) AgentUsage.refreshFull()
    }

    popupContent: Component {
        AgentPanel {
            anchors.fill: parent
            onContentHeightChanged: agentWidget.measuredHeight = contentHeight
            Component.onCompleted: agentWidget.measuredHeight = contentHeight
        }
    }
}
