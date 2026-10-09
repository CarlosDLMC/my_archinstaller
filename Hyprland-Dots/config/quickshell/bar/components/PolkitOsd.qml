import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import ".."

// The polkit password prompt (PolkitState holds the agent). A centred card in
// the bar's own style, built like ClipboardOsd and ShotOsd: one per screen,
// shown on the focused monitor, keyboard grabbed while it is up.
//
// Enter authenticates, Esc cancels. A click outside does NOT cancel - a stray
// click should not throw away a half-typed password.
PanelWindow {
    id: osd

    property var modelData
    screen: modelData

    readonly property bool onFocusedMonitor:
        Hyprland.focusedMonitor && modelData
        && Hyprland.focusedMonitor.name === modelData.name

    readonly property bool shown: PolkitState.open && onFocusedMonitor
    readonly property var flow: PolkitState.flow

    property bool windowVisible: false
    readonly property int fadeMs: 160
    readonly property real uiScale: 1.35

    // Same type scale as the other centred dialogs: title 14, body 15, hint 11.
    readonly property int cardW: Math.round(560 * uiScale)
    readonly property int pad: Math.round(22 * uiScale)
    readonly property int gap: Math.round(12 * uiScale)
    readonly property int radius: Math.round(18 * uiScale)
    readonly property int titleSize: Math.round(14 * uiScale)
    readonly property int bodySize: Math.round(13 * uiScale)
    readonly property int smallSize: Math.round(11 * uiScale)
    readonly property int fieldH: Math.round(40 * uiScale)

    visible: windowVisible

    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    onShownChanged: {
        if (shown) {
            windowVisible = true
            goneTimer.stop()
            field.text = ""
            Qt.callLater(function () { field.forceActiveFocus() })
        } else {
            field.text = ""
            goneTimer.restart()
        }
    }

    function accept() {
        PolkitState.submit(field.text)
        field.text = ""
    }

    Timer {
        id: goneTimer
        interval: osd.fadeMs
        onTriggered: osd.windowVisible = false
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        opacity: osd.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: osd.fadeMs } }
        MouseArea { anchors.fill: parent }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: osd.cardW
        height: content.implicitHeight + 2 * osd.pad
        radius: osd.radius
        color: Theme.colBg
        border.width: 1
        border.color: Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.14)

        opacity: osd.shown ? 1.0 : 0.0
        scale: osd.shown ? 1.0 : 0.96
        Behavior on opacity { NumberAnimation { duration: osd.fadeMs; easing.type: Easing.OutCubic } }
        Behavior on scale   { NumberAnimation { duration: osd.fadeMs; easing.type: Easing.OutCubic } }

        Column {
            id: content
            x: osd.pad
            y: osd.pad
            width: card.width - 2 * osd.pad
            spacing: osd.gap

            Text {
                text: "AUTHENTICATION REQUIRED"
                color: Theme.colDim
                font.family: Theme.fontFamily
                font.pixelSize: osd.titleSize
                font.letterSpacing: 2
            }

            // What is asking, in polkit's own words ("Authentication is
            // needed to mount ...").
            Text {
                width: parent.width
                text: osd.flow ? osd.flow.message : ""
                wrapMode: Text.WordWrap
                color: Theme.colWhite
                font.family: Theme.fontFamilyContent
                font.pixelSize: osd.bodySize
            }

            Text {
                width: parent.width
                text: osd.flow ? osd.flow.actionId : ""
                visible: text !== ""
                elide: Text.ElideMiddle
                color: Theme.colGrey
                font.family: Theme.fontFamilyContent
                font.pixelSize: osd.smallSize
            }

            Rectangle {
                width: parent.width
                height: osd.fieldH
                radius: 8
                color: Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.06)
                border.width: 1
                border.color: field.activeFocus
                    ? Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.35)
                    : Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.12)

                TextInput {
                    id: field
                    anchors.fill: parent
                    anchors.leftMargin: osd.gap
                    anchors.rightMargin: osd.gap
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    focus: true
                    enabled: osd.flow ? osd.flow.isResponseRequired && !PolkitState.checking : false
                    echoMode: osd.flow && osd.flow.responseVisible ? TextInput.Normal : TextInput.Password
                    // Dots, not "*": JetBrains Mono's code ligatures turn "***"
                    // into one glyph with the middle star raised - a password
                    // field that grew a pyramid at three characters. Ligatures
                    // off as well, for prompts that echo what is typed.
                    passwordCharacter: "\u2022"
                    font.features: { "liga": 0, "calt": 0 }
                    color: Theme.colWhite
                    selectionColor: Theme.colGrey
                    font.family: Theme.fontFamilyContent
                    font.pixelSize: osd.bodySize

                    Keys.onReturnPressed: osd.accept()
                    Keys.onEnterPressed: osd.accept()
                    Keys.onEscapePressed: PolkitState.cancel()

                    // The prompt ("Password:") sits in the empty field.
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: field.text === ""
                        text: PolkitState.checking ? "Checking..."
                            : osd.flow && osd.flow.inputPrompt !== ""
                            ? osd.flow.inputPrompt.replace(/:\s*$/, "") : "Password"
                        color: Theme.colGrey
                        font.family: Theme.fontFamilyContent
                        font.pixelSize: osd.bodySize
                    }
                }
            }

            // A wrong password, or whatever polkit wants to add.
            Text {
                width: parent.width
                readonly property string polkitNote: osd.flow ? osd.flow.supplementaryMessage : ""
                text: PolkitState.error !== "" ? PolkitState.error : polkitNote
                visible: text !== ""
                wrapMode: Text.WordWrap
                color: PolkitState.error !== "" || (osd.flow && osd.flow.supplementaryIsError)
                    ? Theme.colAlert : Theme.colGrey
                font.family: Theme.fontFamilyContent
                font.pixelSize: osd.smallSize
            }

            Text {
                text: "Enter  authenticate    Esc  cancel"
                color: Theme.colGrey
                font.family: Theme.fontFamilyContent
                font.pixelSize: osd.smallSize
            }
        }
    }
}
